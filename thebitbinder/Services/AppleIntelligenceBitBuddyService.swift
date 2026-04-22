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
            return SystemLanguageModel.default.isAvailable
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
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "Give me a prompt and I can help with jokes, rewrites, brainstorming, and general chat."
            }

            let userPrompt = buildPrompt(message: trimmed, dataContext: dataContext)

            let lmSession = LanguageModelSession(instructions: systemInstructions)
            let response = try await lmSession.respond(to: userPrompt)
            let output = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !output.isEmpty else {
                throw BitBuddyBackendError.generationFailed
            }
            return output
        }
#endif
        throw BitBuddyBackendError.unavailable
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
}
