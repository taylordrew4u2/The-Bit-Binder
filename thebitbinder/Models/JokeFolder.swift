//
//  JokeFolder.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class JokeFolder: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var dateCreated: Date = Date()
    var isRecentlyAdded: Bool = false  // Special marker for "Recently Added" folder
    @Relationship(deleteRule: .nullify) var jokes: [Joke]?

    // Soft-delete (trash) support
    var isTrashed: Bool = false
    var deletedDate: Date?

    init(name: String, isRecentlyAdded: Bool = false) {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.isRecentlyAdded = isRecentlyAdded
    }

    // MARK: - Trash Helpers

    func moveToTrash() {
        isTrashed = true
        deletedDate = Date()
    }

    func restoreFromTrash() {
        isTrashed = false
        deletedDate = nil
    }
}
