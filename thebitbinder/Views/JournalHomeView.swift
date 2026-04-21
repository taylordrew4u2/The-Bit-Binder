//
//  JournalHomeView.swift
//  thebitbinder
//
//  Section root for Daily Journal. Shows today's status and a shortcut
//  into the past-entries list.
//

import SwiftUI
import SwiftData

struct JournalHomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DailyJournalEntry.date, order: .reverse)
    private var entries: [DailyJournalEntry]

    @State private var showTodayEditor = false

    private var todayEntry: DailyJournalEntry? {
        let key = DailyJournalEntry.todayKey
        return entries.first { $0.dateKey == key }
    }

    private var todayIsComplete: Bool { todayEntry?.isComplete ?? false }

    var body: some View {
        List {
            Section {
                todayStatusRow
                    .contentShape(Rectangle())
                    .onTapGesture { openToday() }

                Button {
                    openToday()
                } label: {
                    Label(todayEntry == nil ? "Start Today's Entry" : "Open Today's Entry",
                          systemImage: "square.and.pencil")
                }
            } header: {
                Text("Today")
            } footer: {
                if !todayIsComplete {
                    Text("A few lines is plenty. One entry per day.")
                }
            }

            Section {
                NavigationLink {
                    JournalEntriesListView()
                } label: {
                    Label("Past Entries", systemImage: "calendar")
                }

                NavigationLink {
                    JournalReminderSettingsView()
                } label: {
                    Label("Reminder", systemImage: "bell")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showTodayEditor) {
            NavigationStack {
                JournalEntryEditorView(
                    entry: DailyJournalStore.entryForToday(in: modelContext),
                    isBackfill: false
                )
            }
        }
    }

    // MARK: - Rows

    private var todayStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: todayIsComplete ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(todayIsComplete ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(todayIsComplete ? "Today is complete" : "Today is incomplete")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func openToday() {
        haptic(.light)
        showTodayEditor = true
    }
}

#Preview {
    NavigationStack { JournalHomeView() }
        .modelContainer(for: DailyJournalEntry.self, inMemory: true)
}
