import Foundation
import SwiftData

@MainActor
enum SiriJokeStore {
    static func save(content: String, in container: ModelContainer) throws -> UUID {
        let capture = try SiriJokeCapture(content: content)
        let configurations = container.configurations
        try SiriJokeCapture.validateStorage(
            isDurable: !configurations.isEmpty && configurations.allSatisfy {
                !$0.isStoredInMemoryOnly && $0.allowsSave
            },
            hasPendingRestore: FileManager.default.fileExists(
                atPath: DataProtectionService.pendingRestoreDir.path
            )
        )

        // Never save or roll back the shared main context: an editor may contain
        // unrelated unsaved writing when Siri is invoked.
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let identifier = try capture.save { request in
            let joke = Joke(content: request.content, title: request.title)
            context.insert(joke)
            return joke.id
        } commit: {
            try context.save()
        } rollback: {
            context.rollback()
        }

        NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
        return identifier
    }
}
