//
//  Joke.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let bitBinderJoke = UTType(exportedAs: "com.thebitbinder.joke")
}

@Model
final class Joke: Identifiable {
    var id: UUID = UUID()
    var content: String = ""
    var title: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    
    // Many-to-many: A joke can be in multiple folders
    // CloudKit requires ALL relationships to be optional
    @Relationship(deleteRule: .nullify, inverse: \JokeFolder.jokes) var folders: [JokeFolder]?
    
    // Legacy single folder support (computed for backward compatibility)
    var folder: JokeFolder? {
        get { (folders ?? []).first }
        set {
            if let newFolder = newValue {
                if !(folders ?? []).contains(where: { $0.id == newFolder.id }) {
                    folders = [newFolder]
                }
            } else {
                folders = []
            }
        }
    }
    
    // Soft-delete (trash) support
    var isTrashed: Bool = false
    var deletedDate: Date?
    
    // Smart categorization fields - stored as strings to avoid SwiftData array issues
    @Transient var categorizationResults: [CategoryMatch] = []
    private var categorizationResultsData: Data?

    var primaryCategory: String?
    
    // Store as comma-separated string internally
    private var allCategoriesString: String = ""
    private var categoryScoresString: String = ""  // format: "category1:0.8|category2:0.6"
    private var styleTagsString: String = ""  // format: "tag1|tag2"
    private var craftNotesString: String = ""  // format: "signal1|signal2"
    
    // Style metadata
    var comedicTone: String?
    var structureScore: Double = 0.0
    
    // AI categorization
    var category: String?  // Primary category from AI
    private var tagsString: String = ""  // AI-suggested tags stored as comma-separated
    var difficulty: String?  // Easy, Medium, Hard
    var humorRating: Int = 0  // 1-10 rating
    
    // The Hits - perfected jokes that work every time
    var isHit: Bool = false
    
    // Open Mic - jokes tagged for open mic sets
    var isOpenMic: Bool = false
    
    // Pre-computed word count for fast sorting and filtering
    var wordCount: Int = 0
    
    // Scratch notes / ideas related to this joke
    var notes: String = ""
    
    // Import source tracking
    var importSource: String?  // Source file name if imported
    var importConfidence: String?  // high/medium/low
    var importTimestamp: Date?  // When imported
    
    // Computed property for tags
    var tags: [String] {
        get {
            guard !tagsString.isEmpty else { return [] }
            return tagsString.split(separator: ",").map { String($0) }
        }
        set {
            // Strip commas from individual tags to prevent corruption of the serialized format
            tagsString = newValue.map { $0.replacingOccurrences(of: ",", with: "") }.joined(separator: ",")
        }
    }
    
    // Computed property for allCategories
    var allCategories: [String] {
        get {
            guard !allCategoriesString.isEmpty else { return [] }
            return allCategoriesString.split(separator: ",").map { String($0) }
        }
        set {
            // Strip commas from individual categories to prevent corruption of the serialized format
            allCategoriesString = newValue.map { $0.replacingOccurrences(of: ",", with: "") }.joined(separator: ",")
        }
    }
    
    // Computed property for categoryConfidenceScores
    var categoryConfidenceScores: [String: Double] {
        get {
            guard !categoryScoresString.isEmpty else { return [:] }
            var result: [String: Double] = [:]
            for pair in categoryScoresString.split(separator: "|") {
                let parts = pair.split(separator: ":")
                if parts.count == 2, let score = Double(parts[1]) {
                    result[String(parts[0])] = score
                } else {
                    DataOperationLogger.shared.logOperation(.warning,
                        "Joke[\(title)]: failed to parse categoryScore segment '\(pair)' — expected 'category:score' format, skipping")
                }
            }
            return result
        }
        set {
            // Strip pipes and colons from keys to prevent corruption of the serialized format
            categoryScoresString = newValue.map { entry in
                let safeKey = entry.key
                    .replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: ":", with: "")
                return "\(safeKey):\(entry.value)"
            }.joined(separator: "|")
        }
    }
    
    // Computed property for styleTags
    var styleTags: [String] {
        get {
            guard !styleTagsString.isEmpty else { return [] }
            return styleTagsString.split(separator: "|").map { String($0) }
        }
        set {
            // Strip pipes from individual tags to prevent corruption of the serialized format
            styleTagsString = newValue.map { $0.replacingOccurrences(of: "|", with: "") }.joined(separator: "|")
        }
    }
    
    // Computed property for craftNotes
    var craftNotes: [String] {
        get {
            guard !craftNotesString.isEmpty else { return [] }
            return craftNotesString.split(separator: "|").map { String($0) }
        }
        set {
            // Strip pipes from individual notes to prevent corruption of the serialized format
            craftNotesString = newValue.map { $0.replacingOccurrences(of: "|", with: "") }.joined(separator: "|")
        }
    }
    
    func loadCategorizationResults() {
        guard let data = categorizationResultsData else { return }
        do {
            categorizationResults = try JSONDecoder().decode([CategoryMatch].self, from: data)
        } catch {
            DataOperationLogger.shared.logError(error,
                operation: "loadCategorizationResults",
                context: "Joke[\(title)] — \(data.count) bytes of stored JSON failed to decode as [CategoryMatch]")
        }
    }

    func saveCategorizationResults() {
        do {
            categorizationResultsData = try JSONEncoder().encode(categorizationResults)
        } catch {
            DataOperationLogger.shared.logError(error,
                operation: "saveCategorizationResults",
                context: "Joke[\(title)] — \(categorizationResults.count) CategoryMatch entries failed to encode")
        }
    }

    init(content: String, title: String = "", folder: JokeFolder? = nil) {
        self.id = UUID()
        self.content = content
        self.title = title.isEmpty ? KeywordTitleGenerator.title(from: content) : title
        self.dateCreated = Date()
        self.dateModified = Date()
        if let folder { self.folders = [folder] } else { self.folders = [] }
        self.comedicTone = nil
        self.structureScore = 0.0
        self.wordCount = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        // New jokes start active (not in trash)
        self.isTrashed = false
        self.deletedDate = nil
        
        loadCategorizationResults()
    }
    
    /// Recalculates and stores the word count. Call after editing `content`.
    func updateWordCount() {
        wordCount = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
    
    // MARK: - Trash Helpers
    
    func moveToTrash() {
        isTrashed = true
        deletedDate = Date()
        dateModified = Date()
    }
    
    func restoreFromTrash() {
        isTrashed = false
        deletedDate = nil
        dateModified = Date()
    }
}

// MARK: - Drag & Drop Support

/// Lightweight codable token used for drag-and-drop.
/// We pass only the UUID so the destination can look up the real Joke from SwiftData.
struct JokeDragItem: Codable, Transferable {
    let jokeID: String
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bitBinderJoke)
    }
}