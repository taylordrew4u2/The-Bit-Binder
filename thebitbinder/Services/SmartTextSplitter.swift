//
//  SmartTextSplitter.swift
//  thebitbinder
//
//  Content-aware text splitter that intelligently separates jokes
//  from raw text files, filtering nonsense and detecting boundaries.
//

import Foundation

/// Splits raw document text into individual joke candidates using
/// multiple heuristics: blank-line separation, numbered lists,
/// title detection, and content quality filtering.
enum SmartTextSplitter {

    // MARK: - Confidence Levels

    enum SplitConfidence: Comparable {
        case low
        case medium
        case high
    }

    // MARK: - Public API

    /// Splits raw text into an array of cleaned joke-candidate strings.
    static func split(_ text: String) -> [String] {
        splitWithConfidence(text).chunks
    }

    /// Splits raw text and reports how confident the splitter is.
    /// `.high` = explicit structural markers (numbered, bullets, separators, one-per-line).
    /// `.medium` = blank-line paragraphs.
    /// `.low` = sentence patterns or single block fallback.
    static func splitWithConfidence(_ text: String) -> (chunks: [String], confidence: SplitConfidence) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Step 1: Explicit separators (---, ===, NEXT JOKE, etc.)
        let separatorChunks = trySeparatorSplit(normalized)
        if separatorChunks.count > 1 {
            let cleaned = separatorChunks.compactMap(cleanAndValidate)
            if cleaned.count > 1 { return (cleaned, .high) }
        }

        // Step 2: Structured (numbered lists, bullets, titles)
        let structuredChunks = tryStructuredSplit(normalized)
        if structuredChunks.count > 1 {
            let cleaned = structuredChunks.compactMap(cleanAndValidate)
            if cleaned.count > 1 { return (cleaned, .high) }
        }

        // Step 3: One joke per line (each line ends with punctuation)
        let lineChunks = tryLinePerJokeSplit(normalized)
        if lineChunks.count > 1 {
            let cleaned = lineChunks.compactMap(cleanAndValidate)
            if cleaned.count > 1 { return (cleaned, .high) }
        }

        // Step 4: Blank-line paragraphs
        let paragraphChunks = splitByParagraphs(normalized)
        if paragraphChunks.count > 1 {
            let merged = mergeShortChunks(paragraphChunks)
            let cleaned = merged.compactMap(cleanAndValidate)
            if cleaned.count > 1 { return (cleaned, .medium) }
        }

        // Step 5: Sentence patterns
        let sentenceChunks = trySentencePatternSplit(normalized)
        if sentenceChunks.count > 1 {
            let cleaned = sentenceChunks.compactMap(cleanAndValidate)
            if cleaned.count > 1 { return (cleaned, .low) }
        }

        // Step 6: Single chunk fallback
        if let single = cleanAndValidate(normalized) {
            return ([single], .low)
        }

