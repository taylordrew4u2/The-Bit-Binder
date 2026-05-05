import Foundation

final class SocraticGuideBackend: BitBuddyBackend {
    static let shared = SocraticGuideBackend()

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
            ? "You're circling it. What's the one part you're scared to say plainly?"
            : "That feels like a bit pacing backstage before it hits the light. What part of it feels most true to you?"
    }

    private func generateFactualResponse(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext,
        mode: ConversationMode,
        roastMode: Bool
    ) async throws -> String {
        let searchResult = try await PrivateSearchService.search(message)
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

        let fallbackFact = searchResult ?? "I couldn't find a clean answer for that."
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

        sections.append("Keep the reply brief unless the user explicitly asks for more detail.")
        sections.append(trimmedMessage)
        return sections.joined(separator: "\n\n")
    }
}
