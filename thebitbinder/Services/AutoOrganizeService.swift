//
//  AutoOrganizeService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/7/25.
//

import Foundation
import SwiftData

struct StyleAnalysis {
    let tags: [String]
    let tone: String?
    let craftSignals: [String]
    let structureScore: Double
    let hook: String?
}

struct TopicMatch {
    let category: String
    let confidence: Double
    let evidence: [String]
}

// MARK: - Joke Structure Analysis
struct JokeStructure {
    let hasSetup: Bool
    let hasPunchline: Bool
    let format: JokeFormat
    let wordplayScore: Double
    let setupLineCount: Int
    let punchlineLineCount: Int
    let questionAnswerPattern: Bool
    let storyTwistPattern: Bool
    let oneLiners: Int
    let dialogueCount: Int
    
    var structureConfidence: Double {
        var score = 0.0
        if hasSetup { score += 0.2 }
        if hasPunchline { score += 0.2 }
        score += min(wordplayScore * 0.2, 0.2)
        if questionAnswerPattern { score += 0.15 }
        if storyTwistPattern { score += 0.15 }
        return min(score, 1.0)
    }
}

enum JokeFormat {
    case questionAnswer
    case storyTwist
    case oneLiner
    case dialogue
    case sequential
    case unknown
}

// MARK: - Pattern Match Result
// Wordplay detection helpers
let homophoneSets: [[String]] = [
    ["to", "too", "two"],
    ["be", "bee"],
    ["see", "sea"],
    ["here", "hear"],
    ["write", "right"],
    ["mail", "male"],
    ["knight", "night"]
]

let doubleMeaningWords: [(String, String)] = [
    ("bark", "tree coating or dog sound"),
    ("bank", "financial or river side"),
    ("can", "is able or container"),
    ("date", "calendar or romantic outing"),
    ("fair", "just or carnival")
]


class AutoOrganizeService {

    // MARK: - Categorization

    /// Categorize a joke using the local heuristic lexicon. Runs entirely
    /// on-device. Signature kept `async` so existing callers don't need to
    /// change.
    static func aiCategorize(content: String, existingFolders: [String] = []) async -> [CategoryMatch] {
        categorize(content: content)
    }

    /// Kept for callers that want to tweak UI copy based on capability. All
    /// categorization is local now, so this is always `false`.
    static var isAIAvailable: Bool { false }

    // MARK: - Local Categorization

    /// Categorizes a single joke content into categories with detailed metadata.
    /// - Parameter content: The joke content to categorize.
    /// - Returns: An array of `CategoryMatch` representing the best matching categories.
    static func categorize(content: String) -> [CategoryMatch] {
        let normalized = normalize(content)
        let topicMatches = scoreCategories(in: normalized)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(content)
        let matches: [CategoryMatch] = topicMatches.map { match in
            CategoryMatch(
                category: match.category,
                confidence: match.confidence,
                reasoning: reasoning(for: match, style: style, structure: structure),
                matchedKeywords: match.evidence,
                styleTags: style.tags,
                emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            )
        }
        .sorted { $0.confidence > $1.confidence }
        return matches
    }

    // MARK: - Configuration
    private static let confidenceThresholdForAutoOrganize: Double = 0.40
    private static let confidenceThresholdForSuggestion: Double = 0.20
    private static let multiCategoryThreshold: Double = 0.35
    
