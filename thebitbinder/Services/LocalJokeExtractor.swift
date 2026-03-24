//
//  LocalJokeExtractor.swift
//  thebitbinder
//
//  ⚠️  DEAD CODE — NOT used by the import pipeline.
//
//  This class is a legacy rule-based joke extractor that was previously used
//  as a fallback when the Gemini AI API was unavailable. Gemini has been
//  replaced by a multi-provider AI pipeline (OpenAI / Arcee / OpenRouter).
//
//  The current pipeline in `ImportPipelineCoordinator` has NO local fallback.
//  If every AI provider fails, the pipeline throws `AIExtractionFailedError`
//  and surfaces the error to the user — it never calls this class.
//
//  DO NOT call `LocalJokeExtractor` from any import path. If you find yourself
//  wanting to use it, you are violating the architecture contract defined in
//  `AIJokeExtractionManager.swift`. Add a new AI provider instead.
//
//  This file is kept to avoid breaking any unit tests that may reference it.
//  It can be deleted once those tests are removed or updated.
//

import Foundation
import CoreGraphics

/// ⚠️  DEAD CODE — NOT called by the import pipeline.
///
/// Legacy rule-based extractor kept for reference. The active pipeline uses
/// `AIJokeExtractionManager` (OpenAI / Arcee / OpenRouter) with NO local fallback.
/// See file header for full context.
final class LocalJokeExtractor {
    
    static let shared = LocalJokeExtractor()
    private init() {}
    
    // MARK: - Configuration
    
    /// Minimum character count for a text block to be considered a potential joke.
    private let minJokeLength = 20
    /// Maximum character count — anything longer is likely a paragraph of prose, not a joke.
    private let maxJokeLength = 2000
    /// Minimum word count for a plausible joke.
    private let minWordCount = 4
    /// Lines that are entirely uppercase and shorter than this are treated as titles.
    private let titleMaxLength = 60
    
    // MARK: - Public API
    
