//
//  JournalEntriesListView.swift
//  thebitbinder
//
//  Past journal entries. Allows backfilling a missed day.
//

import SwiftUI
import SwiftData

struct JournalEntriesListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DailyJournalEntry.date, order: .reverse)
    private var entries: [DailyJournalEntry]

    @State private var showBackfillPicker = false
    @State private var backfillDate: Date = Date()

    private static let rowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "book.closed",
                    description: Text("Your journal entries will show up here.")
                )
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        JournalEntryEditorView(entry: entry, isBackfill: entry.dateKey != DailyJournalEntry.todayKey)
                    } label: {
                        row(for: entry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Past Entries")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    backfillDate = defaultBackfillDate()
                    showBackfillPicker = true
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .accessibilityLabel("Backfill entry")
            }
        }
        .sheet(isPresented: $showBackfillPicker) {
            NavigationStack {
                BackfillDatePicker(date: $backfillDate) { chosen in
                    let entry = DailyJournalStore.entry(for: chosen, in: modelContext)
                    showBackfillPicker = false
                    openedEntry = entry
                }
            }
            .presentationDetents([.medium])
        }
        .navigationDestination(item: $openedEntry) { entry in
            JournalEntryEditorView(entry: entry, isBackfill: entry.dateKey != DailyJournalEntry.todayKey)
        }
    }

    @State private var openedEntry: DailyJournalEntry?

    // MARK: - Row

    private func row(for entry: DailyJournalEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isComplete ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.rowFormatter.string(from: entry.date))
                    .font(.body)
                if let preview = previewText(for: entry) {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if entry.dateKey == DailyJournalEntry.todayKey {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func previewText(for entry: DailyJournalEntry) -> String? {
        let trimmed = entry.freeformJournal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstAnswer = entry.answers.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return firstAnswer
    }

    private func defaultBackfillDate() -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }
}

// MARK: - Backfill Date Picker

private struct BackfillDatePicker: View {
    @Binding var date: Date
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Date",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            } footer: {
                Text("Fill in a past day you missed.")
            }

            Section {
                Button("Open Entry") { onPick(date) }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Backfill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
