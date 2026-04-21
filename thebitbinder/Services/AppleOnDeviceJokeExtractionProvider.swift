//
//  AppleOnDeviceJokeExtractionProvider.swift
//  thebitbinder
//
//  On-device joke extraction using Apple's Foundation Models framework
//  (iOS 26+ / Apple Intelligence). Runs the ~3B-parameter system language
//  model locally with guided generation so the output is already a typed
//  array of `AIExtractedJoke` — no JSON parsing / repair needed.
//
//  Characteristics vs cloud providers:
//  - Free, private, offline. No API key. No rate limits.
//  - Available only on Apple-Intelligence-capable devices (iPhone 15 Pro+,
//    M-series iPads/Macs) running iOS / iPadOS / macOS 26+.
//  - Context window is smaller than cloud models, so very large documents
//    are still chunked by the pipeline coordinator.
//
//  The whole file compiles on older SDKs thanks to `#if canImport` — when
//  FoundationModels isn't present, `isConfigured()` returns `false` and the
//  manager falls through to the next provider automatically.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleOnDeviceJokeExtractionProvider: AIJokeExtractionProvider {

    let providerType: AIProviderType = .appleOnDevice

    // MARK: - Configuration

    func isConfigured() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    // MARK: - Extraction

    func extractJokes(from text: String) async throws -> [AIExtractedJoke] {
        try await extractJokes(from: text, hints: .unspecified)
    }

    /// Hints-aware entry point. Structured hints go into `LanguageModelSession`
    /// instructions (the system-prompt slot) rather than being prefixed to
    /// the user message — that's the cleaner place for them and frees the
    /// user message for pure document content, respecting the on-device
    /// context window.
    func extractJokes(from text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await runOnDevice(text: text, hints: hints)
        }
        #endif

        // Older OS or Foundation Models framework not present — this provider
        // shouldn't have been selected in the first place, but surface a
        // clear error so the manager can skip to the next provider.
        throw AIProviderError.notAvailable(.appleOnDevice)
    }

    // MARK: - FoundationModels implementation (iOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func runOnDevice(text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        // Build instructions: base prompt + the user's hint summary (if any).
        // The instructions slot is the right place for "how to interpret the
        // input" — equivalent to a system prompt. The user message stays
        // pure document content.
        var instructionsText = Self.baseInstructions
        if let prefix = hints.aiPromptPrefix() {
            instructionsText += "\n\n" + prefix
        }

        // Cloud providers receive the hint prefix prepended to `text`; the
        // on-device provider pulls hints from the instructions block
        // instead, so strip any prefix the caller added to `text`.
        let documentText = ExtractionHints.stripPromptPrefix(from: text)

        let session = LanguageModelSession(instructions: instructionsText)

        do {
            let response = try await session.respond(
                to: documentText,
                generating: [OnDeviceJoke].self
            )
            return response.content.map { $0.asAIExtractedJoke() }
        } catch {
            // Wrap in the shared provider-error type so the manager can
            // treat it uniformly with other provider failures.
            throw AIProviderError.runFailed(.appleOnDevice, error.localizedDescription)
        }
    }

    /// Base instruction block for the on-device model. Kept close to the
    /// shared cloud prompt's spirit but trimmed for the smaller context
    /// window and relying on guided generation for the output shape.
    /// User hint summary (when present) is appended at call time.
    private static let baseInstructions: String = """
    You are a comedy-writing assistant reviewing a stand-up comedian's file.
    Return EVERY piece of text from the file as a separate entry — do not skip,
    summarise, merge, or paraphrase.

    For each entry, include:
      - jokeText: the exact wording from the file (verbatim)
      - confidence: 0.0–1.0
          0.8+  clearly a joke / bit / punchline
          0.5–0.79  possibly a joke, premise, tag, or crowd-work line
          below 0.5  not a joke (title, note, header, metadata) but still include it
      - humorMechanism: type of humor, or leave empty
      - title: detected title, or leave empty

    Split on blank lines, numbered items, bullet points, and separator lines
    (---, ***, ===, //, NEXT JOKE, NEW BIT).

    If the input begins with [EXTRACTION HINTS FROM USER], use the hints but do
    NOT include them as an output entry.
    """
    #endif
}

// MARK: - Generable output shape

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct OnDeviceJoke {
    @Guide(description: "The exact joke or text fragment, preserved verbatim from the source.")
    let jokeText: String

    @Guide(description: "Confidence that this fragment is a joke, from 0.0 to 1.0. 0.8+ = clearly a joke; 0.5–0.79 = possibly; below 0.5 = probably not a joke but still include.")
    let confidence: Double

    @Guide(description: "Type of humor (observational, self-deprecating, wordplay, etc.) or empty string if unclear.")
    let humorMechanism: String

    @Guide(description: "Detected title for this entry, or empty string if none.")
    let title: String

    func asAIExtractedJoke() -> AIExtractedJoke {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMech  = humorMechanism.trimmingCharacters(in: .whitespacesAndNewlines)
        let clamped = max(0.0, min(1.0, confidence))
        return AIExtractedJoke(
            jokeText: jokeText,
            humorMechanism: trimmedMech.isEmpty ? nil : trimmedMech,
            confidence: Float(clamped),
            explanation: nil,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            tags: []
        )
    }
}
#endif
