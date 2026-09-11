import Foundation

/// Only editor-owned values participate; timestamps and derived counts do not.
struct JokeEditorSnapshot: Equatable {
    let title: String
    let content: String
    let notes: String
    let tags: [String]
    let folderIDs: Set<UUID>
}

enum JokeEditorPersistence {
    /// Restore only the attempted action, preserving unrelated unsaved edits.
    static func saveOrRestore(
        save: () throws -> Void,
        restore: () -> Void
    ) throws {
        do {
            try save()
        } catch {
            restore()
            throw error
        }
    }
}
