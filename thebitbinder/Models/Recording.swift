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

    /// The actual audio bytes, stored via external storage so CloudKit syncs the
    /// recording itself across devices. `fileURL` only names a local file, which
    /// never leaves the device; this attribute is what makes playback work on a
    /// second device. Populated at save time (`captureAudioData`) and for legacy
    /// recordings by the v2 data migration.
    @Attribute(.externalStorage) var audioData: Data?

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

    /// Returns a local file URL that is guaranteed to contain the audio, if we
    /// have it at all. If the file isn't present on this device (e.g. a recording
    /// created on another device that synced down via CloudKit), the synced
    /// `audioData` is written to the Documents directory first. Use this — not
    /// `resolvedURL` — for playback, transcription, and sharing.
    func playableURL() -> URL {
        let url = resolvedURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let data = audioData {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    /// Reads the freshly-recorded local file into `audioData` so the audio syncs
    /// across devices. Call right after inserting a new recording. No-op if the
    /// bytes are already captured or the file can't be read.
    func captureAudioData() {
        guard audioData == nil else { return }
        audioData = try? Data(contentsOf: resolvedURL)
    }

    // MARK: - Trash Helpers

    /// True if the audio is available on this device — either the local file
    /// exists or the synced bytes are present (and can be materialized on demand).
    var backingFileExists: Bool {
        FileManager.default.fileExists(atPath: resolvedURL.path) || audioData != nil
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
