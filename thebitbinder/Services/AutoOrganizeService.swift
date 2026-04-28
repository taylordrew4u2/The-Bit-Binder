//
//  AutoOrganizeService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/7/25.
//

import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

// MARK: - Apple AI Generable Types

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable(description: "A comedy joke categorization result")
struct AppleAICategoryResult {
    @Guide(description: "The best-fitting category name from the available list")
    var category: String

    @Guide(description: "Confidence from 0.0 to 1.0")
    var confidence: Double

    @Guide(description: "Short explanation of why this category fits")
    var reasoning: String

    @Guide(description: "Key words from the joke that support this categorization", .maximumCount(5))
    var matchedKeywords: [String]
}
#endif

// MARK: - Organize Mode

enum OrganizeMode: String, CaseIterable, Identifiable {
    case topic  = "Topic"
    case tone   = "Tone"
    case format = "Format"
    case style  = "Style"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var subtitle: String {
        switch self {
        case .topic:  return "Puns, Roasts, Dark Humor, Dad Jokes..."
        case .tone:   return "Playful, Cynical, Dark, Hopeful..."
        case .format: return "One-liners, Q&A, Stories, Knock-Knock..."
        case .style:  return "Observational, Crowd Work, Wordplay..."
        }
    }

    var iconName: String {
        switch self {
        case .topic:  return "text.book.closed"
        case .tone:   return "theatermasks"
        case .format: return "list.bullet.rectangle"
        case .style:  return "person.wave.2"
        }
    }
}

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

    /// Categorize a joke using the best available AI, with keyword fallback.
    /// Priority: Apple Intelligence (FoundationModels) → MLX → keywords.
    static func aiCategorize(content: String, existingFolders: [String] = [], mode: OrganizeMode = .topic) async -> [CategoryMatch] {
        // 1. Try Apple Intelligence (no download needed, built into iOS 26+)
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            do {
                let result = try await appleAICategorize(content: content, existingFolders: existingFolders, mode: mode)
                if !result.isEmpty { return result }
            } catch {
                #if DEBUG
                print("[AutoOrganize] Apple AI failed, trying next: \(error.localizedDescription)")
                #endif
            }
        }
#endif

        // 2. Try MLX on-device model (requires HuggingFace download)
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        do {
            return try await mlxCategorize(content: content, existingFolders: existingFolders, mode: mode)
        } catch {
            #if DEBUG
            print("[AutoOrganize] MLX failed, falling back to keywords: \(error.localizedDescription)")
            #endif
        }
#endif

        // 3. Keyword fallback (always available)
        return categorize(content: content, mode: mode)
    }

    /// Returns `true` when any AI categorization engine is available.
    static var isAIAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if SystemLanguageModel(guardrails: .permissiveContentTransformations).isAvailable {
                return true
            }
        }
#endif
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        return true
#else
        return false
