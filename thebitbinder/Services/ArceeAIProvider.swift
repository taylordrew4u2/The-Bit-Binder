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
//  ⚠️  Free models rotate. If this 404s, check openrouter.ai/models for
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

    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .arceeAI) else {
            throw AIProviderError.keyNotConfigured(.arceeAI)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)

        let requestBody: [String: Any] = [
            "model": AIProviderType.arceeAI.defaultModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 16384
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("thebitbinder", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                let retryAfter = (httpResponse.value(forHTTPHeaderField: "retry-after")
                    ?? httpResponse.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.arceeAI, retryAfterSeconds: retryAfter)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.arceeAI, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // OpenRouter uses OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.arceeAI, "Unexpected response format: \(raw.prefix(300))")
        }

        // Many free OpenRouter models use "reasoning" mode — the actual text
        // lands in `reasoning` instead of `content`. Fall back gracefully.
        let content: String
        if let c = message["content"] as? String, !c.isEmpty {
            content = c
        } else if let r = message["reasoning"] as? String, !r.isEmpty {
            print("⚠️ [Arcee] Model returned reasoning instead of content — extracting from reasoning field")
            content = r
        } else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.arceeAI, "Empty response from model: \(raw.prefix(300))")
        }

        let finishReason = firstChoice["finish_reason"] as? String ?? ""
        if finishReason == "length" {
            print("⚠️ [Arcee] Response truncated (finish_reason=length) — attempting partial JSON repair")
        }

        return try JokeExtractionPrompt.parseResponse(content, provider: .arceeAI)
    }
}
