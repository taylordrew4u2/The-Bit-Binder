//
//  SetList.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class SetList: Identifiable {
    // ⚠️ IMPORTANT: After modifying any properties of this model, you MUST call
    // modelContext.save() to persist changes to the database. Forgetting to save
    // will result in data loss and inconsistent app state.
    
    var id: UUID = UUID()
    var name: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    var notes: String = ""  // Added per CD_SetList schema

    // Soft-delete (trash) support
    var isTrashed: Bool = false
    var deletedDate: Date?
    
    // MARK: - Finalization for Live Performance
    
    /// When true, the set is locked for live performance - no editing, clean view
    var isFinalized: Bool = false
    
    /// Date when this set was finalized for performance
    var finalizedDate: Date?
    
    /// Estimated runtime in minutes (set during finalization)
    var estimatedMinutes: Int = 0
    
    /// Venue/event name for this performance
    var venueName: String = ""
    
    /// Performance date/time (optional - for planning)
    var performanceDate: Date?

    // Store UUIDs as a comma-separated string to avoid SwiftData Array<UUID> issues
    private var jokeIDsString: String = ""
    private var roastJokeIDsString: String = ""
    
    // Computed property to access as [UUID]
    var jokeIDs: [UUID] {
        get {
            guard !jokeIDsString.isEmpty else { return [] }
            return jokeIDsString.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
        set {
            jokeIDsString = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }
    
    // Roast joke IDs stored the same way
    var roastJokeIDs: [UUID] {
        get {
            guard !roastJokeIDsString.isEmpty else { return [] }
            return roastJokeIDsString.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
        set {
            roastJokeIDsString = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }
    
    /// Total number of items (regular + roast) in this set
    var totalItemCount: Int {
        jokeIDs.count + roastJokeIDs.count
    }
    
    init(name: String, jokeIDs: [UUID] = [], roastJokeIDs: [UUID] = [], notes: String = "") {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.dateModified = Date()
        self.notes = notes
        self.jokeIDsString = jokeIDs.map { $0.uuidString }.joined(separator: ",")
        self.roastJokeIDsString = roastJokeIDs.map { $0.uuidString }.joined(separator: ",")
    }

    // MARK: - Trash Helpers

    /// Moves this set list to trash. Use instead of modelContext.delete() for recoverability.
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
    
    // MARK: - Finalization Helpers
    
    /// Finalize the set for live performance. Locks editing and prepares clean view.
    func finalize(estimatedMinutes: Int = 0, venueName: String = "", performanceDate: Date? = nil) {
        isFinalized = true
        finalizedDate = Date()
        self.estimatedMinutes = estimatedMinutes
        self.venueName = venueName
        self.performanceDate = performanceDate
        dateModified = Date()
    }
    
    /// Unfinalize to allow editing again
    func unfinalize() {
        isFinalized = false
        finalizedDate = nil
        dateModified = Date()
    }
    
    /// Check if model is valid (not deleted from context)
    var isValid: Bool {
        self.modelContext != nil
    }

    // MARK: - Dangling ID Cleanup

    /// Removes joke/roast IDs that no longer reference existing records.
    /// Returns true if any IDs were removed.
    @discardableResult
    func cleanDanglingIDs(existingJokeIDs: Set<UUID>, existingRoastJokeIDs: Set<UUID>) -> Bool {
        let cleanedJokes = jokeIDs.filter { existingJokeIDs.contains($0) }
        let cleanedRoasts = roastJokeIDs.filter { existingRoastJokeIDs.contains($0) }
        let changed = cleanedJokes.count != jokeIDs.count || cleanedRoasts.count != roastJokeIDs.count
        if changed {
            jokeIDs = cleanedJokes
            roastJokeIDs = cleanedRoasts
            dateModified = Date()
        }
        return changed
    }
}