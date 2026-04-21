//
//  EmbeddingSegmenterProvider.swift
//  thebitbinder
//
//  Pure on-device joke segmenter using Apple's NaturalLanguage framework
//  (available since iOS 12 — works on every device the app supports).
//
//  This provider does NOT classify jokes; it *segments* flowing text into
//  joke-sized chunks using a TextTiling-style approach:
//
//    1. Strip any `[EXTRACTION HINTS…]` prefix the pipeline prepended.
//    2. Pre-split on obviously strong structural signals — blank-line gaps,
//       numbered list items, bullets.
//    3. Inside each block, tokenize to sentences with `NLTokenizer`.
//    4. Embed each sentence with `NLEmbedding.sentenceEmbedding(for: .english)`.
//    5. Compute cosine similarity between consecutive sentences, then split
//       where similarity falls below `mean - k·stddev` (a similarity trough).
//    6. Every resulting chunk becomes an `AIExtractedJoke` with medium
//       confidence so the user reviews each split.
//
//  Why this exists alongside the cloud + Apple-Intelligence providers:
//    - Works offline. No API key. No rate limits.
//    - Works on iOS 17 devices without Apple Intelligence (where
//      `AppleOnDeviceJokeExtractionProvider` reports unavailable).
//    - Last in the default provider order — cloud/Apple AI are more
//      accurate for the "is this a joke?" call and run first when
//      available. This is the "nothing else worked" fallback.
//

import Foundation
import NaturalLanguage

final class EmbeddingSegmenterProvider: AIJokeExtractionProvider {

    let providerType: AIProviderType = .embeddingLocal

    /// Pure on-device — no network, no key.
    var requiresNetwork: Bool { false }

    /// Available whenever an English sentence-embedding model is present —
    /// shipped with iOS since the framework was introduced.
    func isConfigured() -> Bool {
        NLEmbedding.sentenceEmbedding(for: .english) != nil
    }

    func extractJokes(from text: String) async throws -> [AIExtractedJoke] {
        try await extractJokes(from: text, hints: .unspecified)
    }

    /// Hints-aware path the manager prefers. Structured hints lets us:
    ///   - skip auto-detection when the user already told us the separator
    ///     style (`separator != .mixed`);
    ///   - pick `.noneOrFlowing` to bypass structural splitting entirely and
    ///     rely purely on embedding troughs;
    ///   - tune the similarity-trough sigma threshold based on the user's
    ///     declared bit length so one-liner decks get more splits and
    ///     long-paragraph docs get fewer.
    func extractJokes(from text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        // The coordinator sometimes prepends a `[EXTRACTION HINTS FROM USER]
        // … [END HINTS]` block. We strip it so the hint prose doesn't wind up
        // as a joke entry — the semantic equivalent of what guided-generation
        // providers get for free.
        let stripped = Self.stripHintPrefix(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return [] }

        // Heavy NL work off the main actor.
        let chunks = await Task.detached(priority: .userInitiated) {
            EmbeddingSegmenterProvider.segment(text: stripped, hints: hints)
        }.value

        return chunks.map { body in
            // Confidence 0.5 = medium. In `toImportedJoke` that lands the
            // joke in the review queue so the user sees and confirms every
            // split — embedding-only segmentation is not accurate enough to
            // auto-save.
            AIExtractedJoke(
                jokeText: body,
                humorMechanism: nil,
                confidence: 0.5,
                explanation: nil,
                title: nil,
                tags: []
            )
        }
    }

    // MARK: - Hint-prefix stripping

    /// Remove the `[EXTRACTION HINTS FROM USER] … [END HINTS]` block that
    /// `ExtractionHints.aiPromptPrefix()` produces, plus the legacy
    /// `[USER FORMAT HINT: …]` form. Case-insensitive, single-line match.
    static func stripHintPrefix(_ text: String) -> String {
        var out = text

        // New structured prefix (always ends with `[END HINTS]`).
        if let range = out.range(of: #"(?is)^\s*\[EXTRACTION HINTS FROM USER\].*?\[END HINTS\]\s*"#,
                                 options: .regularExpression) {
            out.removeSubrange(range)
        }

        // Legacy single-line prefix.
        out = out.replacingOccurrences(
            of: #"^\s*\[USER FORMAT HINT:[^\]]*\]\s*"#,
            with: "",
            options: .regularExpression
        )

        return out
    }

