import Foundation

@main
struct AutoSaveRegression {
    @MainActor
    static func main() async throws {
        let editor = AutoSaveManager(debounceNanoseconds: 10_000_000, feedbackNanoseconds: 50_000_000)
        let otherEditor = AutoSaveManager(debounceNanoseconds: 10_000_000)
        var writes = 0
        var otherWrites = 0
        editor.scheduleSave { writes += 1; return true }
        editor.scheduleSave { writes += 10; return true }
        otherEditor.scheduleSave { otherWrites += 1; return true }
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(writes == 10, "Debounce must save only the latest edit")
        precondition(otherWrites == 1, "Independent editors must not cancel each other")
        precondition(!editor.hasUnsavedChanges && editor.lastSaveTime != nil)

        editor.saveNow { false }
        precondition(editor.hasUnsavedChanges && editor.lastSaveTime == nil,
                     "A failed save must never display Saved")
        try await Task.sleep(nanoseconds: 60_000_000)
        precondition(editor.hasUnsavedChanges, "Old success feedback must not hide a later failure")

        editor.scheduleSave { writes += 100; return true }
        editor.saveNow { writes += 1; return true }
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(writes == 11, "Immediate exit save must cancel the queued save")
        try await Task.sleep(nanoseconds: 40_000_000)
        precondition(editor.lastSaveTime == nil, "Saved feedback must expire without further editing")
        print("Autosave regression checks passed")
    }
}
