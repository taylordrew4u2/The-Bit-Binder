//
//  DailyJournalStore.swift
//  thebitbinder
//
//  Thin helpers around SwiftData for the Daily Journal.
//  Guarantees one entry per calendar day and resolves duplicates that might
//  appear briefly during a CloudKit merge.
//

import Foundation
import SwiftData

@MainActor
enum DailyJournalStore {

    /// Returns today's entry, creating one if needed. If a CloudKit merge
    /// produced duplicates for the same day, keeps the oldest and deletes
    /// the rest (after copying any meaningful content forward).
    @discardableResult
    static func entryForToday(in context: ModelContext) -> DailyJournalEntry {
        entry(for: Date(), in: context)
    }

    /// Find-or-create an entry for an arbitrary calendar date (backfill path).
    @discardableResult
    static func entry(for date: Date, in context: ModelContext) -> DailyJournalEntry {
        let key = DailyJournalEntry.dateKey(for: date)
        let descriptor = FetchDescriptor<DailyJournalEntry>(
            predicate: #Predicate { $0.dateKey == key },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        let existing = (try? context.fetch(descriptor)) ?? []

        if let primary = existing.first {
            // Merge any duplicates into the primary record.
            if existing.count > 1 {
                mergeDuplicates(into: primary, duplicates: Array(existing.dropFirst()), in: context)
            }
            return primary
        }

        let entry = DailyJournalEntry(date: date)
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Whether today's entry exists and is marked complete.
    static func isTodayComplete(in context: ModelContext) -> Bool {
        let key = DailyJournalEntry.todayKey
        let descriptor = FetchDescriptor<DailyJournalEntry>(
            predicate: #Predicate { $0.dateKey == key }
        )
        guard let entries = try? context.fetch(descriptor), let entry = entries.first else {
            return false
        }
        return entry.isComplete
    }

    // MARK: - Private

    private static func mergeDuplicates(
        into primary: DailyJournalEntry,
        duplicates: [DailyJournalEntry],
        in context: ModelContext
    ) {
        for dupe in duplicates {
            // Pull forward any content the primary doesn't already have.
            if primary.freeformJournal.isEmpty, !dupe.freeformJournal.isEmpty {
                primary.freeformJournal = dupe.freeformJournal
            }
            if primary.mood.isEmpty, !dupe.mood.isEmpty {
                primary.mood = dupe.mood
            }
            var merged = primary.answers
            for (k, v) in dupe.answers where (merged[k] ?? "").isEmpty {
                merged[k] = v
            }
            primary.answers = merged
            context.delete(dupe)
        }
        primary.touch()
        try? context.save()
    }
}