    // MARK: - Comedy Category Lexicon
    private static let categories: [String: CategoryKeywords] = [
        "Puns": CategoryKeywords(keywords: [("pun", 1.0), ("wordplay", 1.0), ("play on words", 1.0), ("double meaning", 0.9), ("homophone", 0.9), ("fruit flies", 0.8), ("arrow", 0.6)]),
        "Roasts": CategoryKeywords(keywords: [("roast", 1.0), ("insult", 0.9), ("you're so", 0.9), ("ugly", 0.9), ("trash", 0.8), ("burn", 0.7)]),
        "One-Liners": CategoryKeywords(keywords: [("one liner", 1.0), ("quick", 0.7), ("short", 0.7), ("punchline", 0.8), ("she looked", 0.7)]),
        "Knock-Knock": CategoryKeywords(keywords: [("knock knock", 1.0), ("who's there", 1.0), ("boo who", 0.9), ("interrupting", 0.8)]),
        "Dad Jokes": CategoryKeywords(keywords: [("dad joke", 1.0), ("scarecrow", 0.9), ("outstanding in his field", 1.0), ("corny", 0.8), ("groan", 0.6)]),
        "Sarcasm": CategoryKeywords(keywords: [("sarcasm", 1.0), ("sarcastic", 1.0), ("oh great", 1.0), ("yeah right", 0.9), ("sure", 0.7)]),
        "Irony": CategoryKeywords(keywords: [("irony", 1.0), ("ironic", 1.0), ("unexpected", 0.8), ("fire station", 0.9), ("burned down", 0.9)]),
        "Satire": CategoryKeywords(keywords: [("satire", 1.0), ("satirical", 1.0), ("society", 0.8), ("politics", 0.8), ("the daily show", 1.0)]),
        "Dark Humor": CategoryKeywords(keywords: [("dark humor", 1.0), ("death", 0.9), ("tragedy", 0.9), ("suicide", 1.0), ("bomber", 0.8), ("blast", 0.7)]),
        "Observational": CategoryKeywords(keywords: [("observational", 1.0), ("why do", 0.9), ("have you ever", 0.9), ("driveway", 0.8), ("parkway", 0.8)]),
        "Anecdotal": CategoryKeywords(keywords: [("one time", 1.0), ("story", 0.8), ("this happened", 0.9), ("friend", 0.7), ("drunk", 0.6)]),
        "Self-Deprecating": CategoryKeywords(keywords: [("self deprecating", 1.0), ("i'm so", 0.9), ("i'm not", 0.9), ("i suck", 0.8), ("i'm terrible", 0.8)]),
        "Anti-Jokes": CategoryKeywords(keywords: [("anti joke", 1.0), ("not really a joke", 0.9), ("why did the chicken", 0.9), ("other side", 0.8)]),
        "Riddles": CategoryKeywords(keywords: [("riddle", 1.0), ("what has", 1.0), ("clever answer", 0.9), ("legs", 0.7), ("morning", 0.6), ("evening", 0.6)]),
        "Other": CategoryKeywords(keywords: [], weight: 0.2)
    ]
    