#endif
    }

    // MARK: - Local Categorization

    /// Dispatches to the appropriate keyword-based categorizer for the chosen mode.
    static func categorize(content: String, mode: OrganizeMode = .topic) -> [CategoryMatch] {
        switch mode {
        case .topic:  return categorizeByTopic(content: content)
        case .tone:   return categorizeByTone(content: content)
        case .format: return categorizeByFormat(content: content)
        case .style:  return categorizeByStyle(content: content)
        }
    }

    /// Returns the category names available for a given organize mode.
    static func getCategories(for mode: OrganizeMode = .topic) -> [String] {
        switch mode {
        case .topic:
            return getCategories()
        case .tone:
            return (Array(toneKeywords.keys) + ["Neutral"]).sorted()
        case .format:
            return ["One-Liner", "Question & Answer", "Story", "Knock-Knock", "Dialogue", "Sequential", "Other"]
        case .style:
            return (Array(styleCueLexicon.keys) + ["Other"]).sorted { a, b in
                if a == "Other" { return false }
                if b == "Other" { return true }
                return a < b
            }
        }
    }

    // MARK: - Topic Categorization (default)

    private static func categorizeByTopic(content: String) -> [CategoryMatch] {
        let normalized = normalize(content)
        let topicMatches = scoreCategories(in: normalized)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(content)
        var matches: [CategoryMatch] = topicMatches.map { match in
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

        // Smart fallback: when no keywords matched, infer a category from
        // structure, length, pronouns, and style cues so the joke doesn't
        // just land in "Other" with zero signal.
        if matches.isEmpty {
            let inferred = inferCategoryFromStructure(
                content: content, normalized: normalized,
                style: style, structure: structure
            )
            matches = [inferred]
        }

        return matches
    }

    /// Last-resort heuristic when the keyword lexicon doesn't match anything.
    /// Uses joke length, structure, pronouns, and style cues to pick the
    /// single most-likely category.
    private static func inferCategoryFromStructure(
        content: String,
        normalized: String,
        style: StyleAnalysis,
        structure: JokeStructure
    ) -> CategoryMatch {
        let words = normalized.split(separator: " ")
        let wordCount = words.count
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Pronoun density
        let iCount = words.filter { $0 == "i" || $0 == "i'm" || $0 == "i've" || $0 == "my" || $0 == "me" }.count
        let youCount = words.filter { $0 == "you" || $0 == "you're" || $0 == "your" || $0 == "you've" }.count
        let selfFocus = wordCount > 0 ? Double(iCount) / Double(wordCount) : 0
        let youFocus = wordCount > 0 ? Double(youCount) / Double(wordCount) : 0

        var bestCategory = "Other"
        var bestConfidence = 0.35
        var reason = "Inferred from structure"

        // Knock-knock is unmistakable
        if normalized.contains("knock knock") || normalized.contains("knock-knock") {
            return CategoryMatch(
                category: "Knock-Knock", confidence: 0.95,
                reasoning: "Knock-knock pattern detected",
                matchedKeywords: ["knock knock"],
                styleTags: style.tags, emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            )
        }

        // Short jokes (< 20 words, 1-2 lines) → One-Liners
        if wordCount <= 20 && lines.count <= 2 {
            bestCategory = "One-Liners"
            bestConfidence = 0.55
            reason = "Short format — likely a one-liner"
        }
        // Q&A structure → Dad Jokes or Observational
        else if structure.format == .questionAnswer {
            if selfFocus > 0.05 {
                bestCategory = "Observational"
                bestConfidence = 0.50
                reason = "Question-answer with self-reference — observational style"
            } else {
                bestCategory = "Dad Jokes"
                bestConfidence = 0.50
                reason = "Clean question-answer setup — dad joke pattern"
            }
        }
        // Heavy self-pronouns → Self-Deprecating or Anecdotal
        else if selfFocus > 0.08 {
            if wordCount > 40 {
                bestCategory = "Anecdotal"
                bestConfidence = 0.50
                reason = "Long personal narrative"
            } else {
                bestCategory = "Self-Deprecating"
                bestConfidence = 0.45
                reason = "Strong self-reference"
            }
        }
        // Heavy you-pronouns → Roasts
        else if youFocus > 0.08 {
            bestCategory = "Roasts"
            bestConfidence = 0.45
            reason = "Directed at someone (you-focused)"
        }
        // Long narrative → Anecdotal
        else if wordCount > 60 || lines.count > 4 {
            bestCategory = "Anecdotal"
            bestConfidence = 0.45
            reason = "Long-form narrative"
        }
        // Story twist structure
        else if structure.format == .storyTwist {
            bestCategory = "Anecdotal"
            bestConfidence = 0.50
            reason = "Story with a twist"
        }

        // Style cue override — if the style analyzer found a strong signal
        if let hook = style.hook {
            let styleToCategory: [String: String] = [
                "Self-Deprecating": "Self-Deprecating",
                "Observational": "Observational",
                "Anecdotal": "Anecdotal",
                "Sarcasm": "Sarcasm",
                "Dark": "Dark Humor",
                "Satire": "Satire",
                "Roast": "Roasts",
                "Dad": "Dad Jokes",
                "Wordplay": "Puns",
                "Knock-Knock": "Knock-Knock",
                "Riddle": "Riddles",
                "Irony": "Irony",
            ]
            if let mapped = styleToCategory[hook] {
                // Only override if style signal is stronger than our structure guess
                let styleConfidence = 0.50
                if styleConfidence >= bestConfidence {
                    bestCategory = mapped
                    bestConfidence = styleConfidence
                    reason = "\(hook) style detected"
                }
            }
        }

        return CategoryMatch(
            category: bestCategory,
            confidence: bestConfidence,
            reasoning: reason,
            matchedKeywords: [],
            styleTags: style.tags,
            emotionalTone: style.tone,
            craftSignals: style.craftSignals,
            structureScore: structure.structureConfidence
        )
    }

    // MARK: - Configuration
    private static let confidenceThresholdForAutoOrganize: Double = 0.40
    private static let confidenceThresholdForSuggestion: Double = 0.20
    private static let multiCategoryThreshold: Double = 0.35
    
    // MARK: - Comedy Category Lexicon
    // Keywords include both meta-labels AND actual content patterns found in jokes.
    private static let categories: [String: CategoryKeywords] = [
        "Puns": CategoryKeywords(keywords: [
            ("pun", 1.0), ("wordplay", 1.0), ("play on words", 1.0), ("double meaning", 0.9),
            // Common pun structures
            ("walks into a bar", 0.9), ("no pun intended", 1.0), ("get it", 0.7),
            ("lettuce", 0.7), ("current", 0.6), ("berry", 0.7), ("cereal", 0.6),
            ("grizzly", 0.6), ("impasta", 1.0), ("nacho", 0.7), ("shell", 0.5),
            ("mussel", 0.8), ("bass", 0.5), ("sole", 0.5), ("fishy", 0.7),
            ("punny", 1.0), ("egg-cellent", 1.0), ("un-bee-lievable", 1.0),
            ("a-maize-ing", 1.0), ("gouda", 0.7), ("brie", 0.6), ("feta", 0.6),
        ]),
        "Roasts": CategoryKeywords(keywords: [
            ("roast", 1.0), ("insult", 0.9),
            ("you're so", 0.9), ("you look like", 0.9), ("your face", 0.8),
            ("ugly", 0.9), ("stupid", 0.8), ("dumb", 0.7), ("trash", 0.7),
            ("you remind me of", 0.8), ("even your", 0.7), ("nobody wants", 0.7),
            ("looks like", 0.6), ("smells like", 0.7), ("built like", 0.8),
            ("yo mama", 1.0), ("your mom", 0.9), ("your mama", 0.9),
        ]),
        "One-Liners": CategoryKeywords(keywords: [
            ("one liner", 1.0), ("one-liner", 1.0),
            // One-liners are mostly detected by structure (short + punchy), but
            // these content cues help too:
            ("i told my", 0.6), ("my wife said", 0.6), ("my doctor said", 0.6),
            ("the problem with", 0.6), ("i asked", 0.5), ("he said", 0.5),
        ]),
        "Knock-Knock": CategoryKeywords(keywords: [
            ("knock knock", 1.0), ("who's there", 1.0), ("boo who", 0.9),
            ("interrupting", 0.8), ("knock-knock", 1.0),
        ]),
        "Dad Jokes": CategoryKeywords(keywords: [
            ("dad joke", 1.0), ("hi hungry", 1.0), ("hi tired", 0.9),
            ("scarecrow", 0.8), ("outstanding in his field", 1.0),
            ("corny", 0.7), ("groan", 0.5),
            // Innocent/wholesome setup-punchlines common in dad jokes
            ("did you hear about", 0.6), ("what do you call", 0.7),
            ("how does a", 0.6), ("why can't", 0.5), ("what did the", 0.6),
            ("because it", 0.4), ("nacho cheese", 0.9), ("two fish", 0.7),
            ("skeleton", 0.5), ("no body", 0.7), ("sea weed", 0.7),
        ]),
        "Sarcasm": CategoryKeywords(keywords: [
            ("sarcasm", 1.0), ("sarcastic", 1.0),
            ("oh great", 0.9), ("yeah right", 0.8), ("what a surprise", 0.9),
            ("because that makes sense", 0.9), ("shocking", 0.6),
            ("how wonderful", 0.8), ("absolutely fantastic", 0.8),
            ("who would have thought", 0.8), ("totally", 0.5),
            ("genius", 0.5), ("brilliant idea", 0.7),
        ]),
        "Irony": CategoryKeywords(keywords: [
            ("irony", 1.0), ("ironic", 1.0), ("ironically", 0.9),
            ("turns out", 0.7), ("the twist", 0.7), ("plot twist", 0.8),
            ("fire station burned", 0.9), ("of all places", 0.7),
            ("who knew", 0.6), ("go figure", 0.7), ("wouldn't you know", 0.7),
        ]),
        "Satire": CategoryKeywords(keywords: [
            ("satire", 1.0), ("satirical", 1.0),
            ("government", 0.8), ("politician", 0.9), ("congress", 0.8),
            ("society", 0.7), ("politics", 0.8), ("election", 0.7),
            ("corporate", 0.7), ("ceo", 0.7), ("billionaire", 0.7),
            ("breaking news", 0.8), ("study finds", 0.7), ("experts say", 0.7),
            ("according to", 0.5), ("the system", 0.6), ("bureaucracy", 0.8),
        ]),
        "Dark Humor": CategoryKeywords(keywords: [
            ("dark humor", 1.0), ("dark joke", 1.0),
            ("death", 0.8), ("dead", 0.7), ("die", 0.6), ("died", 0.7),
            ("funeral", 0.9), ("coffin", 0.9), ("grave", 0.8), ("cemetery", 0.9),
            ("murder", 0.9), ("kill", 0.7), ("suicide", 1.0),
            ("orphan", 0.8), ("cancer", 0.8), ("tumor", 0.8),
            ("blind", 0.5), ("deaf", 0.5), ("wheelchair", 0.6),
            ("tragedy", 0.8), ("disaster", 0.7), ("bomb", 0.7),
            ("corpse", 0.9), ("autopsy", 0.9), ("morgue", 0.9),
        ]),
        "Observational": CategoryKeywords(keywords: [
            ("observational", 1.0),
            ("you ever notice", 0.9), ("have you ever", 0.8), ("isn't it weird", 0.9),
            ("why do we", 0.9), ("why is it that", 0.9), ("ever wonder", 0.8),
            ("why do they call", 0.8), ("you know what's funny", 0.8),
            ("anyone else", 0.7), ("am i the only one", 0.8),
            ("think about it", 0.6), ("doesn't make sense", 0.7),
            ("the thing about", 0.7), ("what's the deal with", 0.9),
            ("driveway", 0.6), ("parkway", 0.6),
        ]),
        "Anecdotal": CategoryKeywords(keywords: [
            ("one time", 0.8), ("this one time", 0.9), ("true story", 0.9),
            ("so i was", 0.8), ("the other day", 0.8), ("last week", 0.7),
            ("my buddy", 0.7), ("my friend", 0.6), ("my ex", 0.7),
            ("so there i was", 0.9), ("i remember when", 0.8),
            ("happened to me", 0.8), ("i swear", 0.6), ("no lie", 0.7),
            ("this actually happened", 0.9), ("growing up", 0.6),
            ("back in", 0.5), ("when i was", 0.6), ("i once", 0.6),
        ]),
        "Self-Deprecating": CategoryKeywords(keywords: [
            ("self deprecating", 1.0),
            ("i'm so ugly", 1.0), ("i'm so fat", 1.0), ("i'm so dumb", 1.0),
            ("i'm so stupid", 1.0), ("i'm so broke", 0.9), ("i'm so lonely", 0.9),
            ("i'm such a", 0.8), ("i suck", 0.8), ("i'm terrible at", 0.8),
            ("even my mom", 0.7), ("my therapist", 0.7), ("my dating life", 0.8),
            ("nobody likes me", 0.8), ("i can't even", 0.6),
            ("look at me", 0.5), ("sad excuse", 0.7), ("i'm the type of person", 0.7),
            ("i'm not smart", 0.8), ("i'm not good", 0.6),
        ]),
        "Anti-Jokes": CategoryKeywords(keywords: [
            ("anti joke", 1.0), ("anti-joke", 1.0),
            ("not really a joke", 0.9), ("that's it", 0.7),
            ("why did the chicken", 0.7), ("to get to the other side", 0.8),
            ("and then nothing happened", 0.9), ("the end", 0.5),
            ("literally", 0.4), ("because that's what happened", 0.9),
        ]),
        "Riddles": CategoryKeywords(keywords: [
            ("riddle", 1.0), ("riddle me this", 1.0),
            ("what has", 0.8), ("what am i", 0.9), ("who am i", 0.8),
            ("the more you take", 0.8), ("what can you", 0.7),
            ("what gets", 0.7), ("what comes", 0.6),
            ("answer is", 0.6), ("give up", 0.5),
        ]),
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
        "Self-Deprecating": ["i'm so", "i'm not", "i suck", "i'm terrible", "look at me", "my life", "even my", "i can't even", "i'm the worst"],
        "Observational": ["have you ever", "why do", "isn't it weird", "you ever notice", "what's the deal", "anyone else", "am i the only", "think about it", "doesn't make sense"],
        "Anecdotal": ["one time", "story", "so there i was", "the other day", "true story", "this happened", "i remember", "growing up", "back when", "my buddy"],
        "Sarcasm": ["yeah right", "sure", "great", "wonderful", "of course", "what a surprise", "genius", "brilliant", "shocking", "who would have thought"],
        "Dark": ["death", "dead", "die", "suicide", "funeral", "grave", "murder", "kill", "corpse", "cancer", "orphan", "coffin", "morgue"],
        "Satire": ["society", "politics", "system", "corporate", "government", "congress", "politician", "election", "billionaire", "ceo", "breaking news"],
        "Roast": ["you're so", "look at you", "sit down", "you look like", "built like", "yo mama", "your mom", "your face"],
        "Dad": ["dad", "kids", "son", "daughter", "what do you call", "did you hear", "how does a", "why can't"],
        "Wordplay": ["pun", "wordplay", "double meaning", "walks into a bar", "get it", "no pun intended"],
        "Anti-Joke": ["not even a joke", "literal", "just", "that's it", "the end", "nothing happened"],
        "Knock-Knock": ["knock knock", "who's there", "knock-knock"],
        "Riddle": ["what has", "who am i", "what am i", "the more you", "what gets", "give up"],
        "Irony": ["ironically", "turns out", "of course the", "plot twist", "who knew", "go figure", "wouldn't you know"],
        "One-Liner": ["i told my", "my wife said", "my doctor said", "the problem with"],
        "Story": ["long story", "cut to", "flash forward", "so anyway", "fast forward", "next thing i know"],
        "Blue": ["explicit", "naughty", "bedroom", "sex", "naked"],
        "Topical": ["today", "headline", "trending", "breaking", "just heard"],
        "Crowd": ["sir", "ma'am", "front row", "this guy", "you in the back"]
    ]
    
    private static let toneKeywords: [String: [String]] = [
        "Playful": ["lol", "haha", "silly", "goofy", "funny", "giggle", "tee hee", "wink"],
        "Cynical": ["of course", "naturally", "figures", "surprise surprise", "what a shock", "shocker", "who knew", "as expected"],
        "Angry": ["hate", "furious", "annoyed", "pissed", "sick of", "fed up", "rage", "angry"],
        "Confessional": ["honestly", "truth", "real talk", "not gonna lie", "confession", "guilty", "i admit"],
        "Dark": ["death", "dead", "die", "funeral", "murder", "kill", "grave", "suicide", "cancer", "coffin", "corpse"],
        "Hopeful": ["maybe", "believe", "hope", "one day", "someday", "dream", "wish", "bright side"],
        "Cringe": ["awkward", "embarrassing", "cringy", "uncomfortable", "yikes", "oof", "second-hand"],
        "Absurd": ["suddenly", "for some reason", "don't ask", "anyway", "random", "out of nowhere", "penguin"],
        "Deadpan": ["said nothing", "walked away", "stared", "silence", "no expression", "straight face", "matter of fact"],
        "Wholesome": ["love", "heart", "sweet", "kind", "precious", "adorable", "heartwarming"],
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

    // MARK: - Tone Categorization

    private static func categorizeByTone(content: String) -> [CategoryMatch] {
        let normalized = normalize(content)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(content)

        var results: [CategoryMatch] = []
        for (tone, cues) in toneKeywords {
            let hits = cues.filter { normalized.containsWord($0) }
            guard !hits.isEmpty else { continue }
            let confidence = min(1.0, Double(hits.count) / Double(max(cues.count, 1)) + 0.3)
            results.append(CategoryMatch(
                category: tone,
                confidence: confidence,
                reasoning: "Matches \(hits.count) tone cue\(hits.count == 1 ? "" : "s")",
                matchedKeywords: hits,
                styleTags: style.tags,
                emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            ))
        }

        if results.isEmpty, let detectedTone = style.tone {
            results.append(CategoryMatch(
                category: detectedTone,
                confidence: 0.4,
                reasoning: "Inferred from style analysis",
                matchedKeywords: [],
                styleTags: style.tags,
                emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            ))
        }

        if results.isEmpty {
            results.append(CategoryMatch(
                category: "Neutral",
                confidence: 0.3,
                reasoning: "No strong tone detected",
                matchedKeywords: [],
                styleTags: style.tags,
                emotionalTone: nil,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            ))
        }

        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Format Categorization

    private static func categorizeByFormat(content: String) -> [CategoryMatch] {
        let normalized = normalize(content)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(content)

        let formatName: String
        switch structure.format {
        case .questionAnswer: formatName = "Question & Answer"
        case .storyTwist:     formatName = "Story"
        case .oneLiner:       formatName = "One-Liner"
        case .dialogue:       formatName = "Dialogue"
        case .sequential:     formatName = "Sequential"
        case .unknown:        formatName = "Other"
        }

        return [CategoryMatch(
            category: formatName,
            confidence: max(0.5, structure.structureConfidence),
            reasoning: "Detected \(formatName.lowercased()) structure",
            matchedKeywords: [],
            styleTags: style.tags,
            emotionalTone: style.tone,
            craftSignals: style.craftSignals,
            structureScore: structure.structureConfidence
        )]
    }

    // MARK: - Style Categorization

    private static func categorizeByStyle(content: String) -> [CategoryMatch] {
        let normalized = normalize(content)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(content)

        var results: [CategoryMatch] = []
        for (tag, cues) in styleCueLexicon {
            let hits = cues.filter { normalized.contains($0) }
            guard !hits.isEmpty else { continue }
            let confidence = min(1.0, Double(hits.count) / Double(max(cues.count, 1)) + 0.2)
            results.append(CategoryMatch(
                category: tag,
                confidence: confidence,
                reasoning: "Matches \(hits.count) style cue\(hits.count == 1 ? "" : "s")",
                matchedKeywords: hits,
                styleTags: style.tags,
                emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            ))
        }

        if results.isEmpty {
            results.append(CategoryMatch(
                category: "Other",
                confidence: 0.3,
                reasoning: "No strong style cues detected",
                matchedKeywords: [],
                styleTags: style.tags,
                emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            ))
        }

        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Apple Intelligence Categorization (FoundationModels)

#if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func appleAICategorize(
        content: String,
        existingFolders: [String],
        mode: OrganizeMode
    ) async throws -> [CategoryMatch] {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard model.isAvailable else {
            throw AutoOrganizeError.appleAIUnavailable
        }

        let availableCategories = getCategories(for: mode)

        let modeDescription: String
        switch mode {
        case .topic:  modeDescription = "comedy genre/topic"
        case .tone:   modeDescription = "emotional tone"
        case .format: modeDescription = "joke structure/format"
        case .style:  modeDescription = "performance style"
        }

        let categoryList = availableCategories.joined(separator: ", ")
        let folderHint = existingFolders.isEmpty
            ? ""
            : " The user has these existing folders: \(existingFolders.joined(separator: ", "))."

        let instructions = """
            You are a comedy categorization engine. Categorize jokes by \(modeDescription). \
            Available categories: \(categoryList).\(folderHint) \
            Pick the single best-fitting category and give a confidence score from 0.0 to 1.0. \
            Provide a short reason and list the key words from the joke that led to your pick. \
            Return ONLY a JSON object with these fields: \
            {"category": "name", "confidence": 0.8, "reasoning": "why", "matchedKeywords": ["word1", "word2"]}
            """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: content)
        let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        let result = try parseAICategoryResult(from: output)

        // Enrich with style/tone/craft heuristics
        let normalized = normalize(content)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(content)

        return [CategoryMatch(
            category: result.category,
            confidence: min(1.0, max(0.0, result.confidence)),
            reasoning: result.reasoning,
            matchedKeywords: result.matchedKeywords,
            styleTags: style.tags,
            emotionalTone: style.tone,
            craftSignals: style.craftSignals,
            structureScore: structure.structureConfidence
        )]
    }

    private struct ParsedCategoryResult: Decodable {
        var category: String
        var confidence: Double
        var reasoning: String
        var matchedKeywords: [String]
    }

    private static func parseAICategoryResult(from text: String) throws -> ParsedCategoryResult {
        let jsonString: String
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            jsonString = String(text[start...end])
        } else {
            jsonString = text
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw AutoOrganizeError.appleAIUnavailable
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ParsedCategoryResult.self, from: data)
    }
#endif

    // MARK: - MLX LLM Categorization

#if canImport(MLXLLM) && canImport(MLXLMCommon)
    private static func mlxCategorize(
        content: String,
        existingFolders: [String],
        mode: OrganizeMode
    ) async throws -> [CategoryMatch] {
        let availableCategories = getCategories(for: mode)

        let modeDescription: String
        switch mode {
        case .topic:  modeDescription = "comedy genre/topic"
        case .tone:   modeDescription = "emotional tone"
        case .format: modeDescription = "joke structure/format"
        case .style:  modeDescription = "performance style"
        }

        let folderHint = existingFolders.isEmpty
            ? ""
            : "\nExisting user folders: \(existingFolders.joined(separator: ", "))"

        let systemPrompt = """
            You are a comedy categorization engine. Categorize the joke by \(modeDescription).
            Available categories: \(availableCategories.joined(separator: ", "))\(folderHint)
            Respond with a JSON array of 1-3 category matches. Each object must have:
            - "category": one of the available categories
            - "confidence": number from 0.0 to 1.0
            - "reasoning": short explanation
            - "matchedKeywords": array of relevant words from the joke
            No markdown fences, no extra text. Just the JSON array.
            """

        let response = try await MLXSharedRuntime.shared.generateSingleShot(
            systemPrompt: systemPrompt,
            userPrompt: content
        )

        return try parseCategorization(response, originalContent: content)
    }

    private static func parseCategorization(
        _ response: String,
        originalContent: String
    ) throws -> [CategoryMatch] {
        // Strip markdown code fences if present
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AutoOrganizeError.parseFailure
        }

        struct LLMCategoryMatch: Decodable {
            let category: String
            let confidence: Double
            let reasoning: String
            let matchedKeywords: [String]
        }

        let decoded = try JSONDecoder().decode([LLMCategoryMatch].self, from: data)

        // Enrich with style/tone/craft heuristics
        let normalized = normalize(originalContent)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(originalContent)

        return decoded.map { match in
            CategoryMatch(
                category: match.category,
                confidence: min(1.0, max(0.0, match.confidence)),
                reasoning: match.reasoning,
                matchedKeywords: match.matchedKeywords,
                styleTags: style.tags,
                emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            )
        }
    }
#endif
}

enum AutoOrganizeError: Error {
    case parseFailure
    case appleAIUnavailable
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
