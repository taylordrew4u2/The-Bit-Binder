//
//  TextRecognitionService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import UIKit
import Vision
import VisionKit

// MARK: - Joke Import Candidate for User Validation
struct JokeImportCandidate: Identifiable {
    let id = UUID()
    var content: String
    var suggestedTitle: String
    var isComplete: Bool
    var confidence: Double
    var issues: [String]
    var suggestedFix: String?
    var userApproved: Bool = false
    var userEdited: Bool = false
    
    var needsReview: Bool {
        return !isComplete || confidence < 0.8 || !issues.isEmpty
    }
    
    var statusDescription: String {
        if isComplete && confidence >= 0.8 {
            return " Complete joke detected"
        } else if confidence >= 0.6 {
            return " Possibly incomplete - please verify"
        } else {
            return " May be missing parts - please review"
        }
    }
}

class TextRecognitionService {
    
    static func recognizeText(from image: UIImage) async throws -> String {
        print(" OCR: Starting recognition, image: \(image.size.width)x\(image.size.height)")
        
        guard let cgImage = image.cgImage else {
            print(" OCR: Failed to get CGImage")
            throw TextRecognitionError.invalidImage
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        try requestHandler.perform([request])
        var observations = request.results ?? []
        if observations.isEmpty {
            // Fallback: try fast recognition if accurate returned nothing
            let fastRequest = VNRecognizeTextRequest()
            fastRequest.recognitionLevel = .fast
            fastRequest.usesLanguageCorrection = true
            try? requestHandler.perform([fastRequest])
            observations = fastRequest.results ?? []
        }
        if observations.isEmpty {
            // Locale-hinted pass for en-US
            let localeRequest = VNRecognizeTextRequest()
            localeRequest.recognitionLevel = .accurate
            localeRequest.usesLanguageCorrection = true
            localeRequest.recognitionLanguages = ["en-US"]
            try? requestHandler.perform([localeRequest])
            observations = localeRequest.results ?? []
        }
        
        if observations.isEmpty {
            print(" OCR: No results")
            throw TextRecognitionError.noTextFound
        }
        
        print(" OCR: Found \(observations.count) text blocks")
        
        let recognizedText = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.joined(separator: "\n")
        
        print(" OCR: Total \(recognizedText.count) chars")
        return recognizedText
    }
    
    /// Light-weight OCR repair to improve extraction fidelity
    static func repairOCRText(_ text: String) -> String {
        var t = text
        // Normalize line endings
        t = t.replacingOccurrences(of: "\r\n|\r", with: "\n", options: .regularExpression)
        // Remove hyphenated line breaks like "hy-\n phen"
        t = t.replacingOccurrences(of: "-\\s*\\n", with: "", options: .regularExpression)
        // Collapse 3+ newlines to 2
        t = t.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        // Trim trailing spaces before newline
        t = t.replacingOccurrences(of: "[ \t]+\n", with: "\n", options: .regularExpression)
        // Merge obvious broken lines: if previous line does not end with punctuation, join with a space
        t = t.replacingOccurrences(of: "(?<=[^.!?\\-])\n(?=[a-z])", with: " ", options: .regularExpression)
        // Normalize multiple spaces
        t = t.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        return t
    }
    
    static func extractJokes(from text: String) -> [String] {
        print(" EXTRACT: Input \(text.count) chars")
        guard !text.isEmpty else {
            print(" EXTRACT: Empty")
            return []
        }
        
        let cleaned = repairOCRText(text)
        
        let preview = String(cleaned.prefix(100)).replacingOccurrences(of: "\n", with: "\\n")
        print(" EXTRACT: Preview: \(preview)")
        
        var jokes: [String] = []
        
        // Method 1: Numbered lists (1. 2. 3.) - PRESERVE NEWLINES!
        print(" Method 1: Numbered lists")
        let pattern = #"(?:^|\n)\s*\d+[\.\)]\s*"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            let matches = regex.matches(in: cleaned, options: [], range: range)
            print(" Found \(matches.count) numbered markers")
            
            if matches.count >= 2 {
                var lastEnd = cleaned.startIndex
                for (i, match) in matches.enumerated() {
                    if let r = Range(match.range, in: cleaned) {
                        if i > 0 {
                            let joke = String(cleaned[lastEnd..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if joke.count >= 5 {
                                print(" Joke \(i): \(joke.prefix(30))...")
                                jokes.append(joke)
                            }
                        }
                        lastEnd = r.upperBound
                    }
                }
                let final = String(cleaned[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if final.count >= 5 {
                    print(" Final: \(final.prefix(30))...")
                    jokes.append(final)
                }
                if !jokes.isEmpty {
                    print(" Method 1 SUCCESS: \(jokes.count) jokes")
                    return jokes
                }
            }
        }
        
        // Method 2: Double line breaks
        print(" Method 2: Paragraphs")
        let paras = cleaned.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        print(" Found \(paras.count) paragraphs")
        if paras.count >= 2 {
            for p in paras {
                let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count >= 5 {
                    print(" Para: \(t.prefix(30))...")
                    jokes.append(t)
                }
            }
            if !jokes.isEmpty {
                print(" Method 2 SUCCESS: \(jokes.count) jokes")
                return jokes
            }
        }
        
        // Method 3: Group by single blank lines (accumulate contiguous lines)
        print(" Method 3: Line groups")
        let lines = cleaned.components(separatedBy: "\n")
        let boundaryMarkers: Set<String> = ["---", "***", "—", "— — —", "[break]", "###"]
        print(" Found \(lines.count) lines")
        if lines.count >= 2 {
            var currentBlock: [String] = []
            func flushBlock() {
                let t = currentBlock.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count >= 5 { jokes.append(t) }
                currentBlock.removeAll()
            }
            for l in lines {
                let trimmed = l.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || boundaryMarkers.contains(trimmed) {
                    if !currentBlock.isEmpty { flushBlock() }
                } else {
                    currentBlock.append(trimmed)
                }
            }
            if !currentBlock.isEmpty { flushBlock() }
            if !jokes.isEmpty {
                print(" Method 3 SUCCESS: \(jokes.count) jokes")
                return jokes
            }
        }
        
        // Method 4: Sentences
        print(" Method 4: Sentences")
        let sents = cleaned.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var curr = ""
        for s in sents {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                curr += t + ". "
                if curr.count >= 50 {
                    print(" Sent: \(curr.prefix(30))...")
                    jokes.append(curr.trimmingCharacters(in: .whitespacesAndNewlines))
                    curr = ""
                }
            }
        }
        if curr.count >= 5 {
            print(" Rest: \(curr.prefix(30))...")
            jokes.append(curr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !jokes.isEmpty {
            print(" Method 4 SUCCESS: \(jokes.count) jokes")
            return jokes
        }
        
        // Method 5: Whole text
        print(" Method 5: Whole text")
        let whole = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if whole.count >= 3 {
            print(" Whole: \(whole.prefix(30))...")
            jokes.append(whole)
        }
        
        print(" FINAL: \(jokes.count) jokes")
        return jokes
    }
    
    // MARK: - Helper Functions for Title Generation and Validation
    
    /// Generates a title from joke content and validates the joke for completeness
    static func generateTitleFromJoke(_ jokeContent: String) -> (title: String, isValid: Bool) {
        let trimmed = jokeContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Minimum length check - avoid incomplete jokes
        let minimumLength = 5  // Reduced from 12 - even short jokes are valid
        
        // Check if joke is too short
        if trimmed.count < minimumLength {
            print(" VALIDATION: Joke too short (\(trimmed.count) < \(minimumLength)): \(trimmed)")
            return (title: "", isValid: false)
        }
        
        // Check for incomplete sentences (ends with only partial punctuation or no punctuation)
        let lastChar = trimmed.last ?? " "
        let endsWithoutPunctuation = !trimmed.hasSuffix(".") && !trimmed.hasSuffix("!") && !trimmed.hasSuffix("?")
        
        let looksIncomplete = trimmed.contains("...") || trimmed.contains("…") || 
                             (lastChar.isLetter && endsWithoutPunctuation && trimmed.count < 100)
        
        if looksIncomplete {
            print(" VALIDATION: Incomplete joke detected: \(trimmed.prefix(50))...")
            return (title: "", isValid: false)
        }
        
        // Generate title from first sentence or first 50 characters
        var title = ""
        let endMarkers = CharacterSet(charactersIn: ".!?")
        
        if let firstSentenceEnd = trimmed.rangeOfCharacter(from: endMarkers) {
            title = String(trimmed[trimmed.startIndex..<firstSentenceEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else {
            title = String(trimmed.prefix(50)).trimmingCharacters(in: .whitespaces)
        }
        
        // Ensure title is not empty and is reasonable
        if title.isEmpty {
            title = String(trimmed.prefix(50)).trimmingCharacters(in: .whitespaces)
        }
        
        // Fallback: if title is empty, mark as invalid
        if title.isEmpty || title.count < 2 {
            print(" VALIDATION: Title too short or empty: '\(title)'")
            return (title: "", isValid: false)
        }
        
        print(" VALIDATION: Valid joke with title '\(title.prefix(40))'")
        return (title: title, isValid: true)
    }
    
    /// Filters out incomplete or invalid jokes
    static func filterValidJokes(_ jokes: [String]) -> [String] {
        return jokes.filter { joke in
            let (_, isValid) = generateTitleFromJoke(joke)
            return isValid
        }
    }
}

enum TextRecognitionError: Error {
    case invalidImage
    case noTextFound
    case recognitionFailed
}

/// Enum representing different types of list formatting detected in text
enum ListFormatType {
    case numbered
    case bulletPoints
    case lettered
    case romanNumerals
    case paragraphs
    case lineBreaks
    case plainText
    
    var description: String {
        switch self {
        case .numbered: return "Numbered List"
        case .bulletPoints: return "Bullet Points"
        case .lettered: return "Lettered List"
        case .romanNumerals: return "Roman Numerals"
        case .paragraphs: return "Paragraphs"
        case .lineBreaks: return "Line Breaks"
        case .plainText: return "Plain Text"
        }
    }
}

/// Structure for analyzing joke completeness based on structural patterns
struct JokeStructureAnalysis {
    let score: Int
    let patterns: [String]
    let isLikelyComplete: Bool
}

// MARK: - Smart Joke Detection Functions
extension TextRecognitionService {
    
    /// Determines if text appears to be a complete, standalone joke using context clues
    static func isCompleteJoke(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count < 15 { return false }
        
        // Question-Answer format
        if trimmed.contains("?") {
            let parts = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let afterQuestion = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if afterQuestion.count >= 5 { return true }
            }
        }
        
        // Multiple sentences
        let sentenceCount = TextRecognitionService.countSentences(trimmed)
        if sentenceCount >= 2 { return true }
        
        // Multiple lines
        let lineCount = trimmed.components(separatedBy: "\n").count
        if lineCount >= 2 { return true }
        
        // Joke markers + punctuation
        let endsWithProperPunctuation = trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
        let jokeMarkers = ["why", "how", "what", "when", "said", "asked", "replied", "walks", "because"]
        let lowerText = trimmed.lowercased()
        let hasJokeMarkers = jokeMarkers.contains { lowerText.contains($0) }
        
        if hasJokeMarkers && endsWithProperPunctuation { return true }
        
        // Substantial text with proper punctuation
        if trimmed.count >= 50 && endsWithProperPunctuation { return true }
        
        return false
    }
    
    /// Counts the number of sentences in text
    static func countSentences(_ text: String) -> Int {
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        var count = 0
        for char in text.unicodeScalars {
            if sentenceEnders.contains(char) { count += 1 }
        }
        return count
    }
    
    /// Intelligently cleans joke text by removing leading markers
    static func smartCleanJoke(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let bulletPatterns = [
            #"^\s*[•\-\*>⁃]\s*"#,
            #"^\s*\d+[\.\)]\s*"#,
            #"^\s*[a-zA-Z][\.\)]\s*"#,
            #"^\s*[IVXLCDMivxlcdm]+[\.\)]\s*"#,
            #"^\s*[]\s*"#
        ]
        
        for pattern in bulletPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Detects if text contains joke list formatting
    static func containsJokeListFormatting(_ text: String) -> Bool {
        let patterns = [
            #"(?:^|\n)\s*[•\-\*>⁃]\s*"#,
            #"(?:^|\n)\s*\d+[\.\)]\s*"#,
            #"(?:^|\n)\s*[a-zA-Z][\.\)]\s*"#,
            #"(?:^|\n)\s*[IVXLCDMivxlcdm]+[\.\)]\s*"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.matches(in: text, options: [], range: range).count >= 2 {
                    return true
                }
            }
        }
        return false
    }
    
    /// Identifies the type of list formatting in text
    static func detectListType(_ text: String) -> ListFormatType {
        let numberedPattern = #"(?:^|\n)\s*\d+[\.\)]\s*"#
        if let regex = try? NSRegularExpression(pattern: numberedPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.matches(in: text, options: [], range: range).count >= 2 {
                return .numbered
            }
        }
        
        let bulletPattern = #"(?:^|\n)\s*[•\-\*>⁃]\s*"#
        if let regex = try? NSRegularExpression(pattern: bulletPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.matches(in: text, options: [], range: range).count >= 2 {
                return .bulletPoints
            }
        }
        
        if text.contains("\n\n") { return .paragraphs }
        if text.contains("\n") { return .lineBreaks }
        
        return .plainText
    }
    
    /// Analyzes joke structure quality
    static func analyzeJokeStructure(_ text: String) -> JokeStructureAnalysis {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var score = 0
        var patterns: [String] = []
        
        if trimmed.contains("?") {
            score += 25
            patterns.append("Contains question")
        }
        
        let sentenceCount = TextRecognitionService.countSentences(trimmed)
        if sentenceCount >= 2 {
            score += 20
            patterns.append("Multiple sentences")
        }
        
        if trimmed.count >= 50 {
            score += 20
            patterns.append("Substantial length")
        }
        
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            score += 15
            patterns.append("Proper ending punctuation")
        }
        
        return JokeStructureAnalysis(score: score, patterns: patterns, isLikelyComplete: score >= 40)
    }
}

extension String {
    /// Normalized prefix used for duplicate detection
    func normalizedPrefix(_ length: Int = 120) -> String {
        let lower = self.lowercased()
        let collapsed = lower.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(collapsed.prefix(length))
    }
}
