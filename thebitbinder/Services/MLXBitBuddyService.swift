import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

/// On-device LLM backend for BitBuddy powered by MLX and Phi-3 Mini Instruct.
final class MLXBitBuddyService: BitBuddyBackend {
    static let shared = MLXBitBuddyService()

    private init() {}

    var backendName: String {
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        "Phi-3 Mini (On-Device)"
#else
        "Phi-3 Mini (Unavailable)"
#endif
    }

    var isAvailable: Bool {
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        true
#else
        false
#endif
    }

    var supportsStreaming: Bool { false }

    func preload() async {
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        _ = try? await MLXBitBuddyRuntime.shared.prepareModelIfNeeded(conversationId: "preload")
#endif
    }

    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Give me a prompt and I can help with jokes, rewrites, brainstorming, and general chat."
        }

        let fullPrompt = buildPrompt(message: trimmed, session: session, dataContext: dataContext)

        do {
            try await MLXBitBuddyRuntime.shared.prepareModelIfNeeded(conversationId: session.conversationId)
            let output = try await MLXBitBuddyRuntime.shared.generate(fullPrompt, conversationId: session.conversationId)
            let cleaned = sanitizeModelOutput(output)
            if cleaned.isEmpty {
                throw BitBuddyBackendError.generationFailed
            }
            return cleaned
        } catch {
            throw BitBuddyBackendError.generationFailed
        }
#else
        throw BitBuddyBackendError.unavailable
#endif
    }

    private func buildPrompt(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) -> String {
        let systemPrompt = """
        You are BitBuddy, an on-device assistant for comedians.
        Be practical, funny when useful, and concise.
        Help with joke writing, punch-up, premise generation, set structure, and general conversation.
        Never claim you saved, edited, deleted, imported, exported, synced, or migrated data.
        If the user asks for an app action, provide guidance text only.
        """

        let recentTurns = session.turns.suffix(6)
        let history = recentTurns
            .map { turn in
                let role: String
                switch turn.role {
                case .system: role = "system"
                case .user: role = "user"
                case .assistant: role = "assistant"
                }
                return "\(role): \(turn.text)"
            }
            .joined(separator: "\n")

        let jokesContext: String
        if dataContext.recentJokes.isEmpty {
            jokesContext = "none"
        } else {
            jokesContext = dataContext.recentJokes.prefix(5).map { joke in
                let preview = joke.content.replacingOccurrences(of: "\n", with: " ")
                return "- \(joke.title): \(preview.prefix(140))"
            }.joined(separator: "\n")
        }

        let routedSection = dataContext.activeSection?.displayName ?? "None"

        return """
        [INST] <<SYS>>
        \(systemPrompt)
        <</SYS>>

        UserName: \(dataContext.userName)
        ActiveSection: \(routedSection)
        RecentJokes:
        \(jokesContext)

        Conversation:
        \(history)

        User: \(message)
        [/INST]
        """
    }

    private func sanitizeModelOutput(_ output: String) -> String {
        let cleaned = output
            .replacingOccurrences(of: "</s>", with: "")
            .replacingOccurrences(of: "[INST]", with: "")
            .replacingOccurrences(of: "[/INST]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}

#if canImport(MLXLLM) && canImport(MLXLMCommon)
private actor MLXBitBuddyRuntime {
    static let shared = MLXBitBuddyRuntime()

    private static let phi3MiniConfig = ModelConfiguration(
        id: "mlx-community/Phi-3-mini-4k-instruct-4bit",
        defaultPrompt: "Help me improve this joke.",
        extraEOSTokens: ["<|end|>"]
    )

    private var chatSession: ChatSession?
    private var activeConversationId: String?

    func prepareModelIfNeeded(conversationId: String) async throws {
        if chatSession == nil {
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: Self.phi3MiniConfig
            )
            chatSession = ChatSession(
                container,
                instructions: "You are BitBuddy, an on-device assistant for comedians. Be practical, funny when useful, and concise."
            )
        }

        if activeConversationId != conversationId {
            chatSession?.clear()
            activeConversationId = conversationId
        }
    }

    func generate(_ prompt: String, conversationId: String) async throws -> String {
        try await prepareModelIfNeeded(conversationId: conversationId)
        guard let chatSession else {
            throw BitBuddyBackendError.generationFailed
        }
        return try await chatSession.respond(to: prompt)
    }

    func reset() {
        chatSession?.clear()
        activeConversationId = nil
    }
}
#endif
