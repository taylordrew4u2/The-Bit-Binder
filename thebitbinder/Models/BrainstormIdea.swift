//
//  BrainstormIdea.swift
//  thebitbinder
//
//  Created for quick joke brainstorming
//

import Foundation
import SwiftData

@Model
final class BrainstormIdea: Identifiable {
    var id: UUID = UUID()
    var content: String = ""
    var dateCreated: Date = Date()
    var colorHex: String = "F5E6D3"  // Store color as hex for variety in grid
    var boardPositionX: Double = -1
    var boardPositionY: Double = -1
    var isVoiceNote: Bool = false  // Track if it was created via voice
    var notes: String = ""  // Scratch notes / related thoughts

    // Soft-delete (trash) support — mirrors Joke model
    var isTrashed: Bool = false
    var deletedDate: Date?

    init(content: String, colorHex: String = "F5E6D3", isVoiceNote: Bool = false) {
        self.id = UUID()
        self.content = content
        self.dateCreated = Date()
        self.colorHex = colorHex
        self.boardPositionX = -1
        self.boardPositionY = -1
        self.isVoiceNote = isVoiceNote
        self.isTrashed = false
        self.deletedDate = nil
    }
    
    // Predefined color palette for sticky notes
    static let noteColors: [String] = [
        "FFE082", // Yellow
        "FFD54F", // Amber
        "FFB74D", // Orange
        "F48FB1", // Pink
        "CE93D8", // Purple
        "9FA8DA", // Indigo
        "81D4FA", // Blue
        "80CBC4", // Teal
        "A5D6A7", // Green
        "C5E1A5", // Light green
    ]

    static func randomColor() -> String {
        noteColors.randomElement() ?? "FFE082"
    }

    // MARK: - Trash Helpers

    /// Moves this idea to trash. Use instead of modelContext.delete() for recoverability.
    func moveToTrash() {
        isTrashed = true
        deletedDate = Date()
    }

    func restoreFromTrash() {
        isTrashed = false
        deletedDate = nil
    }
}
