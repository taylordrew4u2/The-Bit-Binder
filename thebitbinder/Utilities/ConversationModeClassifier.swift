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
        "difference between", "what does", "what are", "what was", "what were"
    ]

    private static let creativeModifiers: [String] = [
        "funny", "comedy", "joke", "bit", "roast", "crowdwork", "heckler",
        "punchline", "punch up", "riff", "tagline"
    ]

    static func classify(_ input: String) -> ConversationMode {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .appAction }

        if router.route(trimmed) != nil {
            return .appAction
        }

        let lower = trimmed.lowercased()
        let normalizedTokens = Set(
            lower
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )

        let hasPronoun = !reflectivePronouns.isDisjoint(with: normalizedTokens)
        let hasReflectiveCue = reflectiveCues.contains { lower.contains($0) }
        if hasPronoun && hasReflectiveCue {
            return .reflective
        }

        let matchesFactualPattern = factualPatterns.contains { lower.hasPrefix($0) || lower.contains(" \($0) ") }
        if matchesFactualPattern {
            let hasCreativeModifier = creativeModifiers.contains { lower.contains($0) }
            return hasCreativeModifier ? .creativeFactual : .simpleFactual
        }

        return .appAction
    }
}