    // MARK: - Segmentation

    /// Split `text` into joke-sized chunks. See file header for the algorithm.
    static func segment(text: String, hints: ExtractionHints = .unspecified) -> [String] {
        // Normalise line endings so regex splits behave consistently.
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Stage 1: strong structural splits. When the user pre-declared a
        // separator style we use it directly; otherwise we auto-detect based
        // on marker frequency.
        let blocks = structuralSplit(normalised, hints: hints)

        // Stage 2: inside each block, use embedding troughs to separate
        // topics where the block is long enough to have internal structure.
        // Short blocks pass through unchanged.
        let sigma = sigmaThreshold(for: hints.length)
        var chunks: [String] = []
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)

        for block in blocks {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBlock.isEmpty else { continue }

            let sentences = tokenizeSentences(trimmedBlock)

            // Too short to bother embedding — one chunk.
            if sentences.count <= minSentencesToAnalyse {
                chunks.append(trimmedBlock)
                continue
            }

            // No embedding model on this device (shouldn't happen — the
            // configured check would have returned false, and the manager
            // would have skipped us). Fall back to emitting the block as a
            // single chunk rather than silently splitting on weak signals.
            guard let embedding else {
                chunks.append(trimmedBlock)
                continue
            }

            let subChunks = segmentByEmbeddings(
                sentences: sentences,
                embedding: embedding,
                sigma: sigma
            )
            chunks.append(contentsOf: subChunks)
        }

        return chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Picks the similarity-trough threshold based on the user's declared
    /// bit length. Lower σ = more splits (expect many short bits); higher σ
    /// = fewer splits (expect long paragraph-sized bits).
    private static func sigmaThreshold(for length: ExtractionHints.BitLength) -> Double {
        switch length {
        case .oneLiner:          return 0.5
        case .shortFewSentences: return 1.0
        case .longParagraph:     return 1.5
        case .varies:            return 1.0
        }
    }

    // MARK: - Stage 1: structural splits

    private static func structuralSplit(_ text: String, hints: ExtractionHints) -> [String] {
        let lines = text.components(separatedBy: "\n")

        let numberedPattern = try? NSRegularExpression(
            pattern: #"^\s*(?:(?:joke|bit|gag|#)\s*)?\d+\s*[.):\-–—]\s+"#,
            options: [.caseInsensitive]
        )
        let bulletPattern = try? NSRegularExpression(
            pattern: #"^\s*[-•*]\s+"#,
            options: []
        )
        let separatorPattern = try? NSRegularExpression(
            pattern: #"^\s*[-–—=*]{3,}\s*$|^\s*(?:NEXT JOKE|NEW BIT|//)\s*$"#,
            options: [.caseInsensitive]
        )

        func matches(_ regex: NSRegularExpression?, _ line: String) -> Bool {
            guard let regex else { return false }
            return regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ) != nil
        }

        // User-declared separator style wins. `.mixed` (default) falls
        // through to auto-detection. `.headers` has no regex yet — treat as
        // auto-detect too.
        switch hints.separator {
        case .numbered:
            return splitOn(lines) { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return matches(numberedPattern, trimmed) || matches(separatorPattern, trimmed)
            }
        case .bullets:
            return splitOn(lines) { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return matches(bulletPattern, trimmed) || matches(separatorPattern, trimmed)
            }
        case .blankLine:
            return splitByBlankLines(lines) { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return matches(separatorPattern, trimmed)
            }
        case .noneOrFlowing:
            // User says there are no structural markers — skip Stage 1
            // entirely and let Stage 2 embedding troughs do the work on the
            // whole document as a single block.
            return [text]
        case .headers, .mixed:
            break
        }

