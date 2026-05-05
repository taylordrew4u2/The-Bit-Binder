import Foundation

final class OpenAIBitBuddyService: BitBuddyBackend {
    static let shared = OpenAIBitBuddyService()

    private init() {}

    var backendName: String { "OpenAI" }

    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    var supportsStreaming: Bool { false }

    private var apiKey: String {
        OpenAIKeychainStore.shared.apiKey
    }

    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw BitBuddyBackendError.unavailable
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Send me a joke or ask me anything about comedy."
        }

        let userPrompt = BitBuddyResources.buildLLMPrompt(message: trimmed, dataContext: dataContext)
        return try await generateResponse(
            userPrompt: userPrompt,
            session: session,
            systemInstructions: BitBuddyResources.llmSystemInstructions
        )
    }

    func generateResponse(
        userPrompt: String,
        session: BitBuddySessionSnapshot,
        systemInstructions: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw BitBuddyBackendError.unavailable
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": systemInstructions]
        ]

        for turn in session.turns.suffix(10) {
            let role: String
            switch turn.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            }
            messages.append(["role": role, "content": turn.text])
        }

        messages.append(["role": "user", "content": userPrompt])

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 300,
            "temperature": 0.8
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BitBuddyBackendError.generationFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw BitBuddyBackendError.generationFailed
        }

        let output = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw BitBuddyBackendError.generationFailed
        }
        return output
    }
}
