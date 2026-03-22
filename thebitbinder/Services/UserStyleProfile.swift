import Foundation

struct UserStyleProfile: Codable, Sendable {
    var avgWordCount: Double = 0.0
    var avgCharCount: Double = 0.0
    var topTopics: [String: Int] = [:]
    var structureDistribution: [String: Int] = [:]
    
    // Formatting logic for display
    var summary: String {
        let sortedTopics = topTopics.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        let mainStructure = structureDistribution.max(by: { $0.value < $1.value })
        
        var parts: [String] = []
        parts.append("Avg length: \(Int(avgWordCount)) words.")
        if !sortedTopics.isEmpty {
            parts.append("Top topics: \(sortedTopics.joined(separator: ", ")).")
        }
        if let structure = mainStructure {
            let total = Double(structureDistribution.values.reduce(0, +))
            let pct = Int((Double(structure.value) / total) * 100)
            parts.append("Structure: \(pct)% \(structure.key).")
        }
        return parts.joined(separator: " ")
    }
    
    static func empty() -> UserStyleProfile {
        return UserStyleProfile()
    }
}
