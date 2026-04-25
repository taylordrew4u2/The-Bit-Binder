//
//  DailyJournalEntry.swift
//  thebitbinder
//
//  One journal entry per calendar day (user's local timezone).
//

import Foundation
import SwiftData

@Model
final class DailyJournalEntry: Identifiable {
    // CloudKit requires every stored property to have a default value or be optional.
    var id: UUID = UUID()

    /// Noon of the calendar day this entry represents, in the user's local timezone
    /// at the moment of creation. Noon avoids DST edge cases that could push a
    /// midnight-anchored date into the wrong day.
    var date: Date = Date()

    /// Stable "yyyy-MM-dd" key derived from `date` at create/edit time.
    /// This is the dedup key — two entries with the same dateKey are the same day.
    var dateKey: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Answers keyed by `DailyJournalPrompts.Prompt.id`.
    /// Stored as JSON so CloudKit doesn't have to serialize a dictionary relationship.
    private var answersJSON: String = "{}"

    var freeformJournal: String = ""

    /// Optional single-word mood. Kept simple: empty string means "not set".
    var mood: String = ""

    /// Cached completion flag so list views don't recompute for every row.
    /// Authoritative value is `computeIsComplete()`.
    var isComplete: Bool = false

    init(date: Date = Date()) {
        let anchored = DailyJournalEntry.anchorDate(date)
        self.id = UUID()
        self.date = anchored
        self.dateKey = DailyJournalEntry.dateKey(for: anchored)
        self.createdAt = Date()
        self.updatedAt = Date()
        self.answersJSON = "{}"
        self.freeformJournal = ""
        self.mood = ""
        self.isComplete = false
    }

    // MARK: - Answers

    var answers: [String: String] {
        get {
            guard let data = answersJSON.data(using: .utf8) else {
                DataOperationLogger.shared.logError(
                    NSError(domain: "DailyJournalEntry", code: 1, userInfo: [NSLocalizedDescriptionKey: "answersJSON is not valid UTF-8"]),
                    operation: "DailyJournalEntry.answers.get",
                    context: "dateKey=\(dateKey)"
                )
                return [:]
            }
            do {
                return try JSONDecoder().decode([String: String].self, from: data)
            } catch {
                DataOperationLogger.shared.logError(
                    error,
                    operation: "DailyJournalEntry.answers.get",
                    context: "Failed to decode answersJSON for dateKey=\(dateKey)"
                )
                return [:]
            }
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8)
            answersJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    func answer(for promptID: String) -> String {
        answers[promptID] ?? ""
    }

    func setAnswer(_ text: String, for promptID: String) {
        var current = answers
        let trimmed = text
        if trimmed.isEmpty {
            current.removeValue(forKey: promptID)
        } else {
            current[promptID] = trimmed
        }
        answers = current
    }

    // MARK: - Completion

    /// Minimum meaningful freeform length (non-whitespace characters).
    static let minimumFreeformCharacters = 100

    /// Minimum number of non-empty prompt answers to count as complete.
    static let minimumAnsweredPrompts = 3

    /// Recompute and cache `isComplete`. Call after every mutation.
    @discardableResult
    func refreshCompletion() -> Bool {
        isComplete = computeIsComplete()
        return isComplete
    }

    private func computeIsComplete() -> Bool {
        let freeformLength = freeformJournal.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        if freeformLength >= Self.minimumFreeformCharacters { return true }

        let answered = answers.values.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return answered >= Self.minimumAnsweredPrompts
    }

    /// Mark this entry as edited "now" and refresh the completion flag.
    func touch() {
        updatedAt = Date()
        refreshCompletion()
    }

    // MARK: - Date helpers

    /// Anchors a date to noon of that local calendar day. Stable across DST.
    static func anchorDate(_ date: Date) -> Date {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .day], from: date)
        return cal.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: 12, minute: 0, second: 0
        )) ?? date
    }

    /// "yyyy-MM-dd" in the user's local timezone. Stable dedup key.
    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static var todayKey: String { dateKey(for: Date()) }
}
