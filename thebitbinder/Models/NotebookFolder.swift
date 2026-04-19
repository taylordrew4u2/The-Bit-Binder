//
//  NotebookFolder.swift
//  thebitbinder
//
//  Model for organizing notebook photos/PDFs into folders.
//

import Foundation
import SwiftData

@Model
final class NotebookFolder: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var dateCreated: Date = Date()
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \NotebookPhotoRecord.folder)
    var photos: [NotebookPhotoRecord]?

    // Soft-delete (trash) support
    var isTrashed: Bool = false
    var deletedDate: Date?

    /// Count of non-trashed photos in this folder
    var activePhotoCount: Int {
        (photos ?? []).filter { !$0.isTrashed }.count
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.sortOrder = Int(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Trash Helpers

    /// Moves folder to trash. Photos are NOT deleted — their folder reference
    /// is nullified by the .nullify delete rule so they become unfiled.
    func moveToTrash() {
        isTrashed = true
        deletedDate = Date()
    }

    func restoreFromTrash() {
        isTrashed = false
        deletedDate = nil
    }
}
