//
//  DuplicateDetectionService.swift
//  thebitbinder
//
//  Fuzzy duplicate detection for jokes during import.
//

import Foundation
import SwiftData

@MainActor
final class DuplicateDetectionService {

    struct DuplicateMatch {
        let existingTitle: String
        let existingContentPreview: String
        let similarity: Double // 0.0–1.0
    }

    /// Check a single piece of content against all non-trashed jokes in the database.
    /// Returns a match if similarity exceeds the threshold.
    static func findDuplicate(
        content: String,
        title: String?,
        in context: ModelContext,
        threshold: Double = 0.75
    ) -> DuplicateMatch? {
        let descriptor = FetchDescriptor<Joke>(
            predicate: #Predicate<Joke> { !$0.isTrashed }
        )
        guard let existingJokes = try? context.fetch(descriptor) else { return nil }

        let newNorm = content.normalizedForDuplication()

        for joke in existingJokes {
            let existingNorm = joke.content.normalizedForDuplication()

            // Fast exact prefix check first (cheap)
            if !newNorm.isEmpty && newNorm == existingNorm {
                return DuplicateMatch(
                    existingTitle: joke.title,
                    existingContentPreview: String(joke.content.prefix(80)),
                    similarity: 1.0
                )
            }

            // Normalized prefix match (same as existing normalizedPrefix but full-string)
            let prefixLen = 120
            if newNorm.count >= 30 && existingNorm.count >= 30 {
                let newPrefix = String(newNorm.prefix(prefixLen))
                let existingPrefix = String(existingNorm.prefix(prefixLen))
                if newPrefix == existingPrefix {
                    return DuplicateMatch(
                        existingTitle: joke.title,
                        existingContentPreview: String(joke.content.prefix(80)),
                        similarity: 0.95
                    )
                }
            }

            // Fuzzy similarity for content of similar length (avoid comparing a one-liner to a 500-word bit)
            let lengthRatio = Double(min(newNorm.count, existingNorm.count)) /
                              Double(max(newNorm.count, existingNorm.count, 1))
            if lengthRatio > 0.5 && newNorm.count >= 20 && existingNorm.count >= 20 {
                let sim = bigramSimilarity(newNorm, existingNorm)
                if sim >= threshold {
                    return DuplicateMatch(
                        existingTitle: joke.title,
                        existingContentPreview: String(joke.content.prefix(80)),
                        similarity: sim
                    )
                }
            }

            // Title match (when both have non-trivial titles)
            if let newTitle = title, !newTitle.isEmpty, !joke.title.isEmpty {
                let t1 = newTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let t2 = joke.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if t1 == t2 && t1.count >= 5 {
                    return DuplicateMatch(
                        existingTitle: joke.title,
                        existingContentPreview: String(joke.content.prefix(80)),
                        similarity: 0.85
                    )
                }
            }
        }
        return nil
    }

    /// Batch check for multiple import candidates. Returns a dictionary mapping item IDs to matches.
    static func findDuplicates(
        for items: [(id: UUID, content: String, title: String?)],
        in context: ModelContext,
        threshold: Double = 0.75
    ) -> [UUID: DuplicateMatch] {
        let descriptor = FetchDescriptor<Joke>(
            predicate: #Predicate<Joke> { !$0.isTrashed }
        )
        guard let existingJokes = try? context.fetch(descriptor) else { return [:] }

        // Pre-compute normalized content for existing jokes
        let existingNormed: [(joke: Joke, norm: String)] = existingJokes.map {
            ($0, $0.content.normalizedForDuplication())
        }

        var results: [UUID: DuplicateMatch] = [:]

        for item in items {
            let newNorm = item.content.normalizedForDuplication()

            for (joke, existingNorm) in existingNormed {
                // Exact normalized match
                if !newNorm.isEmpty && newNorm == existingNorm {
                    results[item.id] = DuplicateMatch(
                        existingTitle: joke.title,
                        existingContentPreview: String(joke.content.prefix(80)),
                        similarity: 1.0
                    )
                    break
                }

                // Prefix match
                if newNorm.count >= 30 && existingNorm.count >= 30 {
                    let newPrefix = String(newNorm.prefix(120))
                    let existingPrefix = String(existingNorm.prefix(120))
                    if newPrefix == existingPrefix {
                        results[item.id] = DuplicateMatch(
                            existingTitle: joke.title,
                            existingContentPreview: String(joke.content.prefix(80)),
                            similarity: 0.95
                        )
                        break
                    }
                }

                // Fuzzy similarity
                let lengthRatio = Double(min(newNorm.count, existingNorm.count)) /
                                  Double(max(newNorm.count, existingNorm.count, 1))
                if lengthRatio > 0.5 && newNorm.count >= 20 && existingNorm.count >= 20 {
                    let sim = bigramSimilarity(newNorm, existingNorm)
                    if sim >= threshold {
                        results[item.id] = DuplicateMatch(
                            existingTitle: joke.title,
                            existingContentPreview: String(joke.content.prefix(80)),
                            similarity: sim
                        )
                        break
                    }
                }

                // Title match
                if let newTitle = item.title, !newTitle.isEmpty, !joke.title.isEmpty {
                    let t1 = newTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let t2 = joke.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if t1 == t2 && t1.count >= 5 {
                        results[item.id] = DuplicateMatch(
                            existingTitle: joke.title,
                            existingContentPreview: String(joke.content.prefix(80)),
                            similarity: 0.85
                        )
                        break
                    }
                }
            }
        }
        return results
    }

    // MARK: - Bigram Similarity (Dice coefficient)

    /// Fast fuzzy similarity using character bigrams (Sørensen–Dice coefficient).
    /// Returns 0.0 (no similarity) to 1.0 (identical).
    private static func bigramSimilarity(_ a: String, _ b: String) -> Double {
        let bigramsA = bigrams(from: a)
        let bigramsB = bigrams(from: b)
        guard !bigramsA.isEmpty && !bigramsB.isEmpty else { return 0 }

        var intersection = 0
        var remaining = bigramsB
        for bg in bigramsA {
            if let idx = remaining.firstIndex(of: bg) {
                intersection += 1
                remaining.remove(at: idx)
            }
        }
        return (2.0 * Double(intersection)) / Double(bigramsA.count + bigramsB.count)
    }

    private static func bigrams(from string: String) -> [String] {
        let chars = Array(string)
        guard chars.count >= 2 else { return [] }
        return (0..<chars.count - 1).map { String(chars[$0...$0+1]) }
    }
}

// MARK: - String Normalization

extension String {
    /// Full normalization for duplicate detection: lowercase, collapse whitespace, strip punctuation.
    func normalizedForDuplication() -> String {
        let lower = self.lowercased()
        let noPunctuation = lower.replacing(/[^\p{L}\p{N}\s]/, with: "")
        let collapsed = noPunctuation.replacing(/\s+/, with: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
    }
}
