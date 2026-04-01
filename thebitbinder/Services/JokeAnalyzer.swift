import Foundation

enum JokeStructureType: String, CaseIterable, Codable {
    case oneLiner = "one-liner"
    case setupPunchline = "setup-punchline"
    case ruleOfThree = "rule of three"
    case anecdote = "anecdote"
    case unknown = "unknown"
}

struct JokeAnalyzer {
    
    // Analyzes joke structure and content
    static func structure(_ text: String) -> JokeStructureType {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".?!")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let wordCount = text.split(separator: " ").count
        
        if wordCount < 20 && sentences.count <= 2 {
            return .oneLiner
        }
        
        if sentences.count == 2 {
            return .setupPunchline
        }
        
        if text.contains(",") && (text.lowercased().contains("and") || text.lowercased().contains("or")) {
            // Very basic heuristic for rule of three
            let commaCount = text.filter { $0 == "," }.count
            if commaCount >= 2 {
                return .ruleOfThree
            }
        }
        
        if wordCount > 40 {
            return .anecdote
        }
        
        return .unknown
    }
    
    static func suggestEdits(_ text: String) -> [String] {
        var suggestions: [String] = []
        let lower = text.lowercased()
        
        // Filler words check
        for filler in BitBuddyResources.fillerWords {
            // Use regex or string matching with boundaries to avoid finding "so" in "some"
            if lower.range(of: "\\b\(filler)\\b", options: .regularExpression) != nil {
                suggestions.append("Cut filler: \"\(filler)\" adds nothing.")
            }
        }
        
        // Synonym check
        for (word, replacements) in BitBuddyResources.synonyms {
            if lower.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
                let randomReplacement = replacements.randomElement() ?? word
                suggestions.append("Swap \"\(word)\"  \"\(randomReplacement)\" for impact.")
            }
        }
        
        // Length check
        let wordCount = text.split(separator: " ").count
        if wordCount > 25 {
            suggestions.append("Tighten: Try cutting 3-5 words.")
        }
        
        return Array(suggestions.prefix(3)) // Limit to top 3
    }
    
    static func detectTopic(_ text: String) -> String? {
        let lower = text.lowercased()
        // Simple keyword matching
        // Sort topics by length descending to match longer phrases first if any
        let sortedTopics = BitBuddyResources.topics.sorted { $0.count > $1.count }
        
        for topic in sortedTopics {
            if lower.contains(topic) {
                return topic
            }
        }
        return nil
    }
}
