import Foundation

final class OpenAIJokeExtractionProvider: AIJokeExtractionProvider {

    let providerType: AIProviderType = .openAI

    private var apiKey: String {
        OpenAIKeychainStore.shared.apiKey
    }

    func isConfigured() -> Bool {
        !apiKey.isEmpty
    }

    func extractJokes(from text: String) async throws -> [AIExtractedJoke] {
        try await extractJokes(from: text, hints: .unspecified)
    }

    func extractJokes(from text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        guard !apiKey.isEmpty else {
            throw AIProviderError.notAvailable(.openAI)
        }

        let stripped = ExtractionHints.stripPromptPrefix(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            throw AIProviderError.noJokesFound(.openAI)
        }

        var systemPrompt = """
        You extract individual jokes and bits from comedy documents. Return ONLY a JSON array. Each element must have exactly these fields:
        {"jokeText": "…", "confidence": 0.0-1.0, "title": "short title or null", "humorMechanism": "wordplay|observational|callback|self-deprecating|absurd|null", "tags": ["tag1"]}

        Rules:
        - Extract EVERY joke or bit, even rough drafts
        - Keep the comedian's original wording exactly — never rewrite
        - Each joke must be self-contained
        - If the text has no comedy material, return []
        - Return ONLY the JSON array, nothing else
        """

        if !hints.isUnspecified {
            if hints.separator != .mixed {
                systemPrompt += "\nThe bits are separated by: \(hints.separator.label.lowercased())."
            }
            if hints.length != .varies {
                systemPrompt += "\nTypical bit length: \(hints.length.label.lowercased())."
            }
            if hints.kind != .unknown {
                systemPrompt += "\nDocument type: \(hints.kind.label.lowercased())."
            }
            let notes = hints.freeformNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                systemPrompt += "\nUser notes: \(notes)"
            }
        }

        let truncated = stripped.count > 24000 ? String(stripped.prefix(24000)) : stripped

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Extract all jokes from this document:\n\n\(truncated)"]
        ]

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 4000,
            "temperature": 0.2
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIProviderError.runFailed(.openAI, "API returned status \(code)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw AIProviderError.runFailed(.openAI, "Could not parse API response")
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString: String
        if let start = trimmed.firstIndex(of: "["),
           let end = trimmed.lastIndex(of: "]") {
            jsonString = String(trimmed[start...end])
        } else {
            jsonString = trimmed
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIProviderError.runFailed(.openAI, "Invalid response encoding")
        }

        do {
            let jokes = try JSONDecoder().decode([AIExtractedJoke].self, from: jsonData)
            guard !jokes.isEmpty else {
                throw AIProviderError.noJokesFound(.openAI)
            }
            return jokes
        } catch is AIProviderError {
            throw AIProviderError.noJokesFound(.openAI)
        } catch {
            throw AIProviderError.runFailed(.openAI, "Could not decode extracted jokes: \(error.localizedDescription)")
        }
    }
}
