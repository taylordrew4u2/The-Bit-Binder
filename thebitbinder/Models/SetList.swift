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
    
    // MARK: - Legacy Set Planning

    /// Legacy flag retained for existing data compatibility.
    var isFinalized: Bool = false
    
    /// Legacy date retained for existing data compatibility.
    var finalizedDate: Date?
    
    /// Estimated runtime in minutes.
    var estimatedMinutes: Int = 0
    
    /// Venue/event name for this set.
    var venueName: String = ""
    
    /// Optional set date/time.
    var performanceDate: Date?

    // Store UUIDs as a comma-separated string to avoid SwiftData Array<UUID> issues
    private var jokeIDsString: String = ""
    private var roastJokeIDsString: String = ""
    
    // Computed property to access as [UUID]
    var jokeIDs: [UUID] {
        get {
            guard !jokeIDsString.isEmpty else { return [] }
            return jokeIDsString.split(separator: ",").compactMap { segment in
                let raw = String(segment)
                guard let uuid = UUID(uuidString: raw) else {
                    DataOperationLogger.shared.logOperation(.warning,
                        "SetList[\(name)]: failed to parse jokeID segment '\(raw)' — skipping")
                    return nil
                }
                return uuid
            }
        }
        set {
            jokeIDsString = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }

    // Roast joke IDs stored the same way
    var roastJokeIDs: [UUID] {
        get {
            guard !roastJokeIDsString.isEmpty else { return [] }
            return roastJokeIDsString.split(separator: ",").compactMap { segment in
                let raw = String(segment)
                guard let uuid = UUID(uuidString: raw) else {
                    DataOperationLogger.shared.logOperation(.warning,
                        "SetList[\(name)]: failed to parse roastJokeID segment '\(raw)' — skipping")
                    return nil
                }
                return uuid
            }
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
    
    // MARK: - Legacy Planning Helpers
    
    /// Retained for old call sites and existing data migrations.
    func finalize(estimatedMinutes: Int = 0, venueName: String = "", performanceDate: Date? = nil) {
        isFinalized = true
        finalizedDate = Date()
        self.estimatedMinutes = estimatedMinutes
        self.venueName = venueName
        self.performanceDate = performanceDate
        dateModified = Date()
    }
    
    /// Clears the legacy finalized flag.
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
