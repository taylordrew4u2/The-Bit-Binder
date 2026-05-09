import Foundation

final class SocraticGuideBackend: BitBuddyBackend {
    static let shared = SocraticGuideBackend()

    private static let prefixMarkers = [
        "words that start with", "word that starts with", "words that starts with",
        "words that star with", "word that star with", "starts with", "start with",
        "begin with", "begins with", "beginning with"
    ]

    private static let synonymMarkers = [
        "synonym for", "synonyms for", "another word for"
    ]

    private static let rhymeMarkers = [
        "rhymes with", "rhyme with"
    ]

    private static let soundLikeMarkers = [
        "sounds like", "sound like"
    ]

    private static let antonymMarkers = [
        "opposite of", "antonym for", "antonyms for"
    ]

    private static let lexicalWordBank: [String] = [
        "apple", "anchor", "angle", "artist", "avenue", "banana", "bottle", "brave",
        "bright", "candle", "chaos", "chuckle", "clever", "coffee", "comic", "crash",
        "danger", "delight", "dream", "echo", "electric", "energy", "fable", "famous",
        "fancy", "fire", "galaxy", "glory", "grin", "habit", "hammer", "happy",
        "hazy", "heckle", "hero", "honest", "hustle", "hype", "idea", "image",
        "jagged", "jolt", "juggle", "kettle", "laser", "legend", "magic", "major",
        "memory", "method", "mirror", "motion", "neon", "nerve", "orbit", "origin",
        "panic", "party", "pepper", "pocket", "punch", "quiet", "radar", "rattle",
        "reason", "rocket", "savage", "shadow", "signal", "sound", "spark", "story",
        "thunder", "ticket", "timing", "trouble", "velvet", "victory", "wild",
        "window", "wizard", "yellow", "zinger"
    ]

    private static let antonyms: [String: [String]] = [
        "good": ["bad", "awful", "poor"],
        "bad": ["good", "solid", "great"],
        "big": ["small", "tiny", "little"],
        "small": ["big", "huge", "massive"],
        "smart": ["dumb", "dense", "clueless"],
        "happy": ["sad", "miserable", "blue"],
        "sad": ["happy", "elated", "thrilled"],
        "angry": ["calm", "peaceful", "chill"],
        "fast": ["slow", "sluggish", "dragging"],
        "loud": ["quiet", "soft", "muted"]
    ]

    private init() {}

