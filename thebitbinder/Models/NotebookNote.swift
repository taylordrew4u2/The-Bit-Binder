//
//  NotebookNote.swift
//  thebitbinder
//
//  Plain text "line notebook" note. Backs the text-based Notebook that
//  replaced the photo notebook. Syncs across devices via CloudKit like the
//  other @Model types.
//

import Foundation
import SwiftData

@Model
final class NotebookNote: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    var sortOrder: Int = 0

    // Soft-delete (trash) support — mirrors the pattern used across the app.
    var isTrashed: Bool = false
    var deletedDate: Date?

    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        let now = Date()
        self.dateCreated = now
        self.dateModified = now
        self.sortOrder = Int(now.timeIntervalSince1970 * 1000)
    }

    /// First non-empty line of the content, used as a preview / fallback title.
    var previewLine: String {
        content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Title to show in lists — the explicit title if set, otherwise the first line.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let preview = previewLine
        return preview.isEmpty ? "Untitled Note" : preview
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
