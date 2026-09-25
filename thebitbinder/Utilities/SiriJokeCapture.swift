import Foundation

enum SiriJokeCaptureError: Error, LocalizedError {
    case emptyContent
    case persistentStoreUnavailable
    case restorePending

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Tell Siri the joke you want to save."
        case .persistentStoreUnavailable:
            return "BitBinder cannot save to your library right now. Open BitBinder to check Data Safety, then try again."
        case .restorePending:
            return "Restart BitBinder to finish restoring your library before saving a joke with Siri."
        }
    }
}

/// A validated capture using the same whitespace and automatic-title rules as New Joke.
struct SiriJokeCapture {
    let content: String
    let title: String

    init(content: String) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SiriJokeCaptureError.emptyContent }
        self.content = trimmed
        self.title = KeywordTitleGenerator.title(from: trimmed)
    }

    static func validateStorage(isDurable: Bool, hasPendingRestore: Bool) throws {
        guard !hasPendingRestore else { throw SiriJokeCaptureError.restorePending }
        guard isDurable else { throw SiriJokeCaptureError.persistentStoreUnavailable }
    }

    /// Only return the new identifier after the durable save succeeds. The caller
    /// supplies an isolated context so rollback cannot discard an open editor's work.
    func save<Identifier>(
        insert: (SiriJokeCapture) -> Identifier,
        commit: () throws -> Void,
        rollback: () -> Void
    ) throws -> Identifier {
        let identifier = insert(self)
        try JokeEditorPersistence.saveOrRestore(save: commit, restore: rollback)
        return identifier
    }
}
