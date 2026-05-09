import Foundation

struct PrivateSearchService {
    private struct DuckDuckGoResponse: Decodable {
        let AbstractText: String
        let Definition: String
        let Answer: String
        let RelatedTopics: [DuckDuckGoTopic]
    }

    private struct DuckDuckGoTopic: Decodable {
        let Text: String?
        let Topics: [DuckDuckGoNestedTopic]?
    }

    private struct DuckDuckGoNestedTopic: Decodable {
        let Text: String?
    }

    private struct WikipediaSearchResponse: Decodable {
        let query: WikipediaQuery?
    }

    private struct WikipediaQuery: Decodable {
        let search: [WikipediaSearchResult]
    }

    private struct WikipediaSearchResult: Decodable {
        let title: String
    }

    private struct WikipediaSummaryResponse: Decodable {
        let extract: String?
    }

    static func search(_ query: String) async throws -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let duckDuckGo = await duckDuckGoAnswer(for: trimmed) {
            return duckDuckGo
        }

        if isTimeSensitive(trimmed),
           let currentDuckDuckGo = await duckDuckGoAnswer(for: "current \(trimmed)") {
            return currentDuckDuckGo
        }

        if let wikipedia = await wikipediaAnswer(for: trimmed) {
            return wikipedia
        }

        return nil
    }

    private static func isTimeSensitive(_ query: String) -> Bool {
        let lower = query.lowercased()
        let markers = [
            "current", "today", "now", "latest", "recent", "right now",
            "this year", "this month", "president", "prime minister",
            "mayor", "governor", "ceo", "score", "price", "weather"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func duckDuckGoAnswer(for query: String) async -> String? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1")
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(DuckDuckGoResponse.self, from: data)
            let relatedTopicText = decoded.RelatedTopics
                .flatMap { topic -> [String] in
                    let direct = topic.Text.map { [$0] } ?? []
                    let nested = topic.Topics?.compactMap(\.Text) ?? []
                    return direct + nested
                }

            let candidates = [decoded.Answer, decoded.AbstractText, decoded.Definition]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                + relatedTopicText.map { cleanRelatedTopic($0) }

            return candidates.first(where: { !$0.isEmpty })
        } catch {
            return nil
        }
    }

    private static func wikipediaAnswer(for query: String) async -> String? {
        guard let title = await wikipediaBestTitle(for: query) else {
            return nil
        }

        let encodedTitle = title.replacingOccurrences(of: " ", with: "_")
        guard let titlePath = encodedTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(titlePath)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
            return decoded.extract?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func wikipediaBestTitle(for query: String) async -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "utf8", value: "1"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "srlimit", value: "1")
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(WikipediaSearchResponse.self, from: data)
            return decoded.query?.search.first?.title
        } catch {
            return nil
        }
    }

    private static func cleanRelatedTopic(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorRange = trimmed.range(of: " - ") else {
            return trimmed
        }

        let title = trimmed[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmed[separatorRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !detail.isEmpty else {
            return String(title)
        }

        return "\(title): \(detail)"
    }
}
