//
//  AppleIntelligenceBitBuddyService.swift
//  thebitbinder
//
//  On-device Apple Intelligence backend for BitBuddy chat.
//  Uses the FoundationModels framework (iOS 26+) — no downloads needed.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleIntelligenceBitBuddyService: BitBuddyBackend {
    static let shared = AppleIntelligenceBitBuddyService()

    private init() {}

    var backendName: String { "Apple Intelligence (On-Device)" }

    var isAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel(guardrails: .permissiveContentTransformations).isAvailable
        }
#endif
        return false
    }

    var supportsStreaming: Bool { false }

    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Give me a prompt and I can help with jokes, rewrites, brainstorming, and general chat."
        }

        let userPrompt = buildPrompt(message: trimmed, dataContext: dataContext)
        return try await generateResponse(
            userPrompt: userPrompt,
            systemInstructions: systemInstructions
        )
    }

    // MARK: - Refusal Detection

    private static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let patterns = [
            "i can't help with",
            "i'm not able to",
            "i cannot help",
            "i'm unable to",
            "sorry, i can't",
            "i can not help",
            "as an ai",
            "i don't think i can help"
        ]
        return patterns.contains { lower.contains($0) }
    }

    // MARK: - Prompt Building

    private var systemInstructions: String {
        BitBuddyResources.llmSystemInstructions
    }

    private func buildPrompt(
        message: String,
        dataContext: BitBuddyDataContext
    ) -> String {
        BitBuddyResources.buildLLMPrompt(message: message, dataContext: dataContext)
    }

    func generateResponse(
        userPrompt: String,
        systemInstructions: String
    ) async throws -> String {
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            let lmSession = LanguageModelSession(model: model, instructions: systemInstructions)
            let response = try await lmSession.respond(to: userPrompt)
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !output.isEmpty, !Self.isRefusal(output) else {
                throw BitBuddyBackendError.generationFailed
            }
            return output
        }
#endif
        throw BitBuddyBackendError.unavailable
    }
}
