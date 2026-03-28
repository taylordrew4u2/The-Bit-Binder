//
//  NotificationManager.swift
//  thebitbinder
//
//  Daily reminder notifications at a random time
//  within the user's configured window.
//

import Foundation
import UserNotifications

final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()
    
    private let kvStore = iCloudKeyValueStore.shared

    // MARK: - Published state

    @Published var isEnabled: Bool {
        didSet {
            kvStore.set(isEnabled, forKey: SyncedKeys.dailyNotificationsEnabled)
            if isEnabled {
                requestPermissionAndSchedule()
            } else {
                cancelAll()
            }
        }
    }

    // Start / end stored as minutes‑from‑midnight (e.g. 600 = 10:00 AM)
    @Published var startMinute: Int {
        didSet {
            kvStore.set(startMinute, forKey: SyncedKeys.dailyNotifStartMinute)
            rescheduleIfEnabled()
        }
    }
    @Published var endMinute: Int {
        didSet {
            kvStore.set(endMinute, forKey: SyncedKeys.dailyNotifEndMinute)
            rescheduleIfEnabled()
        }
    }

    // MARK: - Constants

    private let notifID = "The-BitBinder.thebitbinder.dailyReminder"

    static let reminderMessages: [String] = [
        "Stop working on your manifesto and get back to writing a new set",
        "Get up and go to the open mic. Or at least prep some jokes to try. You can't riff deal with it",
        "Someone just called you \"brave\" for doing stand up. go fix your tight five, hero.",
        "Work on your jokes and give your wrist a break for the love of…",
        "Just because you're the funny friend doesn't mean you're getting booked more…",
        "That guy from the open mic just got up at the cellar. Wyd?",
        "stop gooning to your own podcast clips and write a premise that lands.",
        "your crowd work is just you bullying people who make more money than you. write a real joke.",
        "tiktok views aren't a career. go bomb at an open mic like a man.",
        "you're one bad set away from being a diversity hire at buzzfeed. get to the club.",
        "the only thing bombing harder than gaza is your opener. rewrite it.",
        "stop treating the open mic like a therapy session and write something funny."
    ]

    // MARK: - Init

    private override init() {
        // Read from iCloud-synced store
        self.isEnabled   = UserDefaults.standard.bool(forKey: SyncedKeys.dailyNotificationsEnabled)
        self.startMinute = UserDefaults.standard.object(forKey: SyncedKeys.dailyNotifStartMinute) as? Int ?? 600   // 10:00 AM
        self.endMinute   = UserDefaults.standard.object(forKey: SyncedKeys.dailyNotifEndMinute)   as? Int ?? 1320  // 10:00 PM
        super.init()

        UNUserNotificationCenter.current().delegate = self

        // Re-schedule when timezone changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timezoneDidChange),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
    }

    // MARK: - Public API

    /// Call once on app launch / didBecomeActive
    func scheduleIfNeeded() {
        guard isEnabled else { return }
        // Only schedule if there isn't one already pending
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] reqs in
            guard let self else { return }
            let hasPending = reqs.contains { $0.identifier == self.notifID }
            if !hasPending {
                self.scheduleNext()
            }
        }
    }

    /// Force a fresh schedule (removes old, creates new)
    func rescheduleIfEnabled() {
        guard isEnabled else { return }
        cancelAll()
        scheduleNext()
    }

    // MARK: - Permission

    private func requestPermissionAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard granted, let self else { return }
            self.scheduleNext()
        }
    }

    // MARK: - Scheduling

    private func scheduleNext() {
        let content = UNMutableNotificationContent()
        content.title = "BitBinder"
        content.body  = Self.reminderMessages.randomElement() ?? "Write some jokes."
        content.sound = .default

        // Build trigger date: tomorrow at a random minute within the window
        let cal = Calendar.current
        let now = Date()
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return }

        let start = startMinute
        var end   = endMinute
        if start >= end { end = start + 60 }                     // safety: at least 1-hour window
        let randomMinute = Int.random(in: start..<end)           // minutes from midnight
        let hour   = randomMinute / 60
        let minute = randomMinute % 60

        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour   = hour
        comps.minute = minute
        comps.second = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: notifID, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("❌ [Notifications] schedule failed: \(error)")
            } else {
                print("✅ [Notifications] scheduled for \(hour):\(String(format: "%02d", minute)) tomorrow")
            }
        }
    }

    // MARK: - Cancel

    private func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notifID])
    }

    // MARK: - Observers

    @objc private func timezoneDidChange() {
        rescheduleIfEnabled()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Notification tapped — reschedule next one
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == notifID {
            rescheduleIfEnabled()
        }
        completionHandler()
    }

    /// Show notification even while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