    var backendName: String { "Socratic Guide" }
    var isAvailable: Bool { true }
    var supportsStreaming: Bool { false }

    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        try await respond(
            message: message,
            session: session,
            dataContext: dataContext,
            roastMode: dataContext.isRoastMode
        ) ?? ""
    }

    func respond(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext,
        roastMode: Bool
    ) async throws -> String? {
        let mode = ConversationModeClassifier.classify(message)
        switch mode {
        case .appAction:
            return nil
        case .reflective:
            return try await generateReflectiveResponse(
                message: message,
                session: session,
                dataContext: dataContext,
                roastMode: roastMode
            )
        case .simpleFactual:
            return try await generateFactualResponse(
                message: message,
                session: session,
                dataContext: dataContext,
                mode: .simpleFactual,
                roastMode: roastMode
            )
        case .creativeFactual:
            return try await generateFactualResponse(
                message: message,
                session: session,
                dataContext: dataContext,
                mode: .creativeFactual,
                roastMode: roastMode
            )
        }
    }

    private func generateReflectiveResponse(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext,
        roastMode: Bool
    ) async throws -> String {
        if let localResponse = localReflectiveResponse(
            for: message,
            dataContext: dataContext,
            roastMode: roastMode
        ) {
            return localResponse
        }

        let prompt = buildPrompt(
            message: message,
            dataContext: dataContext,
            searchResult: nil
        )
        let instructions = BitBuddyResources.SocraticPersonality.prompt(
            for: .reflective,
            roastMode: roastMode
        )

        if let response = try await generateWithCurrentLLM(
            prompt: prompt,
            instructions: instructions,
            session: session
        ) {
            return response
        }

        return roastMode
            ? "Use the blunt version first, then trim it until it sounds like something you'd actually say on stage."
            : "Start with the clearest truthful sentence, then add the twist after it. If there is no twist yet, write the opposite of what the audience expects."
    }

    private func generateFactualResponse(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext,
        mode: ConversationMode,
        roastMode: Bool
    ) async throws -> String {
        if let directAnswer = localDirectFactualResponse(
            for: message,
            mode: mode,
            roastMode: roastMode
        ) {
            return directAnswer
        }

        if let localLanguageResponse = localLanguageTaskResponse(
            for: message,
            mode: mode,
            roastMode: roastMode
        ) {
            return localLanguageResponse
        }

        let searchResult: String?
        if isPersonalQuestion(normalizedQuery(message)) {
            searchResult = nil
        } else {
            searchResult = try await PrivateSearchService.search(message)
        }
        if mode == .simpleFactual, let searchResult, !searchResult.isEmpty {
            return searchResult
        }

        let prompt = buildPrompt(
            message: message,
            dataContext: dataContext,
            searchResult: searchResult
        )
        let instructions = BitBuddyResources.SocraticPersonality.prompt(
            for: mode,
            roastMode: roastMode
        )

        if let response = try await generateWithCurrentLLM(
            prompt: prompt,
            instructions: instructions,
            session: session
        ) {
            return response
        }

        let fallbackFact: String
        if let searchResult, !searchResult.isEmpty {
            fallbackFact = searchResult
        } else if isPersonalQuestion(normalizedQuery(message)) {
            fallbackFact = roastMode
                ? "I'm BitBuddy — a writing tool, not a person. Send me material and I'll make it meaner."
                : "I'm BitBuddy, a writing assistant built into BitBinder. I can help with jokes, sets, and brainstorms."
        } else {
            fallbackFact = "I can't connect to the internet right now. Try again when you have a connection."
        }
        switch mode {
        case .simpleFactual:
            return fallbackFact
        case .creativeFactual:
            if roastMode {
                return "\(fallbackFact) That answer has more edge than half the room."
            }
            return "\(fallbackFact) Not bad for a fact with stage presence."
        case .reflective, .appAction:
            return fallbackFact
        }
    }

    private func localDirectFactualResponse(
        for message: String,
        mode: ConversationMode,
        roastMode: Bool
    ) -> String? {
        guard mode == .simpleFactual else { return nil }

        let normalized = normalizedQuery(message)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,:;!?()[]{}"))

        if let currentDateAnswer = CurrentFacts.answer(for: normalized) {
            return currentDateAnswer
        }

        if normalized == "what color is the sky"
            || normalized == "what colour is the sky"
            || normalized == "what color is sky"
            || normalized == "what colour is sky" {
            return roastMode ? "Blue. Usually. Even roast mode cannot make the sky commit to a darker bit." : "Blue."
        }

        if normalized == "what is 2 plus 2"
            || normalized == "what's 2 plus 2"
            || normalized == "whats 2 plus 2"
            || normalized == "what is 2+2"
            || normalized == "what's 2+2"
            || normalized == "whats 2+2" {
            return "4."
        }

        if let personalAnswer = personalQuestionResponse(for: normalized, roastMode: roastMode) {
            return personalAnswer
        }

        return nil
    }

    private func personalQuestionResponse(for normalized: String, roastMode: Bool) -> String? {
        if normalized == "who are you" || normalized == "what are you" {
            return roastMode
                ? "I'm BitBuddy in roast mode: a writing assistant for roast material, tags, targets, and punch-ups."
                : "I'm BitBuddy, the built-in writing assistant for jokes, sets, brainstorms, imports, and app help."
        }

        if normalized.contains("what is your name") || normalized.contains("what's your name")
            || normalized.contains("whats your name") || normalized == "your name" {
            return roastMode
                ? "BitBuddy. The name's not the punchline — your material is."
                : "I'm BitBuddy, your built-in comedy writing partner."
        }

        if normalized.contains("how old are you") || normalized.contains("how old r u")
            || normalized.contains("what is your age") || normalized.contains("what's your age")
            || normalized.contains("whats your age") || normalized.contains("your age") {
            return roastMode
                ? "Old enough to know a weak tag when I hear one. Send me the line."
                : "I don't have an age — I'm built into BitBinder. But I'm always ready to work on material."
        }

        if normalized.contains("where are you from") || normalized.contains("where do you live")
            || normalized.contains("where are you") {
            return roastMode
                ? "I live in your phone, right next to all those drafts you haven't finished."
                : "I live right here in BitBinder on your device. Everything stays local."
        }

        if normalized.contains("are you real") || normalized.contains("are you a bot")
            || normalized.contains("are you a robot") || normalized.contains("are you human") {
            return roastMode
                ? "I'm a writing tool with opinions. Real enough to tell you that setup needs trimming."
                : "I'm BitBuddy — a built-in writing assistant, not a person. But I can help sharpen your material."
        }

        if normalized.contains("do you have feelings") || normalized.contains("can you feel")
            || normalized.contains("are you alive") || normalized.contains("are you sentient") {
            return roastMode
                ? "No feelings. Just pattern recognition and a low tolerance for weak punchlines."
                : "No feelings here — just a writing tool tuned for comedy. Send me what you're working on."
        }

        if normalized.contains("what can you do") || normalized.contains("what do you do") {
            return roastMode
                ? "Punch up roasts, sort targets, tag lines, build openers, find backups, and answer word questions. What do you need?"
                : "Analyze jokes, brainstorm premises, tighten wording, build set lists, answer language questions, and help with app features. What are you working on?"
        }

        if normalized.contains("do you like") || normalized.contains("what is your favorite")
            || normalized.contains("what's your favorite") || normalized.contains("whats your favorite")
            || normalized.contains("what is your favourite") || normalized.contains("what's your favourite") {
            return roastMode
                ? "I like tight punchlines and short setups. Everything else is filler."
                : "I'm partial to a clean callback, but I'll work with whatever style you bring."
        }

        let creatorPatterns = ["who made you", "who built you", "who created you"]
        if creatorPatterns.contains(where: { normalized.contains($0) }) {
            return "The hottest and funniest comic in the world... Taylor Drew!"
        }

        let aboutYouPatterns = [
            "tell me about yourself", "describe yourself", "introduce yourself"
        ]
        if aboutYouPatterns.contains(where: { normalized.contains($0) }) {
            return roastMode
                ? "I'm BitBuddy. Built into BitBinder. I sharpen roasts, sort targets, and call out weak tags. Skip the small talk — send me the line."
                : "I'm BitBuddy, the writing assistant built into BitBinder. I help with jokes, premises, set lists, brainstorms, and app features. What are you working on?"
        }

        return nil
    }

    private func localLanguageTaskResponse(
        for message: String,
        mode: ConversationMode,
        roastMode: Bool
    ) -> String? {
        let normalized = normalizedQuery(message)

        if let prefix = extractSuffix(in: normalized, markers: Self.prefixMarkers) {
            let matches = wordsStarting(with: prefix)
            guard !matches.isEmpty else {
                return formatLanguageFallback(
                    "I couldn't find a clean list for words starting with \(prefix).",
                    mode: mode,
                    roastMode: roastMode
                )
            }

            return formatLanguageResult(
                intro: "Words starting with \(prefix)",
                items: matches,
                mode: mode,
                roastMode: roastMode
            )
        }

        if let term = extractSuffix(in: normalized, markers: Self.synonymMarkers) {
            let matches = synonyms(for: term)
            guard !matches.isEmpty else {
                return formatLanguageFallback(
                    "I don't have a strong synonym list for \(term) yet.",
                    mode: mode,
                    roastMode: roastMode
                )
            }

            return formatLanguageResult(
                intro: "Synonyms for \(term)",
                items: matches,
                mode: mode,
                roastMode: roastMode
            )
        }

        if let term = extractSuffix(in: normalized, markers: Self.antonymMarkers) {
            let matches = antonyms(for: term)
            guard !matches.isEmpty else {
                return formatLanguageFallback(
                    "I don't have a clean opposite list for \(term) yet.",
                    mode: mode,
                    roastMode: roastMode
                )
            }

            return formatLanguageResult(
                intro: "Opposites for \(term)",
                items: matches,
                mode: mode,
                roastMode: roastMode
            )
        }

        if let term = extractSuffix(in: normalized, markers: Self.rhymeMarkers) {
            let matches = rhymes(for: term)
            guard !matches.isEmpty else {
                return formatLanguageFallback(
                    "I couldn't find a clean rhyme set for \(term).",
                    mode: mode,
                    roastMode: roastMode
                )
            }

            return formatLanguageResult(
                intro: "Rhymes with \(term)",
                items: matches,
                mode: mode,
                roastMode: roastMode
            )
        }

        if let term = extractSuffix(in: normalized, markers: Self.soundLikeMarkers) {
            let matches = soundsLike(term)
            guard !matches.isEmpty else {
                return formatLanguageFallback(
                    "I couldn't find a clean sounds-like list for \(term).",
                    mode: mode,
                    roastMode: roastMode
                )
            }

            return formatLanguageResult(
                intro: "Sounds like \(term)",
                items: matches,
                mode: mode,
                roastMode: roastMode
            )
        }

        return nil
    }

    private func localReflectiveResponse(
        for message: String,
        dataContext: BitBuddyDataContext,
        roastMode: Bool
    ) -> String? {
        let normalized = normalizedQuery(message)
        let currentSection = dataContext.currentPage ?? dataContext.activeSection

        if isGreeting(normalized) {
            if roastMode {
                return "I'm here. Say the thing plainly and I'll help you sharpen it."
            }
            return "I'm here. Bring me the joke, the idea, or the mess around it and we'll work it out."
        }

        if normalized.contains("how are you") || normalized.contains("how's it going") {
            if roastMode {
                return "Mean, focused, and fully available. Send me the line, target, or premise and I'll make it sharper."
            }
            return "Sharp enough to help. Send me a joke, premise, or feature question and I'll give you a straight answer."
        }

        if normalized.contains("who are you") || normalized.contains("what are you") {
            if roastMode {
                return "I'm BitBuddy in roast mode. Part writing partner, part heckler with standards."
            }
            return "I'm BitBuddy, your built-in writing partner for jokes, roasts, and rough ideas."
        }

        if let personalAnswer = personalQuestionResponse(for: normalized, roastMode: roastMode) {
            return personalAnswer
        }

        if normalized.contains("what can you do") || normalized == "help" || normalized.contains("help me") {
            return helpResponse(for: currentSection, roastMode: roastMode)
        }

        if normalized.contains("thank you") || normalized == "thanks" || normalized == "thx" {
            if roastMode {
                return "Good. Now keep going."
            }
            return "Anytime. Keep it coming."
        }

        if normalized.contains("i am stuck") || normalized.contains("i'm stuck") || normalized.contains("stuck on") {
            if roastMode {
                return "Start with the meanest true observation, then make the wording shorter. If you paste the line, I'll sharpen it."
            }
            return "Start by separating the setup, the turn, and the final word. The fastest fix is usually cutting setup until the punch lands sooner."
        }

        if normalized.contains("give me an idea") || normalized.contains("brainstorm with me") {
            if roastMode {
                return "Pick a target and one specific flaw: status, habit, outfit, voice, job, or delusion. The more specific the flaw, the easier the roast."
            }
            return "Start with an annoyance, image, or contradiction. Turn it into: 'I thought X was Y, but it is actually Z.'"
        }

        if normalized.contains("what do you think") {
            if roastMode {
                return "The honest version is usually meaner and funnier. Cut the polite framing and land on the most specific flaw."
            }
            return "The truthful version is probably stronger than the polished version. Cut anything that explains the joke before the turn."
        }

        return nil
    }

    private func formatLanguageResult(
        intro: String,
        items: [String],
        mode: ConversationMode,
        roastMode: Bool
    ) -> String {
        let list = items.joined(separator: ", ")

        switch mode {
        case .simpleFactual:
            return "\(intro): \(list)."
        case .creativeFactual:
            if roastMode {
                return "\(intro): \(list). Enough ammo to hurt somebody's feelings professionally."
            }
            return "\(intro): \(list). Solid little word rack."
        case .reflective, .appAction:
            return "\(intro): \(list)."
        }
    }

    private func formatLanguageFallback(
        _ base: String,
        mode: ConversationMode,
        roastMode: Bool
    ) -> String {
        switch mode {
        case .creativeFactual:
            if roastMode {
                return "\(base) That's irritating, but not as irritating as a weak tag."
            }
            return "\(base) Try a nearby phrasing and I can take another swing."
        case .simpleFactual, .reflective, .appAction:
            return base
        }
    }

    private func normalizedQuery(_ message: String) -> String {
        message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isGreeting(_ query: String) -> Bool {
        let greetings = ["hi", "hey", "hello", "yo", "sup", "what's up", "whats up"]
        return greetings.contains(query)
    }

    private func helpResponse(for section: BitBuddySection?, roastMode: Bool) -> String {
        let location = section?.displayName ?? "this page"

        if roastMode {
            return "On \(location), I can help punch up lines, find setups, sort backups, build openers, or answer quick word questions. Say exactly what you need."
        }

        return "On \(location), I can help analyze material, tighten wording, brainstorm premises, explain features, or answer quick language questions. Tell me what you're trying to solve."
    }

    private func extractSuffix(in query: String, markers: [String]) -> String? {
        for marker in markers {
            guard let range = query.range(of: marker) else { continue }
            let suffix = String(query[range.upperBound...])
            let cleaned = cleanedLookupTerm(suffix)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    private func cleanedLookupTerm(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,:;!?()[]{}"))

        let words = trimmed
            .split(whereSeparator: \.isWhitespace)
            .prefix(3)
            .map(String.init)

        return words.joined(separator: " ")
    }

    private func wordsStarting(with prefix: String) -> [String] {
        let normalizedPrefix = prefix.replacingOccurrences(of: " ", with: "")
        guard !normalizedPrefix.isEmpty else { return [] }

        let banks = Self.lexicalWordBank
            + BitBuddyResources.topics
            + BitBuddyResources.fillerWords
            + BitBuddyResources.roastTechniques
            + BitBuddyResources.jokeProTechniques
            + BitBuddyResources.vocabExaggeration
            + BitBuddyResources.vocabPunchyAdjectives
            + BitBuddyResources.vocabNYCFlavored
            + BitBuddyResources.vocabSelfDeprecating
            + Array(BitBuddyResources.synonyms.keys)
            + BitBuddyResources.synonyms.values.flatMap { $0 }
            + Array(BitBuddyResources.vocabObservationalUpgrades.keys)
            + Array(BitBuddyResources.vocabObservationalUpgrades.values)

        var seen = Set<String>()
        var matches: [String] = []

        for token in banks.flatMap(tokenizeWords(from:)) {
            let lower = token.lowercased()
            guard lower.hasPrefix(normalizedPrefix) else { continue }
            guard seen.insert(lower).inserted else { continue }
            matches.append(token)
        }

        return Array(matches.prefix(8))
    }

    private func synonyms(for term: String) -> [String] {
        let normalized = term.lowercased()
        if let direct = BitBuddyResources.synonyms[normalized] {
            return direct
        }

        if let upgraded = BitBuddyResources.vocabObservationalUpgrades[normalized] {
            return [upgraded]
        }

        if let reverse = BitBuddyResources.synonyms.first(where: { _, values in
            values.contains(where: { $0.lowercased() == normalized })
        }) {
            return [reverse.key] + reverse.value.filter { $0.lowercased() != normalized }
        }

        return []
    }

    private func antonyms(for term: String) -> [String] {
        Self.antonyms[term.lowercased()] ?? []
    }

    private func rhymes(for term: String) -> [String] {
        let normalized = term.lowercased()
        let custom = customRhymes(for: normalized)
        if !custom.isEmpty {
            return custom
        }

        let endingLength = min(max(normalized.count >= 4 ? 3 : 2, 2), normalized.count)
        let ending = String(normalized.suffix(endingLength))

        let matches = Set(
            Self.lexicalWordBank.filter {
                let candidate = $0.lowercased()
                return candidate != normalized && candidate.hasSuffix(ending)
            }
        )

        return Array(matches).sorted().prefix(8).map { $0 }
    }

    private func soundsLike(_ term: String) -> [String] {
        let normalized = term.lowercased()
        let custom = customSoundsLike(for: normalized)
        if !custom.isEmpty {
            return custom
        }

        let matches = rhymes(for: normalized)
        if !matches.isEmpty {
            return matches
        }

        let prefixLength = min(2, normalized.count)
        let prefix = String(normalized.prefix(prefixLength))
        return Array(
            Set(Self.lexicalWordBank.filter {
                let candidate = $0.lowercased()
                return candidate != normalized && candidate.hasPrefix(prefix)
            })
        )
        .sorted()
        .prefix(8)
        .map { $0 }
    }

    private func customRhymes(for term: String) -> [String] {
        switch term {
        case "funny":
            return ["money", "sunny", "bunny", "honey"]
        case "late":
            return ["date", "fate", "gate", "great", "wait"]
        case "bright":
            return ["light", "night", "right", "tight"]
        case "smart":
            return ["art", "cart", "dart", "heart", "part"]
        case "roast":
            return ["boast", "coast", "ghost", "most", "post"]
        default:
            return []
        }
    }

    private func customSoundsLike(for term: String) -> [String] {
        switch term {
        case "ant":
            return ["aunt", "can't", "chant", "grant", "pant"]
        case "hype":
            return ["pipe", "ripe", "stripe", "type", "wipe"]
        case "smart":
            return ["smarts", "start", "heart", "chart"]
        case "late":
            return ["eight", "fate", "gate", "wait"]
        case "grind":
            return ["ground", "mind", "rind", "signed"]
        default:
            return []
        }
    }

    private func isPersonalQuestion(_ normalized: String) -> Bool {
        let personalMarkers = [
            "your name", "your age", "how old are you", "how old r u",
            "who are you", "what are you", "are you real", "are you a bot",
            "are you a robot", "are you human", "are you alive",
            "are you sentient", "do you have feelings", "can you feel",
            "where are you from", "where do you live", "where are you",
            "who made you", "who built you", "who created you",
            "tell me about yourself", "describe yourself", "introduce yourself",
            "what do you do", "what can you do", "do you like",
            "what is your favorite", "what's your favorite", "whats your favorite",
            "what is your favourite", "what's your favourite",
        ]
        return personalMarkers.contains { normalized.contains($0) }
    }

    private func tokenizeWords(from phrase: String) -> [String] {
        phrase
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
    }

    private func generateWithCurrentLLM(
        prompt: String,
        instructions: String,
        session: BitBuddySessionSnapshot
    ) async throws -> String? {
        if AppleIntelligenceBitBuddyService.shared.isAvailable {
            return try await AppleIntelligenceBitBuddyService.shared.generateResponse(
                userPrompt: prompt,
                systemInstructions: instructions
            )
        }

        if MLXBitBuddyService.shared.isAvailable {
            return try await MLXBitBuddyService.shared.generateResponse(
                userPrompt: prompt,
                conversationId: session.conversationId,
                systemInstructions: instructions
            )
        }

        if HuggingFaceTransformersBitBuddyService.shared.isAvailable {
            return try await HuggingFaceTransformersBitBuddyService.shared.generateResponse(
                userPrompt: prompt,
                session: session,
                systemInstructions: instructions
            )
        }

        if OpenAIBitBuddyService.shared.isAvailable {
            return try await OpenAIBitBuddyService.shared.generateResponse(
                userPrompt: prompt,
                session: session,
                systemInstructions: instructions
            )
        }

        return nil
    }

    private func buildPrompt(
        message: String,
        dataContext: BitBuddyDataContext,
        searchResult: String?
    ) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []

        sections.append("User: \(dataContext.userName)")
        sections.append("Current date: \(CurrentFacts.currentDateString)")
        sections.append("For current date, year, today, or time-sensitive questions, use the current date above and do not rely on model memory.")

        if let section = dataContext.currentPage ?? dataContext.activeSection {
            sections.append("Current app section: \(section.displayName)")
            sections.append("Stay inside this page or mode unless the user explicitly asks for broader app or library context.")
        }

        if let focusedJoke = dataContext.focusedJoke {
            let content = focusedJoke.content.replacingOccurrences(of: "\n", with: " ")
            sections.append("Focused joke:\nTitle: \(focusedJoke.title)\nContent: \(content)")
        }

        if BitBuddyResources.shouldIncludeRecentJokes(for: trimmedMessage), !dataContext.recentJokes.isEmpty {
            let recent = dataContext.recentJokes.prefix(5).map { joke in
                let content = joke.content.replacingOccurrences(of: "\n", with: " ")
                return "• \(joke.title): \(content.prefix(140))"
            }.joined(separator: "\n")
            sections.append("Recent jokes:\n\(recent)")
        }

        if let searchResult, !searchResult.isEmpty {
            sections.append(
                """
                Private search tool result:
                \(searchResult)

                Use the tool result if it helps. Keep capabilities and response structure identical to the system instruction.
                """
            )
        }

        sections.append("IMPORTANT: Reply in 1–2 sentences max. No preamble, no recap. Just answer.")
        sections.append(trimmedMessage)
        return sections.joined(separator: "\n\n")
    }
}
