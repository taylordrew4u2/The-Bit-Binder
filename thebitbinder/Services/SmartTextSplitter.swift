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
    
    // MARK: - Public API
    
    /// Splits raw text into an array of cleaned joke-candidate strings.
    /// Each returned string should represent one joke or bit.
    static func split(_ text: String) -> [String] {
        // Step 1: Normalize line endings
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
        // Step 2: Try structured splitting (numbered lists, headers, etc.)
        let structuredChunks = tryStructuredSplit(normalized)
        if !structuredChunks.isEmpty && structuredChunks.count > 1 {
            return structuredChunks.compactMap(cleanAndValidate)
        }
        
        // Step 3: Split by double-newlines (paragraph breaks)
        let paragraphChunks = splitByParagraphs(normalized)
        if paragraphChunks.count > 1 {
            // Merge very short consecutive chunks that are likely part of the same joke
            let merged = mergeShortChunks(paragraphChunks)
            return merged.compactMap(cleanAndValidate)
        }
        
        // Step 4: If single large block, try to split by sentence patterns
        let sentenceChunks = trySentencePatternSplit(normalized)
        if sentenceChunks.count > 1 {
            return sentenceChunks.compactMap(cleanAndValidate)
        }
        
        // Step 5: Fallback — treat entire text as one chunk if it passes quality
        if let single = cleanAndValidate(normalized) {
            return [single]
        }
        
        return []
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
    
    private static func splitWithRegex(_ text: String, pattern: String) -> [String] {
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
            lastEnd = match.range.location + match.range.length
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
            let chunks = splitWithRegex(text, pattern: pattern)
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
        
        // ── Reject criteria ──
        
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
