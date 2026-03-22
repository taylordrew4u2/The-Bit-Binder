import Foundation

/// Fully local fallback for devices where Foundation Models isn't available.
/// Keeps BitBuddy useful without any network calls.
final class LocalFallbackBitBuddyService: BitBuddyBackend {
    static let shared = LocalFallbackBitBuddyService()
    
    private init() {}
    
    var backendName: String { "Local Fallback" }
    var isAvailable: Bool { true }
    var supportsStreaming: Bool { false }
    
    // User profile state
    private var userProfile: UserStyleProfile = .empty()
    
    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        // Simulate typing delay for UX
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Refresh profile on every request since it's local and fast
        updateProfile(from: dataContext.recentJokes)
        
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        if lower.starts(with: "analyze") {
            let content = extractContent(from: trimmed, prefix: "analyze")
            return analyze(content)
        }
        
        if lower.starts(with: "improve") {
            let content = extractContent(from: trimmed, prefix: "improve")
            return improve(content)
        }
        
        if lower.starts(with: "premise") {
            let content = extractContent(from: trimmed, prefix: "premise")
             return premise(content)
        }
        
        if lower.starts(with: "generate") {
            let content = extractContent(from: trimmed, prefix: "generate")
            return generate(content)
        }
        
        if lower.starts(with: "style") {
            return style()
        }
        
        if lower.starts(with: "suggest_topic") || lower.contains("suggest topic") {
            return suggestTopic()
        }
        
        // Output help if not recognized
        return """
        Command not recognized.
        Try:
        • analyze: [joke]
        • improve: [joke]
        • premise [topic]
        • generate [topic]
        • style
        • suggest_topic
        """
    }
    
    // MARK: - Handlers
    
    private func analyze(_ text: String) -> String {
        guard !text.isEmpty else { return "Please provide text to analyze." }
        
        let structure = JokeAnalyzer.structure(text)
        // Detect strengths based on structure and content
        var strengths: [String] = []
        if structure != .unknown { strengths.append(structure.rawValue) }
        
        if let topic = JokeAnalyzer.detectTopic(text) {
             strengths.append("clear topic (\(topic))")
        }
        
        // Check for devices/twists
        let twistFound = BitBuddyResources.twists.contains { twistTemplate in
            return text.lowercased().contains("but") || text.lowercased().contains("actually")
        }
        if twistFound { strengths.append("twist") }
        
        if strengths.isEmpty { strengths.append("concise") }

        let suggestions = JokeAnalyzer.suggestEdits(text)
        
        var response = "Structure: \(structure.rawValue).\n"
        response += "Strengths: \(strengths.joined(separator: ", ")).\n"
        
        if !suggestions.isEmpty {
           response += "Edits:\n\(suggestions.joined(separator: "\n"))"
        } else {
           response += "Edits: None specific found."
        }
        
        return response
    }
    
    private func improve(_ text: String) -> String {
        guard !text.isEmpty else { return "Please provide a joke to improve." }
        let suggestions = JokeAnalyzer.suggestEdits(text)
        
        if suggestions.isEmpty {
             return """
             • Tighten setup: Remove context not needed for the punchline.
             • Swap punchline: Try ending on a harder consonant sound.
             """
        }
        return suggestions.map { "• \($0)" }.joined(separator: "\n")
    }
    
    private func premise(_ topic: String) -> String {
        let actualTopic = topic.isEmpty ? (userProfile.topTopics.max(by: { $0.value < $1.value })?.key ?? "dating") : topic
        return "What if \(actualTopic) implied something totally different about us? (Example: \(actualTopic) is actually just adult hide and seek.)"
    }

    private func generate(_ topic: String) -> String {
        let actualTopic = topic.isEmpty ? (userProfile.topTopics.max(by: { $0.value < $1.value })?.key ?? "work") : topic
        let template = BitBuddyResources.templates.randomElement() ?? "Why do [Group] always [Action]? because [Reason]."
        
        // Simple string replacement
        var joke = template.replacingOccurrences(of: "[Topic]", with: actualTopic)
        joke = joke.replacingOccurrences(of: "[Topic A]", with: actualTopic)
        joke = joke.replacingOccurrences(of: "[Topic B]", with: "everything else")
        joke = joke.replacingOccurrences(of: "[Group]", with: "people")
        joke = joke.replacingOccurrences(of: "[Action]", with: "fail at existing")
        joke = joke.replacingOccurrences(of: "[Reason]", with: "they forgot the rules")
        joke = joke.replacingOccurrences(of: "[expectation]", with: "normal")
        joke = joke.replacingOccurrences(of: "[reality]", with: "a trap")
        joke = joke.replacingOccurrences(of: "[Twist]", with: "more anxiety")
        
        joke = joke.replacingOccurrences(of: "[Adjective]", with: "tired")
        joke = joke.replacingOccurrences(of: "[Relation]", with: "friend")
        joke = joke.replacingOccurrences(of: "[Object]", with: "toaster")
        joke = joke.replacingOccurrences(of: "[Comparison]", with: "it burns everything")
        joke = joke.replacingOccurrences(of: "[Activity]", with: "running")
        joke = joke.replacingOccurrences(of: "[Analogy]", with: "dying slowly")
        joke = joke.replacingOccurrences(of: "[Trait]", with: "loud")
        joke = joke.replacingOccurrences(of: "[Opposite Trait]", with: "quiet")
        
        return joke
    }

    private func style() -> String {
        return userProfile.summary.isEmpty ? "Not enough data to determine style." : userProfile.summary
    }

    private func suggestTopic() -> String {
        // Pick a topic NOT in top topics
        let usedTopics = Set(userProfile.topTopics.keys)
        // Filter BitBuddyResources.topics
        let newTopics = BitBuddyResources.topics.filter { !usedTopics.contains($0) }
        let suggestion = newTopics.randomElement() ?? "quantum physics"
        
        return "\(suggestion.capitalized) (unused). Try: \"Why is \(suggestion) so hard to explain? Because...\""
    }

    // MARK: - Helpers
    
    private func updateProfile(from summaries: [BitBuddyJokeSummary]) {
        var profile = UserStyleProfile()
        guard !summaries.isEmpty else {
            self.userProfile = profile
            return
        }
        
        var totalWords = 0
        var totalChars = 0
        var topicCounts: [String: Int] = [:]
        var structureCounts: [String: Int] = [:]
        
        for joke in summaries {
            totalWords += joke.content.split(separator: " ").count
            totalChars += joke.content.count
            
            if let topic = JokeAnalyzer.detectTopic(joke.content) {
                topicCounts[topic, default: 0] += 1
            }
            
            let structure = JokeAnalyzer.structure(joke.content)
            structureCounts[structure.rawValue, default: 0] += 1
        }
        
        profile.avgWordCount = Double(totalWords) / Double(summaries.count)
        profile.avgCharCount = Double(totalChars) / Double(summaries.count)
        profile.topTopics = topicCounts
        profile.structureDistribution = structureCounts
        
        self.userProfile = profile
    }
    
    private func extractContent(from message: String, prefix: String) -> String {
        var content = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        if content.starts(with: ":") {
            content = content.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return content
    }
    
    @objc private func handleDatabaseChange() {
        // Profile will update on next request via updateProfile(from:)
    }
}
