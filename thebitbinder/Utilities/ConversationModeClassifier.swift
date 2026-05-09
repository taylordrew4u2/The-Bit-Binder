import Foundation

enum ConversationMode: Sendable {
    case reflective
    case simpleFactual
    case creativeFactual
    case appAction
}

struct ConversationModeClassifier {
    private static let router = BitBuddyIntentRouter.shared

    private static let reflectivePronouns: Set<String> = [
        "i", "im", "i'm", "ive", "i've", "me", "my", "mine", "myself"
    ]

    private static let reflectiveCues: [String] = [
        "feel", "feeling", "stuck", "lost", "confused", "unsure", "afraid",
        "worried", "anxious", "frustrated", "overwhelmed", "struggling",
        "blocked", "bombed", "bombing", "can't write", "cannot write",
        "don't know", "do not know", "what am i doing", "why am i", "should i"
    ]

    private static let factualPatterns: [String] = [
        "what's", "what is", "define", "definition of", "meaning of",
        "synonym for", "synonyms for", "how tall", "how old", "how long",
        "capital of", "who is", "where is", "when is", "spell", "pronounce",
        "difference between", "what does", "what are", "what was", "what were",
        "how do", "how can", "why is", "why does", "why do", "tell me about",
        "search for", "look up", "find out", "can you explain"
    ]

    private static let languageTaskPatterns: [String] = [
        "words that start with", "word that starts with", "words that starts with",
        "words that star with", "word that star with", "starts with", "start with",
        "begin with", "begins with", "beginning with",
        "synonym for", "synonyms for", "another word for",
        "sounds like", "sound like", "rhymes with", "rhyme with",
        "opposite of", "antonym for", "antonyms for"
    ]

    private static let creativeModifiers: [String] = [
        "funny", "comedy", "joke", "bit", "roast", "crowdwork", "heckler",
        "punchline", "punch up", "riff", "tagline"
    ]

    private static let acknowledgments: Set<String> = [
        "ok", "okay", "thanks", "thank you", "thx", "cool", "got it",
        "gotcha", "nice", "great", "perfect", "yep", "yeah", "yes",
        "no", "nah", "nope", "sure", "bet", "word", "dope", "sick",
        "lol", "lmao", "haha", "ha"
    ]

    static func classify(_ input: String) -> ConversationMode {
        let result = classifyWithoutRouting(input)
        if result == .reflective {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && router.route(trimmed) != nil {
                return .appAction
            }
        }
        return result
    }

    static func classifyWithoutRouting(_ input: String) -> ConversationMode {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .reflective }

        let lower = trimmed.lowercased()
        let normalizedTokens = Set(
            lower
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )

        if normalizedTokens.count <= 3, !normalizedTokens.isDisjoint(with: acknowledgments) {
            return .simpleFactual
        }

        let hasPronoun = !reflectivePronouns.isDisjoint(with: normalizedTokens)
        let hasReflectiveCue = reflectiveCues.contains { lower.contains($0) }
        if hasPronoun && hasReflectiveCue {
            return .reflective
        }

        let currentDatePatterns = [
            "what year", "current year", "what date", "today's date",
            "todays date", "what day is it", "what day is today",
            "what's today", "whats today"
        ]
        if currentDatePatterns.contains(where: { lower.contains($0) }) {
            return .simpleFactual
        }

        let matchesLanguageTask = languageTaskPatterns.contains { lower.contains($0) }
        if matchesLanguageTask {
            let hasCreativeModifier = creativeModifiers.contains { lower.contains($0) }
            return hasCreativeModifier ? .creativeFactual : .simpleFactual
        }

        let matchesFactualPattern = factualPatterns.contains { pattern in
            lower.hasPrefix(pattern) || lower.contains(" \(pattern) ") || lower.contains(pattern)
        }
        if matchesFactualPattern {
            let hasCreativeModifier = creativeModifiers.contains { lower.contains($0) }
            return hasCreativeModifier ? .creativeFactual : .simpleFactual
        }

        if lower.hasSuffix("?") {
            let questionStarts = [
                "who", "what", "when", "where", "why", "how", "is", "are",
                "do", "does", "did", "can", "could", "should", "would"
            ]
            let firstWord = lower
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .first(where: { !$0.isEmpty }) ?? ""

            if questionStarts.contains(firstWord) {
                let hasCreativeModifier = creativeModifiers.contains { lower.contains($0) }
                return hasCreativeModifier ? .creativeFactual : .simpleFactual
            }
        }

        return .reflective
    }
}
