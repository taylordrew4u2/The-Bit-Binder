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

    private static let writingStrugglePatterns: [String] = [
        "i'm stuck", "im stuck", "i am stuck", "i'm blocked", "im blocked",
        "i can't write", "i cant write", "i cannot write", "can't write",
        "cant write", "cannot write", "i'm struggling", "im struggling",
        "i don't know what to do", "i dont know what to do",
        "what should i do with this bit", "what do i do with this bit",
        "how do i fix this punchline", "how can i fix this punchline",
        "fix this punchline", "fix my punchline", "fix this bit",
        "fix my bit", "make this funnier", "punch this up",
        "punch up this", "help me with this bit", "help me with my bit",
        "help me with this joke", "help me with my joke"
    ]

    private static let acknowledgments: Set<String> = [
        "ok", "okay", "thanks", "thank you", "thx", "cool", "got it",
        "gotcha", "nice", "great", "perfect", "yep", "yeah", "yes",
        "no", "nah", "nope", "sure", "bet", "word", "dope", "sick",
        "lol", "lmao", "haha", "ha"
    ]

    private static let explicitActionPhrases: [String] = [
        "save ", "add ", "create ", "make ", "start ", "open ", "show ", "find ",
        "search ", "delete ", "remove ", "rename ", "move ", "import ", "export ",
        "sync ", "record ", "transcribe ", "turn on ", "turn off ", "toggle ",
        "mark ", "tag ", "attach ", "play ", "present "
    ]

    private static let writingCommandPhrases: [String] = [
        "analyze", "improve", "punch up", "rewrite", "shorten", "expand",
        "generate", "write", "give me", "compare", "summarize", "suggest",
        "brainstorm", "roast", "crowdwork"
    ]

    static func classify(_ input: String) -> ConversationMode {
        let result = classifyWithoutRouting(input)
        if result == .reflective && shouldUseIntentRouting(input) {
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

        if isPersonalWritingStruggle(lower, tokens: normalizedTokens) {
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
            return hasComedyRelevance(lower) ? .creativeFactual : .simpleFactual
        }

        let matchesFactualPattern = factualPatterns.contains { pattern in
            lower.hasPrefix(pattern) || lower.contains(" \(pattern) ") || lower.contains(pattern)
        }
        if matchesFactualPattern {
            return hasComedyRelevance(lower) ? .creativeFactual : .simpleFactual
        }

        if isGeneralQuestion(trimmed) {
            return hasComedyRelevance(lower) ? .creativeFactual : .simpleFactual
        }

        return .reflective
    }

    static func shouldUseIntentRouting(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        let tokens = Set(
            lower
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )

        if isPersonalWritingStruggle(lower, tokens: tokens) {
            return false
        }

        if classifyWithoutRouting(trimmed) != .reflective {
            return false
        }

        return hasExplicitActionCue(lower)
    }

    static func isGeneralQuestion(_ input: String) -> Bool {
        let lower = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower.hasSuffix("?") { return true }

        let firstWord = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? ""

        return ["who", "what", "where", "when", "why", "how"].contains(firstWord)
    }

    private static func hasComedyRelevance(_ lower: String) -> Bool {
        creativeModifiers.contains { lower.contains($0) }
    }

    private static func hasExplicitActionCue(_ lower: String) -> Bool {
        if explicitActionPhrases.contains(where: { lower.hasPrefix($0) || lower.contains(" \($0)") }) {
            return true
        }

        return writingCommandPhrases.contains { lower.hasPrefix($0) || lower.contains(" \($0)") }
    }

    private static func isPersonalWritingStruggle(_ lower: String, tokens: Set<String>) -> Bool {
        if writingStrugglePatterns.contains(where: { lower.contains($0) }) {
            return true
        }

        let hasSelfReference = !reflectivePronouns.isDisjoint(with: tokens)
        let writingTargets = ["joke", "bit", "punchline", "act", "set", "premise", "tag"]
        let repairVerbs = ["fix", "rewrite", "improve", "work", "do", "change", "cut"]
        let hasWritingTarget = writingTargets.contains { lower.contains($0) }
        let hasRepairVerb = repairVerbs.contains { lower.contains($0) }

        return hasSelfReference && hasWritingTarget && hasRepairVerb
    }
}
