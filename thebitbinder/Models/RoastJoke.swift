//
//  RoastJoke.swift
//  thebitbinder
//
//  A single roast joke written for a specific person (RoastTarget).
//  Designed for mastering joke structure, relatability, and performance testing.
//

import Foundation
import SwiftData

@Model
final class RoastJoke: Identifiable {
    var id: UUID = UUID()
    var content: String = ""
    var title: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    // Soft-delete (trash) support
    var isDeleted: Bool = false
    var deletedDate: Date?

    /// The person this roast is about
    @Relationship(deleteRule: .nullify)
    var target: RoastTarget?
    
    // MARK: - Joke Structure & Craft
    
    /// The setup/premise of the joke
    var setup: String = ""
    
    /// The punchline/payoff
    var punchline: String = ""
    
    /// Performance notes (timing, delivery, crowd reactions)
    var performanceNotes: String = ""
    
    /// How relatable is this joke to general audiences? (1-5 scale)
    var relatabilityScore: Int = 0
    
    /// Has this joke been tested on stage/audience?
    var isTested: Bool = false
    
    /// Date last performed
    var lastPerformedDate: Date?
    
    /// Number of times performed
    var performanceCount: Int = 0
    
    /// Manual display order within target (for custom sorting)
    var displayOrder: Int = 0
    
    /// Is this a "killer" roast that always lands?
    var isKiller: Bool = false
    
    /// Is this an "opening roast" (vs a backup roast)?
    var isOpeningRoast: Bool = false
    
    /// If this is a backup roast, which opening roast does it belong to?
    var parentOpeningRoastID: UUID?
    
    /// Tags for categorization (stored as comma-separated string)
    private var tagsString: String = ""
    
    var tags: [String] {
        get {
            guard !tagsString.isEmpty else { return [] }
            return tagsString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        set {
            tagsString = newValue.joined(separator: ",")
        }
    }
    
    /// Safely checks if the model is in a valid state for UI access
    @Transient
    var isValid: Bool {
        !id.uuidString.isEmpty && !isDeleted
    }
    
    /// Word count for the joke content
    @Transient
    var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
    
    /// Has joke structure been broken down (setup/punchline)?
    @Transient
    var hasStructure: Bool {
        !setup.isEmpty || !punchline.isEmpty
    }

    init(content: String, title: String = "", target: RoastTarget? = nil) {
        self.content = content
        self.title = title.isEmpty ? KeywordTitleGenerator.title(from: content) : title
        self.target = target
    }

    // MARK: - Trash Helpers

    /// Moves this roast joke to trash. Use instead of modelContext.delete() for recoverability.
    func moveToTrash() {
        isDeleted = true
        deletedDate = Date()
        dateModified = Date()
    }

    func restoreFromTrash() {
        isDeleted = false
        deletedDate = nil
        dateModified = Date()
    }
    
    // MARK: - Performance Tracking
    
    /// Record a performance of this joke
    func recordPerformance() {
        performanceCount += 1
        lastPerformedDate = Date()
        isTested = true
        dateModified = Date()
    }
    
    /// Undo a performance (decrement count, min 0)
    func undoPerformance() {
        guard performanceCount > 0 else { return }
        performanceCount -= 1
        if performanceCount == 0 {
            isTested = false
            lastPerformedDate = nil
        }
        dateModified = Date()
    }
}