//
//  Recording.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class Recording: Identifiable {
    var id: UUID = UUID()
    var title: String = ""  // Renamed from 'name' to match CD_Recording schema
    var dateCreated: Date = Date()
    var duration: TimeInterval = 0.0
    var fileURL: String = ""
    var transcription: String?
    var isProcessed: Bool = false  // Added per CD_Recording schema

    // Soft-delete (trash) support
    var isTrashed: Bool = false
    var deletedDate: Date?

    init(title: String, fileURL: String, duration: TimeInterval = 0) {
        self.id = UUID()
        self.title = title
        self.dateCreated = Date()
        self.duration = duration
        self.fileURL = fileURL
        self.transcription = nil
        self.isProcessed = false
    }

    // MARK: - File URL Resolution

    /// Resolves `fileURL` (which may be a bare filename or a stale absolute path)
    /// to an actual file-system URL in the Documents directory.
    ///
    /// Logic:
    /// - Absolute path  use it if the file still exists; otherwise extract the
    ///   filename and look in Documents (sandbox paths change between installs).
    /// - Relative / bare filename  prepend the Documents directory.
    var resolvedURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if fileURL.hasPrefix("/") {
            let absURL = URL(fileURLWithPath: fileURL)
            if FileManager.default.fileExists(atPath: absURL.path) {
                return absURL
            }
            // Stale absolute path — fall back to filename in Documents
            return documentsPath.appendingPathComponent(absURL.lastPathComponent)
        }
        return documentsPath.appendingPathComponent(fileURL)
    }

    // MARK: - Trash Helpers

    /// True if the backing audio file exists on disk at `resolvedURL`.
    var backingFileExists: Bool {
        FileManager.default.fileExists(atPath: resolvedURL.path)
    }

    /// Soft-deletes this recording record. The audio file is NOT deleted here.
    /// Permanent deletion (file + record) must be done explicitly by the caller.
    func moveToTrash() {
        isTrashed = true
        deletedDate = Date()
    }

    func restoreFromTrash() {
        isTrashed = false
        deletedDate = nil
    }
}
