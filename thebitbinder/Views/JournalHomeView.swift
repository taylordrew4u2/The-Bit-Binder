//
//  JournalHomeView.swift
//  thebitbinder
//
//  Section root for Daily Journal. Shows today's status, a calendar
//  heatmap of progress, and shortcuts into past entries & reminders.
//

import SwiftUI
import SwiftData

struct JournalHomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DailyJournalEntry.date, order: .reverse)
    private var entries: [DailyJournalEntry]

    @State private var showTodayEditor = false
    @State private var displayedMonth = Date()

    private var todayEntry: DailyJournalEntry? {
        let key = DailyJournalEntry.todayKey
        return entries.first { $0.dateKey == key }
    }

    private var todayIsComplete: Bool { todayEntry?.isComplete ?? false }

    /// Lookup of dateKey → isComplete for the currently displayed month.
    private var entryMap: [String: Bool] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.dateKey, $0.isComplete) })
    }

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
                JournalCalendarView(
                    displayedMonth: $displayedMonth,
                    entryMap: entryMap
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } header: {
                Text("Progress")
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

// MARK: - Calendar View

private struct JournalCalendarView: View {
    @Binding var displayedMonth: Date
    let entryMap: [String: Bool]

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private var monthYear: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }

        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        return days
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            // Month navigation
            HStack {
                Button {
                    withAnimation { shiftMonth(-1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .foregroundStyle(Color.bitbinderAccent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYear)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    withAnimation { shiftMonth(1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Color.bitbinderAccent)
                }
                .buttonStyle(.plain)
                .disabled(calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month))
            }
            .padding(.horizontal, 16)

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)

            // Day cells
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: 32)
                    }
                }
            }
            .padding(.horizontal, 12)

            // Legend
            HStack(spacing: 16) {
                legendDot(color: Color.bitbinderAccent, label: "Complete")
                legendDot(color: Color.bitbinderAccent.opacity(0.35), label: "Started")
                legendDot(color: Color(.tertiarySystemFill), label: "No entry")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let key = DailyJournalEntry.dateKey(for: date)
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()
        let status = entryMap[key]

        let bgColor: Color = {
            if let complete = status {
                return complete ? Color.bitbinderAccent : Color.bitbinderAccent.opacity(0.35)
            }
            return Color(.tertiarySystemFill)
        }()

        Text(dayFormatter.string(from: date))
            .font(.caption2.weight(isToday ? .bold : .regular))
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFuture ? Color.clear : bgColor)
            )
            .foregroundStyle(isFuture ? Color.secondary.opacity(0.4) : (status != nil ? Color.white : Color.primary))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.bitbinderAccent, lineWidth: isToday ? 1.5 : 0)
            )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private func shiftMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }
}

#Preview {
    NavigationStack { JournalHomeView() }
        .modelContainer(for: DailyJournalEntry.self, inMemory: true)
}
