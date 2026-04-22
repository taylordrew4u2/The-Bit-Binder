import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

/// On-device LLM backend for BitBuddy powered by MLX and Qwen 2.5 3B.
final class MLXBitBuddyService: BitBuddyBackend {
    static let shared = MLXBitBuddyService()

    private init() {}

    var backendName: String {
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        "Qwen 2.5 3B (On-Device)"
#else
        "Qwen 2.5 3B (Unavailable)"
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
        _ = try? await MLXSharedRuntime.shared.prepareModelIfNeeded()
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

        let userPrompt = buildPrompt(
            message: trimmed,
            dataContext: dataContext
        )

        do {
            let output = try await MLXSharedRuntime.shared.generateChatResponse(
                userPrompt,
                conversationId: session.conversationId,
                instructions: systemInstructions
            )
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

    // MARK: - Prompt Building

    private var systemInstructions: String {
        """
        You are BitBuddy, an on-device assistant for comedians. \
        Be practical, funny when useful, and concise. \
        Help with joke writing, punch-up, premise generation, set structure, and general conversation. \
        Never claim you saved, edited, deleted, imported, exported, synced, or migrated data. \
        If the user asks for an app action, provide guidance text only.
        """
    }

    /// Builds the user-facing prompt with context metadata.
    /// ChatSession handles chat template formatting automatically.
    private func buildPrompt(
        message: String,
        dataContext: BitBuddyDataContext
    ) -> String {
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
        UserName: \(dataContext.userName)
        ActiveSection: \(routedSection)
        RecentJokes:
        \(jokesContext)

        \(message)
        """
    }

    // MARK: - Output Sanitization

    private func sanitizeModelOutput(_ output: String) -> String {
        output
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "<|endoftext|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
