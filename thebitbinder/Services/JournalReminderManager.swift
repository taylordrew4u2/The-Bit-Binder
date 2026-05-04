//
//  JournalReminderManager.swift
//  thebitbinder
//
//  Daily local notification reminding the user to fill in their journal.
//  Skipped automatically if today's entry is already complete.
//

import Foundation
import SwiftData
import UserNotifications

/// Preferences are stored via `iCloudKeyValueStore` so reminder time roams
/// across devices like the existing daily writing reminder.
@MainActor
final class JournalReminderManager: NSObject, ObservableObject {

    static let shared = JournalReminderManager()

    private let kvStore = iCloudKeyValueStore.shared
    private let notifID = "The-BitBinder.thebitbinder.journalReminder"

    // MARK: - Published state

    @Published var isEnabled: Bool {
        didSet {
            kvStore.set(isEnabled, forKey: SyncedKeys.journalReminderEnabled)
            if isEnabled {
                requestPermissionAndSchedule()
            } else {
                cancelAll()
            }
        }
    }

    /// Reminder time as minutes from midnight. Default 21:00 (9 PM).
    @Published var reminderMinute: Int {
        didSet {
            kvStore.set(reminderMinute, forKey: SyncedKeys.journalReminderMinute)
            rescheduleIfEnabled()
        }
    }

    // MARK: - Init

    private override init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: SyncedKeys.journalReminderEnabled)
        self.reminderMinute = defaults.object(forKey: SyncedKeys.journalReminderMinute) as? Int ?? (21 * 60)
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timezoneDidChange),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
    }

    // MARK: - Public API

    /// Safe to call on every app launch / foreground. No-op if already scheduled.
    func scheduleIfNeeded() {
        guard isEnabled else { return }
        let id = notifID
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            let alreadyScheduled = requests.contains { $0.identifier == id }
            if !alreadyScheduled {
                Task { @MainActor in self?.scheduleDaily() }
            }
        }
    }

    func rescheduleIfEnabled() {
        guard isEnabled else { return }
        cancelAll()
        scheduleDaily()
    }

    /// Cancel the pending reminder if today's entry is complete.
    /// Called right after the user completes their entry so they don't get
    /// pinged later the same evening.
    func cancelTodayIfComplete(context: ModelContext) {
        guard isEnabled else { return }
        if DailyJournalStore.isTodayComplete(in: context) {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [notifID])
        }
    }

    // MARK: - Permission

    private func requestPermissionAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            Task { @MainActor in self?.scheduleDaily() }
        }
    }

    // MARK: - Scheduling

    private func scheduleDaily() {
        let content = UNMutableNotificationContent()
        content.title = "Daily Journal"
        content.body = "Take a minute to log today's journal."
        content.sound = .default

        let hour = reminderMinute / 60
        let minute = reminderMinute % 60

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        // Repeating daily trigger. We check completion at delivery time via the
        // system's UNUserNotificationCenterDelegate (see `willPresent`) and also
        // remove today's delivered reminder as soon as the user finishes.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: notifID, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print(" [JournalReminder] schedule failed: \(error)")
            }
        }
    }

    private func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notifID])
        center.removeDeliveredNotifications(withIdentifiers: [notifID])
    }

    // MARK: - Observers

    @objc nonisolated private func timezoneDidChange() {
        Task { @MainActor [weak self] in self?.rescheduleIfEnabled() }
    }

    /// Stable identifier so other code can suppress the banner if today is
    /// already complete when the notification fires in the foreground.
    var notificationIdentifier: String { notifID }
}
