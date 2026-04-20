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
            throw AIProviderError.apiError(.openRouter, "Invalid OpenRouter endpoint URL: \(baseURL)")
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://openrouter.ai", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("thebitbinder", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 || httpResponse.statusCode == 402 {
                let retryAfter = (httpResponse.value(forHTTPHeaderField: "retry-after")
                    ?? httpResponse.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.openRouter, retryAfterSeconds: retryAfter ?? 3600)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.openRouter, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // OpenRouter uses the OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.openRouter, "Unexpected response format: \(raw.prefix(300))")
        }

        // Check for inline error (credit/limit exhaustion can come as 200 + error body)
        if let error = json["error"] as? [String: Any], let errMsg = error["message"] as? String {
            let lower = errMsg.lowercased()
            if lower.contains("credit") || lower.contains("limit") || lower.contains("quota") || lower.contains("budget") || lower.contains("free") {
                throw AIProviderError.rateLimited(.openRouter, retryAfterSeconds: 3600)
            }
            throw AIProviderError.apiError(.openRouter, errMsg)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.openRouter, "Unexpected response format: \(raw.prefix(300))")
        }

        // openrouter/free auto-routes to any available model.  Some use
        // "reasoning" mode where the real output is in `reasoning`, not `content`.
        let content: String
        if let c = message["content"] as? String, !c.isEmpty {
            content = c
        } else if let r = message["reasoning"] as? String, !r.isEmpty {
            print(" [OpenRouter] Model returned reasoning instead of content — extracting from reasoning field")
            content = r
        } else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.openRouter, "Empty response from model: \(raw.prefix(300))")
        }

        let finishReason = firstChoice["finish_reason"] as? String ?? ""
        if finishReason == "length" {
            print(" [OpenRouter] Response truncated (finish_reason=length) — attempting partial JSON repair")
        }

        return try JokeExtractionPrompt.parseResponse(content, provider: .openRouter)
    }
}
