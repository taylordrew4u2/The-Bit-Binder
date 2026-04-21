//
//  JournalReminderSettingsView.swift
//  thebitbinder
//
//  Settings for the Daily Journal end-of-day reminder.
//

import SwiftUI

struct JournalReminderSettingsView: View {
    @ObservedObject private var manager = JournalReminderManager.shared

    private var reminderTime: Binding<Date> {
        Binding(
            get: { dateFromMinutes(manager.reminderMinute) },
            set: { manager.reminderMinute = minutesFromDate($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $manager.isEnabled) {
                    Label("Daily Reminder", systemImage: "bell")
                }
                if manager.isEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("If today's journal is already complete, we skip the reminder. If notifications are off, you'll still see a gentle prompt inside the app.")
            }
        }
        .navigationTitle("Journal Reminder")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dateFromMinutes(_ mins: Int) -> Date {
        Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

#Preview {
    NavigationStack { JournalReminderSettingsView() }
}
