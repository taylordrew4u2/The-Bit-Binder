//
//  OpenAICompatibleChatClient.swift
//  thebitbinder
//
//  Shared request/response handling for OpenAI-compatible Chat Completions
//  endpoints (OpenRouter, Arcee slot, and any future "OpenAI-compat" backends).
//
//  OpenAIProvider intentionally does NOT use this — it needs `response_format`
//  with a JSON schema, which OpenRouter's free models don't support reliably.
//

import Foundation

/// Calls any OpenAI-compatible `/v1/chat/completions` endpoint and returns the
/// extracted jokes. Handles the quirks shared by OpenRouter-backed providers:
/// 429/402 rate-limit mapping, inline error bodies returned with HTTP 200,
/// and the `reasoning`-vs-`content` fallback for models in reasoning mode.
enum OpenAICompatibleChatClient {

    struct ExtraHeader {
        let name: String
        let value: String
    }

    static func callChatCompletion(
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        provider: AIProviderType,
        extraHeaders: [ExtraHeader] = [],
        rateLimitRetryAfterFallbackSeconds: Int = 3600,
        temperature: Double = 0.3,
        maxTokens: Int = 16384,
        timeout: TimeInterval = 120
    ) async throws -> [AIExtractedJoke] {

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        guard let endpointURL = URL(string: baseURL) else {
            throw AIProviderError.apiError(provider, "Invalid endpoint URL: \(baseURL)")
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for header in extraHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 || httpResponse.statusCode == 402 {
                let retryAfter = (httpResponse.value(forHTTPHeaderField: "retry-after")
                    ?? httpResponse.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(provider, retryAfterSeconds: retryAfter ?? rateLimitRetryAfterFallbackSeconds)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(provider, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(provider, "Unexpected response format: \(raw.prefix(300))")
        }

        // Some endpoints return HTTP 200 + inline error body on quota exhaustion
        if let error = json["error"] as? [String: Any], let errMsg = error["message"] as? String {
            let lower = errMsg.lowercased()
            if lower.contains("credit") || lower.contains("limit") || lower.contains("quota")
                || lower.contains("budget") || lower.contains("free") {
                throw AIProviderError.rateLimited(provider, retryAfterSeconds: rateLimitRetryAfterFallbackSeconds)
            }
            throw AIProviderError.apiError(provider, errMsg)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(provider, "Unexpected response format: \(raw.prefix(300))")
        }

        // Fall back from `content` to `reasoning` — several free OpenRouter
        // models only populate the reasoning field.
        let content: String
        if let c = message["content"] as? String, !c.isEmpty {
            content = c
        } else if let r = message["reasoning"] as? String, !r.isEmpty {
            print(" [\(provider.displayName)] Model returned reasoning instead of content — extracting from reasoning field")
            content = r
        } else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(provider, "Empty response from model: \(raw.prefix(300))")
        }

        let finishReason = firstChoice["finish_reason"] as? String ?? ""
        if finishReason == "length" {
            print(" [\(provider.displayName)] Response truncated (finish_reason=length) — attempting partial JSON repair")
        }

        return try JokeExtractionPrompt.parseResponse(content, provider: provider)
    }
}
