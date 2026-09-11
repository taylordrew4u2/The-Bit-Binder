import Foundation
import Combine

/// Owned by an editor so unrelated documents cannot cancel each other's saves.
@MainActor
final class AutoSaveManager: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var lastSaveTime: Date?

    private let debounceNanoseconds: UInt64
    private let feedbackNanoseconds: UInt64
    private var pendingSave: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    init(debounceNanoseconds: UInt64 = 1_500_000_000, feedbackNanoseconds: UInt64 = 3_000_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
        self.feedbackNanoseconds = feedbackNanoseconds
    }

    /// The action returns true only after a successful save (or a clean no-op).
    func scheduleSave(_ action: @escaping @MainActor () -> Bool) {
        pendingSave?.cancel()
        feedbackTask?.cancel()
        lastSaveTime = nil
        hasUnsavedChanges = true
        pendingSave = Task { [weak self] in
            guard let delay = self?.debounceNanoseconds else { return }
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.performSave(action)
        }
    }

    func saveNow(_ action: @MainActor () -> Bool) {
        pendingSave?.cancel()
        pendingSave = nil
        performSave(action)
    }

    private func performSave(_ action: @MainActor () -> Bool) {
        feedbackTask?.cancel()
        isSaving = true
        let succeeded = action()
        isSaving = false
        hasUnsavedChanges = !succeeded
        lastSaveTime = succeeded ? Date() : nil
        guard succeeded else { return }
        feedbackTask = Task { [weak self] in
            guard let delay = self?.feedbackNanoseconds else { return }
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.lastSaveTime = nil
        }
    }

    deinit {
        pendingSave?.cancel()
        feedbackTask?.cancel()
    }
}