        // Auto-detect: count structural signals across the whole document.
        // When one signal dominates (≥ ~30% of non-empty lines) we commit to
        // it; otherwise fall back to splitting on blank lines.
        var numberedCount = 0
        var bulletCount = 0
        var nonEmpty = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            nonEmpty += 1
            if matches(numberedPattern, trimmed) { numberedCount += 1 }
            if matches(bulletPattern, trimmed)   { bulletCount += 1 }
        }

        let structuralThreshold = max(3, nonEmpty / 3)
        let useNumbered = numberedCount >= structuralThreshold
        let useBullets  = !useNumbered && bulletCount >= structuralThreshold

        if useNumbered {
            return splitOn(lines) { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return matches(numberedPattern, trimmed) || matches(separatorPattern, trimmed)
            }
        }

        if useBullets {
            return splitOn(lines) { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return matches(bulletPattern, trimmed) || matches(separatorPattern, trimmed)
            }
        }

        return splitByBlankLines(lines) { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return matches(separatorPattern, trimmed)
        }
    }

    /// Split `lines` into blocks where each block starts with a line for
    /// which `isStart` returns true. Separator lines are dropped.
    private static func splitOn(_ lines: [String], isStart: (String) -> Bool) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        for line in lines {
            if isStart(line) {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                }
                // Keep the line itself — but drop pure separator lines
                // (e.g. "---") so they don't pollute output.
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let isPureSeparator = trimmed.range(
                    of: #"^[-–—=*]{3,}$|^(?:NEXT JOKE|NEW BIT|//)$"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
                if !isPureSeparator {
                    current.append(line)
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }
        return blocks
    }

    /// Split on blank-line gaps and explicit separator lines.
    private static func splitByBlankLines(_ lines: [String], separatorMatcher: (String) -> Bool) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || separatorMatcher(line) {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }
        return blocks
    }

    // MARK: - Stage 2: embedding-based sub-splits

    /// Minimum sentence count to bother running embedding analysis — any
    /// shorter and the block is smaller than a typical bit anyway.
    private static let minSentencesToAnalyse = 4

    private static func tokenizeSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                out.append(sentence)
            }
            return true
        }
        return out
    }

    private static func segmentByEmbeddings(
        sentences: [String],
        embedding: NLEmbedding,
        sigma: Double
    ) -> [String] {
        // Compute per-sentence vectors. Unknown sentences (punctuation-only,
        // etc.) come back nil — we reuse the previous vector so they don't
        // cause spurious splits.
        var vectors: [[Double]] = []
        var lastGood: [Double]? = nil
        for sentence in sentences {
            if let vec = embedding.vector(for: sentence), !vec.isEmpty {
                vectors.append(vec)
                lastGood = vec
            } else if let lastGood {
                vectors.append(lastGood)
            } else {
                vectors.append([])
            }
        }

        // Similarities between consecutive sentences.
        var sims: [Double] = []
        for i in 0..<(vectors.count - 1) {
            sims.append(cosine(vectors[i], vectors[i + 1]))
        }

        // Nothing meaningful to analyse.
        guard sims.count >= 2 else {
            return [sentences.joined(separator: " ")]
        }

        let mean = sims.reduce(0, +) / Double(sims.count)
        let variance = sims.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sims.count)
        let stddev = variance.squareRoot()
        let threshold = mean - sigma * stddev

        // Find boundaries. `sims[i]` is the similarity between sentence `i`
        // and sentence `i+1`, so a low value there means the split happens
        // between them — we start a new chunk at sentence `i+1`.
        var chunkStarts: [Int] = [0]
        for i in 0..<sims.count where sims[i] < threshold {
            chunkStarts.append(i + 1)
        }
        chunkStarts.append(sentences.count)

        var chunks: [String] = []
        for i in 0..<(chunkStarts.count - 1) {
            let lo = chunkStarts[i]
            let hi = chunkStarts[i + 1]
            guard lo < hi else { continue }
            let chunk = sentences[lo..<hi].joined(separator: " ")
            chunks.append(chunk)
        }
        return chunks
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot()) * (nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}