    /// Public accessor for available category names used for organizing jokes
    static func getCategories() -> [String] {
        // Expose keys of the internal categories lexicon, sorted alphabetically with "Other" last
        let names = Array(categories.keys)
        let sorted = names.sorted { a, b in
            if a == "Other" { return false }
            if b == "Other" { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return sorted
    }
    
    // MARK: - Style Lexicons
    private static let styleCueLexicon: [String: [String]] = [
        "Self-Deprecating": ["i'm so", "i'm not", "i suck", "i'm terrible"],
        "Observational": ["have you ever", "why do", "isn't it weird"],
        "Anecdotal": ["one time", "story", "so there i was"],
        "Sarcasm": ["yeah right", "sure", "great", "wonderful", "of course"],
        "Dark": ["death", "suicide", "funeral", "grave"],
        "Satire": ["society", "politics", "system", "corporate"],
        "Roast": ["you're so", "look at you", "sit down"],
        "Dad": ["dad", "kids", "son", "daughter"],
        "Wordplay": ["pun", "wordplay", "double meaning"],
        "Anti-Joke": ["not even a joke", "literal", "just"],
        "Knock-Knock": ["knock knock", "who's there"],
        "Riddle": ["what has", "who am i", "clever answer"],
        "Irony": ["ironically", "turns out", "of course the"],
        "One-Liner": ["short", "quick", "line"],
        "Story": ["long story", "cut to", "flash forward"],
        "Blue": ["explicit", "naughty", "bedroom"],
        "Topical": ["today", "headline", "trending"],
        "Crowd": ["sir", "ma'am", "front row"]
    ]
    
    private static let toneKeywords: [String: [String]] = [
        "Playful": ["lol", "haha", "silly", "goofy"],
        "Cynical": ["of course", "naturally", "figures"],
        "Angry": ["hate", "furious", "annoyed"],
        "Confessional": ["honestly", "truth", "real talk"],
        "Dark": ["death", "suicide", "grave"],
        "Hopeful": ["maybe", "believe", "hope"],
        "Cringe": ["awkward", "embarrassing"]
    ]
    
    private static let craftSignalsLexicon: [String: [String]] = [
        "Rule of Three": ["first", "second", "third", "one", "two", "three"],
        "Callback": ["again", "like before", "remember"],
        "Misdirection": ["but", "instead", "actually", "turns out"],
        "Act-Out": ["(acts", "[act", "stage"],
        "Crowd Work": ["sir", "ma'am", "front row", "table"],
        "Question/Punch": ["?", "answer is", "because"],
        "Absurd Heighten": ["then suddenly", "escalated", "spiraled"]
    ]
    
    
    /// Analyzes joke structure heuristics for a given text
    private static func analyzeJokeStructure(_ text: String) -> JokeStructure {
        let lower = text.lowercased()
        let hasQ = lower.contains("?") || lower.contains("why ") || lower.contains("what ") || lower.contains("how ")
        let hasAnswerIndicators = lower.contains("because") || lower.contains("so ") || lower.contains("that's why")
        let lines = text.split(separator: "\n").map { String($0) }
        let setupLines = lines.prefix { !$0.contains("?") }.count
        let punchLines = max(1, lines.count - setupLines)

        // Wordplay heuristic using homophones/double meanings already defined
        var wordplay = 0.0
        for set in homophoneSets {
            let present = set.filter { lower.contains($0) }
            if present.count >= 2 { wordplay += 0.5; break }
        }
        for (word, _) in doubleMeaningWords { if lower.contains(word) { wordplay += 0.1 } }
        wordplay = min(wordplay, 1.0)

        // Determine format
        let format: JokeFormat
        if lower.contains("knock knock") { format = .sequential }
        else if hasQ && hasAnswerIndicators { format = .questionAnswer }
        else if lines.count <= 2 && text.count < 140 { format = .oneLiner }
        else if lower.contains("\n") && (lower.contains("then ") || lower.contains("turns out") || lower.contains("but ")) { format = .storyTwist }
        else { format = .unknown }

        return JokeStructure(
            hasSetup: hasQ || setupLines > 0,
            hasPunchline: hasAnswerIndicators || punchLines > 0,
            format: format,
            wordplayScore: wordplay,
            setupLineCount: setupLines,
            punchlineLineCount: punchLines,
            questionAnswerPattern: format == .questionAnswer,
            storyTwistPattern: format == .storyTwist,
            oneLiners: format == .oneLiner ? 1 : 0,
            dialogueCount: lower.components(separatedBy: ": ").count - 1
        )
    }
    
    private static func scoreCategories(in text: String) -> [TopicMatch] {
        var results: [TopicMatch] = []
        for (category, keywords) in categories {
            let hits = keywords.keywords.filter { text.containsWord($0.0) }
            guard !hits.isEmpty else { continue }
            let weightSum = keywords.keywords.reduce(0.0) { $0 + $1.1 }
            let score = hits.reduce(0.0) { $0 + $1.1 }
            let lengthBoost = min(Double(text.count) / 800.0, 0.15)
            let confidence = min(1.0, (score / max(weightSum, 1.0)) + lengthBoost)
            results.append(TopicMatch(category: category, confidence: confidence, evidence: hits.map { $0.0 }))
        }
        return results.sorted { $0.confidence > $1.confidence }
    }
    
    private static func analyzeStyle(in text: String) -> StyleAnalysis {
        var styleScores: [(String, Int)] = []
        for (tag, cues) in styleCueLexicon {
            let hits = cues.filter { text.contains($0) }
            guard !hits.isEmpty else { continue }
            styleScores.append((tag, hits.count))
        }
        let tags = styleScores.sorted { $0.1 > $1.1 }.map { $0.0 }.prefix(4)
        
        var toneScores: [(String, Int)] = []
        for (tone, cues) in toneKeywords {
            let hits = cues.filter { text.contains($0) }
            if !hits.isEmpty { toneScores.append((tone, hits.count)) }
        }
        let tone = toneScores.sorted { $0.1 > $1.1 }.first?.0
        
        var craftHits: [String] = []
        for (signal, cues) in craftSignalsLexicon {
            if cues.contains(where: { text.contains($0) }) {
                craftHits.append(signal)
            }
        }
        
        var structureScore = 0.0
        if text.contains("setup") { structureScore += 0.15 }
        if text.contains("punchline") { structureScore += 0.15 }
        if text.contains("tag") { structureScore += 0.1 }
        let questionMarks = text.components(separatedBy: "?").count - 1
        structureScore += min(0.2, Double(max(0, questionMarks)) * 0.05)
        structureScore = min(1.0, structureScore)
        
        return StyleAnalysis(tags: Array(tags), tone: tone, craftSignals: craftHits, structureScore: structureScore, hook: tags.first ?? tone)
    }
    
    private static func reasoning(for match: TopicMatch, style: StyleAnalysis, structure: JokeStructure) -> String {
        let confidenceText: String
        switch match.confidence {
        case 0.75...: confidenceText = "very confident"
        case 0.5..<0.75: confidenceText = "confident"
        case 0.35..<0.5: confidenceText = "moderately confident"
        default: confidenceText = "suggested"
        }
        
        var details: [String] = []
        
        if let hook = style.hook {
            details.append("\(hook) vibe")
        }
        
        if structure.structureConfidence > 0.6 {
            details.append("strong structure")
        }
        
        if structure.wordplayScore > 0.5 {
            details.append("wordplay detected")
        }
        
        if !details.isEmpty {
            return "Matches \(match.evidence.count) cues, \(details.joined(separator: ", ")) — \(confidenceText)."
        }
        
        return "Matches \(match.evidence.count) cues — \(confidenceText)."
    }
    
    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

struct CategoryKeywords {
    let keywords: [(String, Double)]
    let weight: Double
    init(keywords: [(String, Double)], weight: Double = 1.0) {
        self.keywords = keywords
        self.weight = weight
    }
}

extension String {
    func containsWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(startIndex..., in: self)
            return regex.firstMatch(in: self, options: [], range: range) != nil
        } catch {
            return contains(word)
        }
    }
}
