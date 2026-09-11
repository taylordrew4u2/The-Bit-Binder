import Foundation

// Run from the repository root:
// swiftc thebitbinder/Utilities/JokeEditorPersistence.swift Tests/JokeEditor/PersistenceRegression.swift -o /tmp/joke-editor-tests
// /tmp/joke-editor-tests
@main
struct PersistenceRegression {
    static func main() throws {
        let folder = UUID()
        let otherFolder = UUID()
        func snapshot(content: String = "Original", folders: Set<UUID> = [folder, otherFolder]) -> JokeEditorSnapshot {
            JokeEditorSnapshot(title: "Title", content: content, notes: "Notes", tags: ["tag"], folderIDs: folders)
        }
        let baseline = snapshot()
        precondition(baseline == snapshot(), "Reading must not dirty the editor")
        precondition(baseline == snapshot(folders: [otherFolder, folder]), "Folder order is not an edit")
        precondition(baseline != snapshot(content: "Dictated text"), "Dictation must dirty the editor")
        precondition(baseline != snapshot(folders: []), "Folder removal must dirty the editor")

        enum SaveError: Error { case failed }
        // Simulate both trash and restore with a failed durable write. The
        // action must roll back without discarding a pending body edit.
        for originalState in [false, true] {
            struct Record: Equatable {
                var isTrashed: Bool
                var deletedDate: Date?
                var dateModified: Date
                var body: String
            }
            let original = Record(
                isTrashed: originalState,
                deletedDate: originalState ? Date(timeIntervalSince1970: 10) : nil,
                dateModified: Date(timeIntervalSince1970: 20),
                body: "Unsaved writing"
            )
            var record = original
            record.isTrashed.toggle()
            record.deletedDate = record.isTrashed ? Date() : nil
            record.dateModified = Date()
            var completed = false
            do {
                try JokeEditorPersistence.saveOrRestore {
                    throw SaveError.failed
                } restore: {
                    record.isTrashed = original.isTrashed
                    record.deletedDate = original.deletedDate
                    record.dateModified = original.dateModified
                }
                completed = true
            } catch SaveError.failed {
                precondition(record == original, "Rollback must preserve the entire original record")
            }
            precondition(!completed, "Failed save must not enter the dismissal path")
        }
        var restored = false
        var saved = false
        try JokeEditorPersistence.saveOrRestore {
            saved = true
        } restore: {
            restored = true
        }
        precondition(saved && !restored, "Successful saves must keep the action")
        print("Joke editor persistence regressions passed")
    }
}
