//
//  NotebookPhotoRecord.swift
//  thebitbinder
//
//  Model for storing notebook page photos
//

import Foundation
import SwiftData

@Model
final class NotebookPhotoRecord: Identifiable {
    var id: UUID = UUID()
    var notes: String = ""  // Renamed from 'caption' per CD_NotebookPhotoRecord schema
    @Attribute(.externalStorage) var imageData: Data?  // Changed from fileURL to imageData (BYTES) per schema
    var dateAdded: Date = Date()  // Renamed from 'createdAt' per CD_NotebookPhotoRecord schema
    var sortOrder: Int = 0  // For manual reordering

    // Folder organisation (nil = unfiled)
    var folder: NotebookFolder?

    // Soft-delete (trash) support
    var isTrashed: Bool = false
    var deletedDate: Date?

    init(notes: String, imageData: Data? = nil) {
        self.id = UUID()
        self.notes = notes
        self.imageData = imageData
        self.dateAdded = Date()
        self.sortOrder = Int(Date().timeIntervalSince1970 * 1000) // Default to timestamp for ordering
    }

    // Convenience accessor for dateCreated (used in queries)
    var dateCreated: Date { dateAdded }

    // MARK: - Trash Helpers

    /// Moves this photo to trash. The imageData is kept until permanent deletion.
    func moveToTrash() {
        isTrashed = true
        deletedDate = Date()
    }

    func restoreFromTrash() {
        isTrashed = false
        deletedDate = nil
    }
}