    /// Extracts potential jokes from raw text using heuristic rules.
    /// All results are marked `.low` confidence so the user reviews every one.
    func extract(from text: String) -> [GeminiExtractedJoke] {
        let blocks = splitIntoBlocks(text)
        var jokes: [GeminiExtractedJoke] = []
        
        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            // Filter by length
            guard trimmed.count >= minJokeLength,
                  trimmed.count <= maxJokeLength else { continue }
            
            let words = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard words.count >= minWordCount else { continue }
            
            // Skip lines that look like metadata (dates, page numbers, headers)
            if looksLikeMetadata(trimmed) { continue }
            
            // Try to detect a title (first line if short + rest is body)
            let lines = trimmed.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            var title: String? = nil
            var body = trimmed
            
            if lines.count >= 2 {
                let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
                if firstLine.count <= titleMaxLength && !firstLine.hasSuffix(".") {
                    title = firstLine
                    body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // Infer basic tags from content
            let tags = inferTags(from: trimmed.lowercased())
            
            jokes.append(GeminiExtractedJoke(
                jokeText: body,
                humorMechanism: nil,
                confidence: 0.3, // Low confidence — always send to review
                explanation: "Extracted by legacy local rule-based extractor (NOT from AI pipeline)",
                title: title,
                tags: tags
            ))
        }
        
        print("📝 [LocalExtractor] Extracted \(jokes.count) potential joke(s) from \(text.count) chars")
        return jokes
    }
    
    // MARK: - Text Splitting
    
    /// Splits text into blocks using explicit separators first, then blank lines.
    private func splitIntoBlocks(_ text: String) -> [String] {
        // PRIORITY 1: Check for explicit separators that the user typed
        let explicitSeparators = [
            // === TEXT SEPARATORS (words/phrases) ===
            "next joke",
            "new joke",
            "next bit",
            "new bit",
            "next one",
            "another one",
            "another joke",
            "moving on",
            "next up",
            "and then",
            "also",
            "plus",
            "bonus",
            "extra",
            "more",
            "joke:",
            "bit:",
            "premise:",
            "idea:",
            "topic:",
            "subject:",
            "material:",
            "chunk:",
            "segment:",
            "section:",
            "part:",
            "item:",
            "entry:",
            "note:",
            "thought:",
            "concept:",
            "end joke",
            "end bit",
            "done",
            "fin",
            "next",
            "new",
            "okay next",
            "ok next",
            "alright next",
            "now for",
            "here's another",
            "heres another",
            "here is another",
            "and another",
            "one more",
            "different topic",
            "new topic",
            "switch",
            "switching",
            "change",
            "changing",
            "onto",
            "on to",
            
            // === DASH/LINE SEPARATORS ===
            "---",
            "----",
            "-----",
            "------",
            "-------",
            "--------",
            "--",
            "———",
            "————",
            "—————",
            "——",
            "- -",
            "- - -",
            "- - - -",
            "– –",
            "– – –",
            "— —",
            "— — —",
            
            // === ASTERISK/STAR SEPARATORS ===
            "***",
            "****",
            "*****",
            "**",
            "* *",
            "* * *",
            "* * * *",
            "✱✱✱",
            "★★★",
            "☆☆☆",
            "⭐⭐⭐",
            
            // === EQUALS/UNDERSCORE SEPARATORS ===
            "===",
            "====",
            "=====",
            "==",
            "= =",
            "= = =",
            "___",
            "____",
            "_____",
            "_ _",
            "_ _ _",
            
            // === TILDE/HASH SEPARATORS ===
            "~~~",
            "~~~~",
            "~~~~~",
            "~~",
            "~ ~",
            "~ ~ ~",
            "###",
            "####",
            "#####",
            "##",
            "# #",
            "# # #",
            
            // === SLASH/PIPE SEPARATORS ===
            "//",
            "///",
            "////",
            "/ /",
            "/ / /",
            "||",
            "|||",
            "| |",
            "| | |",
            "\\\\",
            "\\\\\\",
            "\\ \\",
            "\\ \\ \\",
            
            // === DOT/BULLET SEPARATORS ===
            "...",
            "....",
            ".....",
            ". . .",
            ". . . .",
            "…",
            "……",
            "•••",
            "••••",
            "• • •",
            "···",
            "····",
            "· · ·",
            "∙∙∙",
            "‣‣‣",
            "►►►",
            "▸▸▸",
            ">>>",
            ">> >>",
            "> > >",
            "<<<",
            "<< <<",
            "< < <",
            
            // === ARROW SEPARATORS ===
            "->",
            "-->",
            "--->",
            "=>",
            "==>",
            "===>",
            "<-",
            "<--",
            "<---",
            "<=",
            "<==",
            "<===",
            "→",
            "→→",
            "→→→",
            "←",
            "←←",
            "←←←",
            "↓",
            "↓↓",
            "↓↓↓",
            
            // === COLON/SEMICOLON SEPARATORS ===
            "::",
            ":::",
            "::::",
            ": :",
            ": : :",
            ";;",
            ";;;",
            "; ;",
            "; ; ;",
            
            // === BRACKET/PAREN SEPARATORS ===
            "[next]",
            "[new]",
            "[joke]",
            "[bit]",
            "[end]",
            "[break]",
            "[---]",
            "[***]",
            "[ ]",
            "[  ]",
            "(next)",
            "(new)",
            "(joke)",
            "(bit)",
            "(end)",
            "(break)",
            "(---)",
            "(***)",
            "{next}",
            "{new}",
            "{joke}",
            "{bit}",
            
            // === MISC SYMBOL SEPARATORS ===
            "+++",
            "++++",
            "+ + +",
            "^^^",
            "^^^^",
            "^ ^ ^",
            "%%%",
            "%%%%",
            "% % %",
            "&&&",
            "&&&&",
            "& & &",
            "@@@",
            "@@@@",
            "@ @ @",
            "!!!",
            "!!!!",
            "! ! !",
            "???",
            "????",
            "? ? ?",
            "◆◆◆",
            "◇◇◇",
            "○○○",
            "●●●",
            "□□□",
            "■■■",
            "△△△",
            "▲▲▲",
            "♦♦♦",
            "♠♠♠",
            "♣♣♣",
            "♥♥♥",
            "✓✓✓",
            "✔✔✔",
            "✕✕✕",
            "✖✖✖",
            "✗✗✗",
            "✘✘✘",
            "❌❌❌",
            "✅✅✅",
            "🔹🔹🔹",
            "🔸🔸🔸",
            "💎💎💎",
            "🎤🎤🎤",
            "😂😂😂",
            "🤣🤣🤣",
        ]
        
        var workingText = text
        
        // Replace explicit separators with a unique delimiter
        let uniqueDelimiter = "\n§§§JOKE_SPLIT§§§\n"
        
        for separator in explicitSeparators {
            // Case-insensitive replacement for text separators
            let pattern = "(?i)\\n\\s*\(NSRegularExpression.escapedPattern(for: separator))\\s*\\n"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(workingText.startIndex..., in: workingText)
                workingText = regex.stringByReplacingMatches(in: workingText, range: range, withTemplate: uniqueDelimiter)
            }
            
            // Also check for separator at start of line (no leading newline)
            let startPattern = "(?i)^\(NSRegularExpression.escapedPattern(for: separator))\\s*\\n"
            if let regex = try? NSRegularExpression(pattern: startPattern, options: .anchorsMatchLines) {
                let range = NSRange(workingText.startIndex..., in: workingText)
                workingText = regex.stringByReplacingMatches(in: workingText, range: range, withTemplate: uniqueDelimiter)
            }
        }
        
        // PRIORITY 2: Detect numbered/lettered/bulleted items
        let numberedPatterns = [
            // === NUMBERS ===
            "(?m)^\\s*\\d+\\.\\s+",              // "1. ", "2. ", "10. "
            "(?m)^\\s*\\d+\\)\\s+",              // "1) ", "2) ", "10) "
            "(?m)^\\s*\\d+:\\s+",                // "1: ", "2: "
            "(?m)^\\s*\\d+-\\s+",                // "1- ", "2- "
            "(?m)^\\s*\\(\\d+\\)\\s*",           // "(1) ", "(2) "
            "(?m)^\\s*\\[\\d+\\]\\s*",           // "[1] ", "[2] "
            "(?m)^\\s*\\{\\d+\\}\\s*",           // "{1} ", "{2} "
            
            // === HASHTAG NUMBERS ===
            "(?m)^\\s*#\\d+\\s*:?\\s*",          // "#1", "#1:", "#1 "
            "(?m)^\\s*№\\d+\\s*:?\\s*",          // "№1", "№1:"
            
            // === LABELED NUMBERS ===
            "(?m)^\\s*joke\\s*\\d+\\s*:?\\s*",   // "Joke 1", "joke 1:", "JOKE 1"
            "(?m)^\\s*bit\\s*\\d+\\s*:?\\s*",    // "Bit 1", "bit 1:", "BIT 1"
            "(?m)^\\s*premise\\s*\\d+\\s*:?\\s*", // "Premise 1"
            "(?m)^\\s*idea\\s*\\d+\\s*:?\\s*",   // "Idea 1"
            "(?m)^\\s*topic\\s*\\d+\\s*:?\\s*",  // "Topic 1"
            "(?m)^\\s*item\\s*\\d+\\s*:?\\s*",   // "Item 1"
            "(?m)^\\s*entry\\s*\\d+\\s*:?\\s*",  // "Entry 1"
            "(?m)^\\s*note\\s*\\d+\\s*:?\\s*",   // "Note 1"
            "(?m)^\\s*thought\\s*\\d+\\s*:?\\s*", // "Thought 1"
            "(?m)^\\s*j\\d+\\s*:?\\s*",          // "J1", "j1:"
            "(?m)^\\s*b\\d+\\s*:?\\s*",          // "B1", "b1:"
            
            // === LETTERS ===
            "(?m)^\\s*[A-Za-z]\\.\\s+",          // "A. ", "B. ", "a. ", "b. "
            "(?m)^\\s*[A-Za-z]\\)\\s+",          // "A) ", "B) ", "a) ", "b) "
            "(?m)^\\s*[A-Za-z]:\\s+",            // "A: ", "B: "
            "(?m)^\\s*\\([A-Za-z]\\)\\s*",       // "(A) ", "(B) ", "(a) "
            "(?m)^\\s*\\[[A-Za-z]\\]\\s*",       // "[A] ", "[B] "
            
            // === ROMAN NUMERALS ===
            "(?m)^\\s*[ivxIVX]+\\.\\s+",         // "i. ", "ii. ", "I. ", "II. "
            "(?m)^\\s*[ivxIVX]+\\)\\s+",         // "i) ", "ii) "
            "(?m)^\\s*\\([ivxIVX]+\\)\\s*",      // "(i) ", "(ii) "
            
            // === BULLETS ===
            "(?m)^\\s*[-–—]\\s+",                // "- ", "– ", "— " (dashes as bullets)
            "(?m)^\\s*[•●○◦▪▫■□]\\s*",          // "• ", "● ", "○ " etc.
            "(?m)^\\s*[►▸▹▻❯❱➤➜➡→]\\s*",        // "► ", "➤ " etc.
            "(?m)^\\s*[✓✔☑✗✘☐]\\s*",            // "✓ ", "☑ " etc.
            "(?m)^\\s*[★☆✪✫✭⭐]\\s*",            // "★ ", "☆ " etc.
            "(?m)^\\s*[❤♥♡💜💙💚]\\s*",          // "❤ ", "♥ " etc.
            "(?m)^\\s*[🔹🔸🔷🔶💎]\\s*",          // "🔹 ", "🔸 " etc.
            "(?m)^\\s*[🎤🎙️🎭😂🤣]\\s*",         // "🎤 ", "😂 " etc.
        ]
        
        for pattern in numberedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(workingText.startIndex..., in: workingText)
                // Check if we have multiple matches - only split if there are 2+ numbered items
                let matches = regex.matches(in: workingText, range: range)
                if matches.count >= 2 {
                    // Replace all but the first match with our delimiter
                    var offset = 0
                    for (index, match) in matches.enumerated() {
                        if index == 0 { continue } // Keep the first one as-is
                        let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                        if let swiftRange = Range(adjustedRange, in: workingText) {
                            let replacement = uniqueDelimiter
                            workingText.replaceSubrange(swiftRange, with: replacement)
                            offset += replacement.count - match.range.length
                        }
                    }
                }
            }
        }
        
        // PRIORITY 3: Split on our unique delimiter if we found any explicit separators
        if workingText.contains("§§§JOKE_SPLIT§§§") {
            let blocks = workingText.components(separatedBy: "§§§JOKE_SPLIT§§§")
            let cleaned = blocks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
            if cleaned.count > 1 {
                print("📝 [LocalExtractor] Found \(cleaned.count) blocks via explicit separators")
                return cleaned
            }
        }
        
        // PRIORITY 4: Fall back to blank line splitting (2+ consecutive newlines)
        let blankLinePattern = "\n\\s*\n"
        guard let regex = try? NSRegularExpression(pattern: blankLinePattern) else {
            return text.components(separatedBy: "\n\n")
        }
        
        let nsRange = NSRange(text.startIndex..., in: text)
        var blocks: [String] = []
        var lastEnd = text.startIndex
        
        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let matchRange = match?.range, let range = Range(matchRange, in: text) else { return }
            let block = String(text[lastEnd..<range.lowerBound])
            blocks.append(block)
            lastEnd = range.upperBound
        }
        
        // Don't forget the last block
        let remaining = String(text[lastEnd...])
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(remaining)
        }
        
        print("📝 [LocalExtractor] Found \(blocks.count) blocks via blank lines")
        return blocks
    }
    
    // MARK: - Heuristic Filters
    
    /// Returns true if the text looks like a page number, date, or header/footer.
    private func looksLikeMetadata(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pure numbers (page numbers)
        if Int(trimmed) != nil { return true }
        
        // Very short lines that are just formatting
        if trimmed.count < 5 { return true }
        
        // Common metadata patterns
        let metadataPatterns = [
            "^page \\d+",
            "^\\d+\\s*$",
            "^(january|february|march|april|may|june|july|august|september|october|november|december)\\s+\\d",
            "^\\d{1,2}/\\d{1,2}/\\d{2,4}",
            "^copyright",
            "^all rights reserved",
            "^table of contents",
            "^chapter \\d"
        ]
        
        let lower = trimmed.lowercased()
        for pattern in metadataPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, range: range) != nil {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Infers simple topic tags from lowercase text.
    private func inferTags(from text: String) -> [String] {
        var tags: [String] = []
        
        let tagPatterns: [(String, [String])] = [
            ("wife|husband|marriage|married|spouse|divorce", ["relationships"]),
            ("kid|children|baby|son|daughter|parent|mom|dad", ["family"]),
            ("work|boss|office|job|coworker|meeting", ["work"]),
            ("fly|flew|airplane|airport|airline|travel|hotel", ["travel"]),
            ("doctor|hospital|health|sick|medicine", ["health"]),
            ("food|eat|restaurant|cook|diet|pizza|burger", ["food"]),
            ("phone|internet|social media|app|computer|tech", ["technology"]),
            ("drunk|bar|beer|wine|drink|hangover", ["drinking"]),
            ("dog|cat|pet|animal", ["animals"]),
            ("sex|dating|tinder|relationship", ["dating"]),
        ]
        
        for (pattern, matchTags) in tagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, range: range) != nil {
                    tags.append(contentsOf: matchTags)
                }
            }
        }
        
        return Array(Set(tags)) // Deduplicate
    }
}
