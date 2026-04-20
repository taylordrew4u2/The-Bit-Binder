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
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 16384
        ]

        guard let endpointURL = URL(string: baseURL) else {
            throw AIProviderError.apiError(.arceeAI, "Invalid Arcee endpoint URL: \(baseURL)")
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("thebitbinder", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 || httpResponse.statusCode == 402 {
                let retryAfter = (httpResponse.value(forHTTPHeaderField: "retry-after")
                    ?? httpResponse.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.arceeAI, retryAfterSeconds: retryAfter ?? 3600)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.arceeAI, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // OpenRouter uses OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.arceeAI, "Unexpected response format: \(raw.prefix(300))")
        }

        // Check for inline error (OpenRouter returns 200 with error body for some limit cases)
        if let error = json["error"] as? [String: Any], let errMsg = error["message"] as? String {
            let lower = errMsg.lowercased()
            if lower.contains("credit") || lower.contains("limit") || lower.contains("quota") || lower.contains("budget") || lower.contains("free") {
                throw AIProviderError.rateLimited(.arceeAI, retryAfterSeconds: 3600)
            }
            throw AIProviderError.apiError(.arceeAI, errMsg)
        }

        guard let choices = json["choices"] as? [[String: Any]],
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
            print(" [Arcee] Model returned reasoning instead of content — extracting from reasoning field")
            content = r
        } else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.arceeAI, "Empty response from model: \(raw.prefix(300))")
        }

        let finishReason = firstChoice["finish_reason"] as? String ?? ""
        if finishReason == "length" {
            print(" [Arcee] Response truncated (finish_reason=length) — attempting partial JSON repair")
        }

        return try JokeExtractionPrompt.parseResponse(content, provider: .arceeAI)
    }
}
