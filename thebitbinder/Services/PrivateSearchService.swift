import Foundation

struct PrivateSearchService {
    private struct Response: Decodable {
        let AbstractText: String
        let Definition: String
        let Answer: String
    }

    static func search(_ query: String) async throws -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(string: "https://api.duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1")
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let candidates = [decoded.AbstractText, decoded.Definition, decoded.Answer]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return candidates.first(where: { !$0.isEmpty })
    }
}