        return ([], .low)
    }
    
    // MARK: - Separator Splitting

    /// Detects explicit separators like ---, ===, ***, NEXT JOKE, etc.
    private static func trySeparatorSplit(_ text: String) -> [String] {
        let separatorPattern = #"^\s*[-–—=*]{3,}\s*$|^\s*(?:NEXT JOKE|NEW BIT|NEXT BIT|//)\s*$"#
        let lines = text.components(separatedBy: "\n")

        var separatorCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               trimmed.range(of: separatorPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                separatorCount += 1
            }
        }

        guard separatorCount >= 1 else { return [] }

        var chunks: [String] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               trimmed.range(of: separatorPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                if !current.isEmpty {
                    chunks.append(current.joined(separator: "\n"))
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }

        return chunks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Line-Per-Joke Detection

    /// Detects documents where each line is a separate joke (all lines end
    /// with sentence-ending punctuation).
    private static func tryLinePerJokeSplit(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 3 else { return [] }

        var completeSentenceCount = 0
        for line in lines {
            guard let lastChar = line.last else { continue }
            if lastChar == "." || lastChar == "!" || lastChar == "?" ||
               lastChar == "\"" || lastChar == "\u{201D}" {
                completeSentenceCount += 1
            }
        }

        let ratio = Float(completeSentenceCount) / Float(lines.count)
        guard ratio >= 0.6 else { return [] }
        return lines
    }

    // MARK: - Structured Splitting

    /// Detects numbered lists (1. / 1) / #1) and splits on them
    private static func tryStructuredSplit(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        
        // Detect numbered patterns
        let numberedPattern = #"^\s*(\d+)[.)\-:]\s+"#
        let bulletPattern = #"^\s*[•\-\*]\s+"#
        let titlePattern = #"^[A-Z][A-Za-z\s]{2,50}:?\s*$"#
        
        var numberedCount = 0
        var bulletCount = 0
        var titleCount = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: numberedPattern, options: .regularExpression) != nil { numberedCount += 1 }
            if trimmed.range(of: bulletPattern, options: .regularExpression) != nil { bulletCount += 1 }
            if trimmed.range(of: titlePattern, options: .regularExpression) != nil { titleCount += 1 }
        }
        
        // Use the dominant pattern if it appears enough times
        if numberedCount >= 2 {
            return splitOnPattern(lines, pattern: numberedPattern)
        }
        if bulletCount >= 2 {
            return splitOnPattern(lines, pattern: bulletPattern)
        }
        if titleCount >= 2 {
            return splitOnTitleLines(lines)
        }
        
        return []
    }
    
    private static func splitOnPattern(_ lines: [String], pattern: String) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: pattern, options: .regularExpression) != nil && !current.isEmpty {
                // Start a new chunk
                chunks.append(current.joined(separator: "\n"))
                current = [trimmed]
            } else {
                current.append(line)
            }
        }
        
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        
        return chunks
    }
    
    private static func splitOnTitleLines(_ lines: [String]) -> [String] {
        let titlePattern = #"^[A-Z][A-Za-z\s']{2,50}:?\s*$"#
        var chunks: [String] = []
        var current: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isTitleLine = trimmed.range(of: titlePattern, options: .regularExpression) != nil
                && trimmed.split(separator: " ").count <= 8
            
            if isTitleLine && !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = [trimmed]
            } else {
                current.append(line)
            }
        }
        
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        
        return chunks
    }
    
    // MARK: - Paragraph Splitting
    
    private static func splitByParagraphs(_ text: String) -> [String] {
        // Split on 2+ consecutive newlines (with optional whitespace between)
        let paragraphs = splitWithRegex(text, pattern: #"\n[ \t]*\n"#)
        return paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private static func splitWithRegex(_ text: String, pattern: String, preserveMatchInNextChunk: Bool = false) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text]
        }
        
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        
        if matches.isEmpty { return [text] }
        
        var chunks: [String] = []
        var lastEnd = 0
        
        for match in matches {
            let start = lastEnd
            let end = match.range.location
            if end > start {
                let chunk = nsText.substring(with: NSRange(location: start, length: end - start))
                chunks.append(chunk)
            }
            lastEnd = preserveMatchInNextChunk ? match.range.location : match.range.location + match.range.length
        }
        
        // Remaining text after last match
        if lastEnd < nsText.length {
            let chunk = nsText.substring(from: lastEnd)
            chunks.append(chunk)
        }
        
        return chunks
    }
    
    // MARK: - Sentence Pattern Split
    
    /// For long continuous text, look for joke-start patterns
    private static func trySentencePatternSplit(_ text: String) -> [String] {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard wordCount > 60 else { return [text] }  // Don't split short texts
        
        // Common joke-start patterns
        let jokeStarters = [
            #"(?<=\. |\? |! )So (?=[A-Z])"#,
            #"(?<=\. |\? |! )You know what"#,
            #"(?<=\. |\? |! )I was "#,
            #"(?<=\. |\? |! )The other day"#,
            #"(?<=\. |\? |! )My (?:wife|husband|girlfriend|boyfriend|mom|dad|friend)"#,
            #"(?<=\. |\? |! )Ever notice"#,
            #"(?<=\. |\? |! )What's the deal"#,
            #"(?<=\. |\? |! )Here's the thing"#,
        ]
        
        // Find best pattern that splits into reasonable chunks
        for pattern in jokeStarters {
            let chunks = splitWithRegex(text, pattern: pattern, preserveMatchInNextChunk: true)
            if chunks.count > 1 && chunks.count <= 20 {
                return chunks
            }
        }
        
        return [text]
    }
    
    // MARK: - Chunk Merging
    
    /// Merges very short consecutive chunks that are probably fragments, not separate jokes
    private static func mergeShortChunks(_ chunks: [String]) -> [String] {
        var merged: [String] = []
        var accumulator = ""
        
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
            
            if wordCount < 4 && !accumulator.isEmpty {
                // Very short — append to previous chunk
                accumulator += "\n" + trimmed
            } else if wordCount < 8 && !accumulator.isEmpty {
                // Short — check if it looks like a punchline (no period/setup words)
                let looksLikePunchline = !trimmed.lowercased().hasPrefix("so ") &&
                    !trimmed.lowercased().hasPrefix("i ") &&
                    !trimmed.lowercased().hasPrefix("my ") &&
                    !trimmed.lowercased().hasPrefix("you ")
                
                if looksLikePunchline {
                    accumulator += "\n" + trimmed
                } else {
                    if !accumulator.isEmpty { merged.append(accumulator) }
                    accumulator = trimmed
                }
            } else {
                if !accumulator.isEmpty { merged.append(accumulator) }
                accumulator = trimmed
            }
        }
        
        if !accumulator.isEmpty { merged.append(accumulator) }
        return merged
    }
    
    // MARK: - Quality Filtering
    
    /// Returns nil if the chunk is nonsense/noise, otherwise returns cleaned text
    private static func cleanAndValidate(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip leading bullet/number prefix for cleaner storage
        // (keep the content, just clean the marker)
        text = text.replacingOccurrences(
            of: #"^\s*(\d+[.)\-:]|[•\-\*])\s+"#,
            with: "",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        //  Reject criteria 
        
        // Too short
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if wordCount < 3 { return nil }
        
        // Mostly numbers or symbols (OCR garbage, page numbers, etc.)
        let letters = text.filter { $0.isLetter }
        let letterRatio = Float(letters.count) / max(Float(text.count), 1)
        if letterRatio < 0.4 { return nil }
        
        // Repeated characters (scan artifacts)
        if isGibberish(text) { return nil }
        
        // Common non-joke content
        let lower = text.lowercased()
        let noisePatterns = [
            "page ", "chapter ", "table of contents", "copyright",
            "all rights reserved", "printed in", "isbn", "published by",
            "acknowledgment", "dedication", "index", "bibliography",
            "about the author", "also by", "www.", "http://", "https://",
        ]
        for noise in noisePatterns {
            if lower.hasPrefix(noise) || (lower.contains(noise) && wordCount < 12) {
                return nil
            }
        }
        
        // Single word repeated many times
        let words = text.lowercased().split(whereSeparator: \.isWhitespace)
        if words.count > 4 {
            let unique = Set(words)
            if Float(unique.count) / Float(words.count) < 0.3 {
                return nil  // Too repetitive
            }
        }
        
        return text
    }
    
    /// Detects garbled text (OCR errors, random characters)
    private static func isGibberish(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 3 else { return false }
        
        // Count "real" English-looking words (2+ letters, mostly alpha)
        var realWordCount = 0
        for word in words {
            let alpha = word.filter { $0.isLetter }
            if alpha.count >= 2 && Float(alpha.count) / Float(word.count) > 0.7 {
                realWordCount += 1
            }
        }
        
        let ratio = Float(realWordCount) / Float(words.count)
        return ratio < 0.5  // More than half the "words" aren't real words
    }
}
