//
//  AppleOnDeviceJokeExtractionProvider.swift
//  thebitbinder
//
//  On-device joke extraction using Apple's Foundation Models framework
//  (iOS 26+ / Apple Intelligence). Uses permissive guardrails with string
//  generation so comedy content isn't blocked.
//
//  The on-device model has a small context window, so we:
//    - Keep instructions short and focused on one task: splitting text
//    - Chunk large documents and process each chunk separately
//    - Ask for a simple numbered-list format (not complex JSON)
//    - Parse robustly with multiple fallback strategies
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleOnDeviceJokeExtractionProvider: AIJokeExtractionProvider {

    let providerType: AIProviderType = .appleOnDevice

    /// Max chars per chunk sent to the on-device model. Conservative to leave
    /// room for instructions (~300 chars) and the response in the context window.
    private static let maxChunkSize = 3000

    func isConfigured() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel(guardrails: .permissiveContentTransformations).isAvailable
        }
        #endif
        return false
    }

    func extractJokes(from text: String) async throws -> [AIExtractedJoke] {
        try await extractJokes(from: text, hints: .unspecified)
    }

    func extractJokes(from text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await runOnDevice(text: text, hints: hints)
        }
        #endif
        throw AIProviderError.notAvailable(.appleOnDevice)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func runOnDevice(text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        let stripped = ExtractionHints.stripPromptPrefix(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            throw AIProviderError.noJokesFound(.appleOnDevice)
        }

        let chunks = Self.chunkText(stripped, maxSize: Self.maxChunkSize)
        print(" [OnDevice] Processing \(chunks.count) chunk(s) from \(stripped.count) chars")

        var allJokes: [AIExtractedJoke] = []

        for (i, chunk) in chunks.enumerated() {
            do {
                let jokes = try await processChunk(chunk, hints: hints)
                print(" [OnDevice] Chunk \(i+1)/\(chunks.count): \(jokes.count) joke(s)")
                allJokes.append(contentsOf: jokes)
            } catch {
                print(" [OnDevice] Chunk \(i+1) failed: \(error.localizedDescription)")
                if chunks.count == 1 { throw error }
            }
        }

        guard !allJokes.isEmpty else {
            throw AIProviderError.noJokesFound(.appleOnDevice)
        }
        return allJokes
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func processChunk(_ chunk: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        var instructions = Self.baseInstructions
        if let prefix = hints.aiPromptPrefix() {
            instructions += "\n" + prefix
        }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)

        do {
            let response = try await session.respond(to: chunk)
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !output.isEmpty, !Self.isRefusal(output) else {
                throw AIProviderError.runFailed(.appleOnDevice, "Model refused to process the content")
            }

            return Self.parseResponse(output)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.runFailed(.appleOnDevice, error.localizedDescription)
        }
    }

    // MARK: - Text Chunking

    /// Split text into chunks that fit the on-device model's context window.
    /// Splits on blank-line boundaries to keep jokes intact.
    private static func chunkText(_ text: String, maxSize: Int) -> [String] {
        guard text.count > maxSize else { return [text] }

        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current = ""

        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if current.isEmpty {
                current = trimmed
            } else if current.count + trimmed.count + 2 <= maxSize {
                current += "\n\n" + trimmed
            } else {
                chunks.append(current)
                current = trimmed
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }

        // If a single paragraph exceeds maxSize, hard-split it
        return chunks.flatMap { chunk -> [String] in
            guard chunk.count > maxSize else { return [chunk] }
            var parts: [String] = []
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let end = chunk.index(start, offsetBy: maxSize, limitedBy: chunk.endIndex) ?? chunk.endIndex
                parts.append(String(chunk[start..<end]))
                start = end
            }
            return parts
        }
    }

    // MARK: - Response Parsing

    /// Parse the model's response. Tries JSON first, then numbered list,
    /// then line-delimited, then separator-delimited.
    private static func parseResponse(_ text: String) -> [AIExtractedJoke] {
        // Try 1: Full JSON array
        if let jokes = tryParseJSON(text), !jokes.isEmpty {
            return jokes
        }

        // Try 2: Numbered list (1. joke text\n2. joke text)
        if let jokes = tryParseNumberedList(text), !jokes.isEmpty {
            return jokes
        }

        // Try 3: Separator-delimited (--- or similar)
        if let jokes = tryParseSeparatorDelimited(text), !jokes.isEmpty {
            return jokes
        }

        // Try 4: Blank-line separated blocks
        let blocks = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 15 && !looksLikeInstruction($0) }

        if blocks.count >= 2 {
            return blocks.map { AIExtractedJoke(jokeText: $0, confidence: 0.6) }
        }

        // Last resort: the model returned the whole thing as one block
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 15 && !looksLikeInstruction(cleaned) {
            return [AIExtractedJoke(jokeText: cleaned, confidence: 0.5)]
        }

        return []
    }

    private static func tryParseJSON(_ text: String) -> [AIExtractedJoke]? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return nil }
        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([AIExtractedJoke].self, from: data)
    }

    private static func tryParseNumberedList(_ text: String) -> [AIExtractedJoke]? {
        let pattern = #"(?:^|\n)\s*\d+\s*[.)\-:–—]\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard matches.count >= 2 else { return nil }

        var jokes: [AIExtractedJoke] = []
        for i in 0..<matches.count {
            let matchEnd = matches[i].range.location + matches[i].range.length
            let nextStart = (i + 1 < matches.count) ? matches[i + 1].range.location : text.utf16.count

            let startIdx = text.utf16.index(text.utf16.startIndex, offsetBy: matchEnd)
            let endIdx = text.utf16.index(text.utf16.startIndex, offsetBy: nextStart)

            guard let s = String.Index(startIdx, within: text),
                  let e = String.Index(endIdx, within: text) else { continue }

            let jokeText = String(text[s..<e]).trimmingCharacters(in: .whitespacesAndNewlines)
            if jokeText.count > 10 {
                jokes.append(AIExtractedJoke(jokeText: jokeText, confidence: 0.7))
            }
        }
        return jokes.isEmpty ? nil : jokes
    }

    private static func tryParseSeparatorDelimited(_ text: String) -> [AIExtractedJoke]? {
        let separators = ["---", "***", "===", "- - -"]
        for sep in separators {
            let parts = text.components(separatedBy: sep)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count > 10 && !looksLikeInstruction($0) }
            if parts.count >= 2 {
                return parts.map { AIExtractedJoke(jokeText: $0, confidence: 0.6) }
            }
        }
        return nil
    }

    /// Filter out model meta-commentary that isn't joke content.
    private static func looksLikeInstruction(_ text: String) -> Bool {
        let lower = text.lowercased()
        let metaPhrases = [
            "here are the jokes", "here is the list", "extracted jokes",
            "the following", "below are", "i found", "here's what i found",
            "json array", "note:", "numbered list"
        ]
        return metaPhrases.contains { lower.hasPrefix($0) || lower.contains($0) }
    }

    // MARK: - Refusal Detection

    private static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let patterns = [
            "i can't help with", "i'm not able to", "i cannot help",
            "i'm unable to", "sorry, i can't", "i can not help",
            "as an ai", "i don't think i can help"
        ]
        return patterns.contains { lower.contains($0) }
    }

    // MARK: - Instructions

    private static let baseInstructions: String = """
    You are splitting a comedian's text into individual jokes. \
    Number each joke. Keep the comedian's exact words. \
    Do not skip, merge, or rewrite anything. \
    Split on blank lines, numbers, bullets, or topic changes. \
    Output ONLY a numbered list like:
    1. first joke text here
    2. second joke text here
    """
    #endif
}
