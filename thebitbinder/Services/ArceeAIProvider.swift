//
//  ArceeAIProvider.swift
//  thebitbinder
//
//  "Arcee AI" provider slot — uses Mistral Small 3.1 24B (free) via OpenRouter's
//  OpenAI-compatible Chat Completions API.
//
//  The slot is named "Arcee AI" in the UI because users previously configured
//  an Arcee key. The underlying model is `mistralai/mistral-small-3.1-24b-instruct:free`
//  (128k context, strong JSON instruction following).
//  The same OpenRouter API key is used — no re-auth required.
//
//    Free models rotate. If this 404s, check openrouter.ai/models for
//  current free options and update AIProviderType.defaultModel.
//
//  No external SDK required.
//

import Foundation

/// "Arcee AI" slot — currently backed by Mistral Nemo via OpenRouter.
final class ArceeAIProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .arceeAI

    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"

    private let systemPrompt = """
    You are a JSON API. You output ONLY a valid JSON array — no markdown, no prose, no explanation.
    Every response must start with [ and end with ]. Never wrap output in code fences.
    """

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .arceeAI) != nil
    }

    func extractJokes(from text: String) async throws -> [AIExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .arceeAI) else {
            throw AIProviderError.keyNotConfigured(.arceeAI)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)
        let modelsToTry = [AIProviderType.arceeAI.defaultModel] + AIProviderType.arceeAI.fallbackModels

        var lastError: Error?
        for model in modelsToTry {
            do {
                print(" [Arcee] Trying model: \(model)")
                return try await callOpenRouter(apiKey: apiKey, model: model, prompt: prompt)
            } catch let error as AIProviderError {
                switch error {
                case .apiError(_, let msg) where msg.contains("HTTP 404") || msg.contains("HTTP 400"):
                    print(" [Arcee] Model \(model) unavailable, trying next…")
                    lastError = error
                    continue
                case .rateLimited:
                    throw error // don't retry, let manager fall back to next provider
                default:
                    lastError = error
                    continue
                }
            }
        }
        throw lastError ?? AIProviderError.apiError(.arceeAI, "All free models unavailable")
    }

    private func callOpenRouter(apiKey: String, model: String, prompt: String) async throws -> [AIExtractedJoke] {
        try await OpenAICompatibleChatClient.callChatCompletion(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            provider: .arceeAI,
            extraHeaders: [.init(name: "X-Title", value: "thebitbinder")]
        )
    }
}
