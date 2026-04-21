//
//  AIJokeExtractionManager.swift
//  thebitbinder
//
//  Coordinates GagGrabber's on-device extraction providers.
//  The Apple Foundation Model runs first when available (iOS 26+); otherwise
//  the NLEmbedding segmenter handles the document. Both run entirely offline.
//
//  HARDWIRED RESTRICTION: Extraction is only for the import pipeline.
//  Callers must supply an `AIExtractionToken`. BitBuddy and other interactive
//  features must never instantiate one.
//

import Foundation

// MARK: - Caller Restriction Token

struct AIExtractionToken {
    fileprivate(set) var caller: String
    init(caller: String) { self.caller = caller }
}

/// Manages the on-device extraction providers GagGrabber uses.
final class AIJokeExtractionManager {

    static let shared = AIJokeExtractionManager()

    // MARK: - Allowed callers

    private static let allowedCallers: Set<String> = [
        "ImportPipelineCoordinator",
        "HybridGagGrabber"
    ]

    private func assertAuthorised(_ token: AIExtractionToken) {
        if !Self.allowedCallers.contains(token.caller) {
            assertionFailure(
                " [Extraction] BLOCKED: '\(token.caller)' is not allowed to use extraction. "
                + "Allowed: \(Self.allowedCallers)"
            )
            print(" [Extraction] BLOCKED: Unauthorised caller '\(token.caller)'")
        }
    }

    // MARK: - Providers

    /// Apple's Foundation Model runs first when available — it understands
    /// the detailed per-entry questions (jokeText / confidence / humorMechanism
    /// / title) via guided generation. The embedding segmenter is the fallback
    /// on older devices.
    private let providerOrder: [AIProviderType] = [.appleOnDevice, .embeddingLocal]

    private let providers: [AIProviderType: AIJokeExtractionProvider] = [
        .appleOnDevice:  AppleOnDeviceJokeExtractionProvider(),
        .embeddingLocal: EmbeddingSegmenterProvider()
    ]

    private init() {}

    // MARK: - Status

    /// Providers that report themselves ready right now.
    var availableProviders: [AIProviderType] {
        providerOrder.filter { providers[$0]?.isConfigured() ?? false }
    }

    /// Whether a provider is ready on this device.
    func isProviderReady(_ type: AIProviderType) -> Bool {
        providers[type]?.isConfigured() ?? false
    }

    // MARK: - Extraction

    /// Try each on-device provider in order. If both fail, throw
    /// `AIExtractionFailedError` — the pipeline must surface the failure.
    func extractJokes(from text: String, hints: ExtractionHints = .unspecified, token: AIExtractionToken) async throws -> (jokes: [AIExtractedJoke], provider: AIProviderType) {
        assertAuthorised(token)

        print(" [Extraction] Starting with \(text.count) chars")
        print(" [Extraction] Providers: \(providerOrder.map(\.displayName).joined(separator: " → "))")

        var errors: [AIProviderType: Error] = [:]

        for providerType in providerOrder {
            guard let provider = providers[providerType], provider.isConfigured() else {
                print(" [Extraction] Skipping \(providerType.displayName) (unavailable on this device)")
                continue
            }

            do {
                print(" [Extraction] Trying \(providerType.displayName)…")
                let jokes = try await provider.extractJokes(from: text, hints: hints)
                print(" [Extraction] \(providerType.displayName) returned \(jokes.count) fragment(s)")
                return (jokes, providerType)
            } catch {
                print(" [Extraction] \(providerType.displayName) error: \(error.localizedDescription)")
                errors[providerType] = error
            }
        }

        print(" [Extraction] All on-device providers failed")
        throw AIExtractionFailedError(
            reason: "GagGrabber couldn't read this document — try a different file.",
            underlyingErrors: errors
        )
    }

    /// Convenience wrapper used by `ImportPipelineCoordinator`.
    func extractJokesForPipeline(from text: String, hints: ExtractionHints = .unspecified, token: AIExtractionToken) async throws -> (jokes: [AIExtractedJoke], providerUsed: String) {
        let result = try await extractJokes(from: text, hints: hints, token: token)
        return (result.jokes, result.provider.displayName)
    }

    // MARK: - Status Messages

    var statusMessage: String {
        availableProviders.isEmpty
            ? "GagGrabber is warming up — try again in a moment."
            : "GagGrabber is ready!"
    }
}

// MARK: - Failure

struct AIExtractionFailedError: LocalizedError {
    let reason: String
    let underlyingErrors: [AIProviderType: Error]

    var errorDescription: String? { reason }

    var detailedDescription: String {
        guard !underlyingErrors.isEmpty else { return reason }
        let details = underlyingErrors
            .map { "  • \($0.key.displayName): \($0.value.localizedDescription)" }
            .joined(separator: "\n")
        return "\(reason)\n\nGagGrabber details:\n\(details)"
    }
}
