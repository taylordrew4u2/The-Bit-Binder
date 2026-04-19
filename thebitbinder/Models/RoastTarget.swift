//
//  RoastTarget.swift
//  thebitbinder
//
//  A person you're writing roast jokes about.
//  Each target has a name, optional photo, notes,
//  and a collection of roast jokes written for them.
//

import Foundation
import SwiftData

/// Sorting options for roast jokes within a target
enum RoastJokeSortOption: String, CaseIterable, Identifiable {
    case custom = "Custom Order"
    case newest = "Newest First"
    case oldest = "Oldest First"
    case mostPerformed = "Most Performed"
    case killers = "Killers First"
    case relatability = "Most Relatable"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .custom: return "line.3.horizontal"
        case .newest: return "clock"
        case .oldest: return "clock.arrow.circlepath"
        case .mostPerformed: return "flame"
        case .killers: return "star.fill"
        case .relatability: return "person.3.fill"
        }
    }
}

@Model
final class RoastTarget: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var traits: [String] = []
    @Attribute(.externalStorage) var photoData: Data?
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    
    /// Number of opening roasts for this target (default 3, configurable 1-10)
    var openingRoastCount: Int = 3

    // Soft-delete (trash) support
    var isTrashed: Bool = false
    var deletedDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \RoastJoke.target)
    var jokes: [RoastJoke]? = []

    /// Convenience: sorted active (non-deleted) jokes, newest first
    /// Safely handles nil relationships and faulted objects during iCloud sync
    @Transient
    var sortedJokes: [RoastJoke] {
        guard let jokeArray = jokes else { return [] }
        // Filter out faulted/invalid objects that can crash during sync
        return jokeArray.compactMap { joke -> RoastJoke? in
            // Access a property to trigger fault resolution - if it fails, skip this object
            guard !joke.isTrashed else { return nil }
            return joke
        }.sorted { $0.dateCreated > $1.dateCreated }
    }
    
    /// Jokes sorted by custom display order (for drag-to-reorder)
    @Transient
    var jokesByOrder: [RoastJoke] {
        guard let jokeArray = jokes else { return [] }
        return jokeArray.compactMap { joke -> RoastJoke? in
            guard !joke.isTrashed else { return nil }
            return joke
        }.sorted { $0.displayOrder < $1.displayOrder }
    }
    
    /// Jokes sorted by performance count (most performed first)
    @Transient
    var jokesByPerformance: [RoastJoke] {
        guard let jokeArray = jokes else { return [] }
        return jokeArray.compactMap { joke -> RoastJoke? in
            guard !joke.isTrashed else { return nil }
            return joke
        }.sorted { $0.performanceCount > $1.performanceCount }
    }
    
    /// Jokes sorted by relatability score (highest first)
    @Transient
    var jokesByRelatability: [RoastJoke] {
        guard let jokeArray = jokes else { return [] }
        return jokeArray.compactMap { joke -> RoastJoke? in
            guard !joke.isTrashed else { return nil }
            return joke
        }.sorted { $0.relatabilityScore > $1.relatabilityScore }
    }
    
    /// Only "killer" jokes that always land
    @Transient
    var killerJokes: [RoastJoke] {
        guard let jokeArray = jokes else { return [] }
        return jokeArray.compactMap { joke -> RoastJoke? in
            guard !joke.isTrashed && joke.isKiller else { return nil }
            return joke
        }.sorted { $0.dateCreated > $1.dateCreated }
    }
    
    /// Tested jokes only
    @Transient
    var testedJokes: [RoastJoke] {
        guard let jokeArray = jokes else { return [] }
        return jokeArray.compactMap { joke -> RoastJoke? in
            guard !joke.isTrashed && joke.isTested else { return nil }
            return joke
        }.sorted { $0.performanceCount > $1.performanceCount }
    }
    
    /// Untested jokes (material that needs stage time)
    @Transient
    var untestedJokes: [RoastJoke] {
        guard let jokeArray = jokes else { return [] }
        return jokeArray.compactMap { joke -> RoastJoke? in
            guard !joke.isTrashed && !joke.isTested else { return nil }
            return joke
        }.sorted { $0.dateCreated > $1.dateCreated }
    }
    
    /// Get jokes sorted by specified option
    func jokesSorted(by option: RoastJokeSortOption) -> [RoastJoke] {
        switch option {
        case .custom:
            return jokesByOrder
        case .newest:
            return sortedJokes
        case .oldest:
            return sortedJokes.reversed()
        case .mostPerformed:
            return jokesByPerformance
        case .killers:
            // Killers first, then non-killers by date
            let killers = killerJokes
            let nonKillers = sortedJokes.filter { !$0.isKiller }
            return killers + nonKillers
        case .relatability:
            return jokesByRelatability
        }
    }

    @Transient
    var jokeCount: Int {
        guard let jokeArray = jokes else { return 0 }
        return jokeArray.filter { !$0.isTrashed }.count
    }
    
    @Transient
    var killerCount: Int {
        killerJokes.count
    }
    
    @Transient
    var testedCount: Int {
        testedJokes.count
    }
    
    /// Safely checks if the model is in a valid state for UI access
    @Transient
    var isValid: Bool {
        // Check if we can safely access properties
        !id.uuidString.isEmpty && !isTrashed
    }

    init(name: String, notes: String = "", traits: [String] = [], photoData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.traits = traits
        self.photoData = photoData
        self.dateCreated = Date()
        self.dateModified = Date()
        self.jokes = []
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
    
    // MARK: - Reorder Support
    
    /// Reorders jokes based on new index positions
    func reorderJokes(_ jokes: [RoastJoke]) {
        for (index, joke) in jokes.enumerated() {
            joke.displayOrder = index
        }
        dateModified = Date()
    }
}