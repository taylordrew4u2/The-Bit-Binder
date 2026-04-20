//
//  OpenAIProvider.swift
//  thebitbinder
//
//  OpenAI provider — uses the Chat Completions REST API via URLSession.
//  No external SDK required.
//
//  response_format is set to `json_schema` (structured outputs) so the model
//  returns a valid JSON object wrapping the jokes array.  The schema is
//  intentionally lenient (additionalProperties: true on each joke item) so
//  we don't break if the model adds a harmless extra field.
//
//    DO NOT switch back to `json_object`.  That mode forces a JSON *object*
//  response, which conflicts with the prompt asking for an array and causes
//  the model to wrap results in a random key like {"jokes":[...]}.  While
//  parseResponse handles that wrapper today, relying on it is fragile.
//  `json_schema` is the correct and reliable solution for gpt-4o / gpt-4o-mini.
//

import Foundation

/// OpenAI provider using the Chat Completions API with structured outputs.
final class OpenAIProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .openAI

    private let baseURL = "https://api.openai.com/v1/chat/completions"

    // System prompt keeps the model in JSON-only mode regardless of file content.
    // The json_schema response_format below enforces structure at the API level,
    // so this is a belt-and-suspenders instruction.
    private let systemPrompt = """
    You are a JSON API. You output ONLY a valid JSON object with a single key "jokes" \
    whose value is a JSON array — no markdown, no prose, no explanation.
    Never wrap output in code fences.
    """

    // MARK: - Structured output schema
    //
    // gpt-4o-mini supports json_schema (structured outputs).  We wrap the
    // top-level response as { "jokes": [...] } because json_schema requires a
    // JSON *object* at the root.  parseResponse already unwraps this wrapper.
    //
    // The "joke_item" definition is kept loose (additionalProperties not
    // restricted) so the model can emit extra debugging fields without
    // causing a schema validation failure that would blank the response.
    private let responseFormatSchema: [String: Any] = [
        "type": "json_schema",
        "json_schema": [
            "name": "joke_extraction_response",
            "strict": false,   // false = lenient; avoids blank responses on minor schema drift
            "schema": [
                "type": "object",
                "properties": [
                    "jokes": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "jokeText":       ["type": "string"],
                                "humorMechanism": ["type": ["string", "null"]],
                                "confidence":     ["type": "number"],
                                "explanation":    ["type": ["string", "null"]],
                                "title":          ["type": ["string", "null"]],
                                "tags":           ["type": "array", "items": ["type": "string"]]
                            ],
                            "required": ["jokeText", "confidence"]
                        ]
                    ]
                ],
                "required": ["jokes"]
            ]
        ]
    ] as [String: Any]

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .openAI) != nil
    }

    func extractJokes(from text: String) async throws -> [AIExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .openAI) else {
            throw AIProviderError.keyNotConfigured(.openAI)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)

        let requestBody: [String: Any] = [
            "model": AIProviderType.openAI.defaultModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": prompt]
            ],
            "temperature": 0.3,
            // 16 384 tokens gives room for large files. gpt-4o-mini supports 16 k output.
            "max_tokens": 16384,
            // Structured outputs — enforces { "jokes": [...] } wrapper at the API layer.
            // This replaces the old `json_object` mode which conflicted with the array
            // format the prompt requests and caused unreliable wrapping behavior.
            "response_format": responseFormatSchema
        ]

        guard let endpointURL = URL(string: baseURL) else {
            throw AIProviderError.apiError(.openAI, "Invalid OpenAI endpoint URL: \(baseURL)")
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.openAI, retryAfterSeconds: retryAfter)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.openAI, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // Parse OpenAI response: { choices: [{ message: { content: "..." }, finish_reason: "..." }] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.apiError(.openAI, "Unexpected response format")
        }

        // Warn loudly when the model was cut off — the JSON will be incomplete.
        let finishReason = firstChoice["finish_reason"] as? String ?? ""
        if finishReason == "length" {
            print(" [OpenAI] Response truncated (finish_reason=length) — attempting partial JSON repair")
        }

        return try JokeExtractionPrompt.parseResponse(content, provider: .openAI)
    }
}
