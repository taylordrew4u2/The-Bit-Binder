//
//  OpenRouterProvider.swift
//  thebitbinder
//
//  OpenRouter provider — routes to any model available on openrouter.ai
//  using the OpenAI-compatible Chat Completions API.
//  No external SDK required.
//

import Foundation

/// OpenRouter provider — access hundreds of models (including free ones)
/// through a single OpenAI-compatible endpoint.
final class OpenRouterProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .openRouter

    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"

    private let systemPrompt = """
    You are a JSON API. You output ONLY a valid JSON array — no markdown, no prose, no explanation.
    Every response must start with [ and end with ]. Never wrap output in code fences.
    """

    /// The model to use. Can be overridden via UserDefaults (e.g. from a settings screen).
    private static let modelDefaultsKey = "openrouter_model"
    private var model: String {
        UserDefaults.standard.string(forKey: Self.modelDefaultsKey)
            ?? AIProviderType.openRouter.defaultModel
    }

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .openRouter) != nil
    }

    func extractJokes(from text: String) async throws -> [AIExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .openRouter) else {
            throw AIProviderError.keyNotConfigured(.openRouter)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)
        let modelsToTry = [model] + AIProviderType.openRouter.fallbackModels.filter { $0 != model }

        var lastError: Error?
        for m in modelsToTry {
            do {
                print(" [OpenRouter] Trying model: \(m)")
                return try await callOpenRouter(apiKey: apiKey, model: m, prompt: prompt)
            } catch let error as AIProviderError {
                switch error {
                case .apiError(_, let msg) where msg.contains("HTTP 404") || msg.contains("HTTP 400"):
                    print(" [OpenRouter] Model \(m) unavailable, trying next…")
                    lastError = error
                    continue
                case .rateLimited:
                    throw error
                default:
                    lastError = error
                    continue
                }
            }
        }
        throw lastError ?? AIProviderError.apiError(.openRouter, "All free models unavailable")
    }

    private func callOpenRouter(apiKey: String, model: String, prompt: String) async throws -> [AIExtractedJoke] {
        try await OpenAICompatibleChatClient.callChatCompletion(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            provider: .openRouter,
            extraHeaders: [
                .init(name: "HTTP-Referer", value: "https://openrouter.ai"),
                .init(name: "X-Title", value: "thebitbinder")
            ]
        )
    }
}
