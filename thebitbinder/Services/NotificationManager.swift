//
//  NotificationManager.swift
//  thebitbinder
//
//  Daily reminder notifications at a random time
//  within the user's configured window.
//

import Foundation
import UserNotifications

/// Notification manager - thread-safe via SwiftUI's @Published property dispatch.
/// UNUserNotificationCenterDelegate callbacks are already dispatched on main thread by the system.
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
        "stop treating the open mic like a therapy session and write something funny.",
        // — New messages —
        "Hey! Write one joke before your excuses unionize.",
        "You there! Finish the bit. It's been waiting.",
        "Psst! One new tag still counts as work.",
        "Listen! Open the app and earn your ego.",
        "Hey! That premise will not raise itself.",
        "Oi! Fix the punchline, not your lighting.",
        "You there! Write before the fake errands hit.",
        "Psst! One joke now, smugness later.",
        "Listen! Tighten the setup. Nobody owes it patience.",
        "Hey! Stop circling the bit like a raccoon.",
        "You there! Add the tag you know it needs.",
        "Oi! One rewrite. Be brave for six minutes.",
        "Psst! Turn that annoyance into usable material.",
        "Listen! A half-bit is still your responsibility.",
        "Hey! Finish one joke before starting four others.",
        "You there! Cut the fluff. Keep the laugh.",
        "Psst! The app is open. Be employable.",
        "Oi! Fix the weak line. You know the one.",
        "Listen! One premise. Three angles. Act professional.",
        "Hey! Make that joke less \"almost there.\"",
        "You there! Write one line worth stealing later.",
        "Psst! Stop thinking about the joke. Write it.",
        "Listen! Rewrite it like stage time depends on it.",
        "Hey! One good tag can save a lazy bit.",
        "Oi! Turn your complaint into a punchline already.",
        "You there! Make the setup shorter and the joke smarter.",
        "Psst! Rescue that idea from notes-app purgatory.",
        "Listen! Your best line hates being buried.",
        "Hey! Finish the joke before your standards get weird.",
        "You there! One ugly draft is still a draft.",
        "Oi! Fix the opener. The rest may follow.",
        "Psst! Give that punchline some basic dignity.",
        "Listen! One rewrite now saves panic later.",
        "Hey! Open the app and do your little craft.",
        "You there! Make that personal detail earn a laugh.",
        "Psst! Shorter setup. Bigger reward.",
        "Oi! One fresh joke beats twelve noble intentions.",
        "Listen! Trim the setup like rent is due.",
        "Hey! Write before the day gets fake important.",
        "You there! That bit still has money in it.",
        "Psst! Add a topper and stop being shy.",
        "Listen! Find the funny before the story takes over.",
        "Hey! One joke today keeps bombing artisanal.",
        "Oi! Rewrite the stale one. It knows what it did.",
        "You there! Make it sound like you, not filler.",
        "Psst! Push past the first obvious version.",
        "Listen! That weak tag is embarrassing both of you.",
        "Hey! Open the app and make one choice.",
        "You there! Turn that awkward moment into rent.",
        "Oi! Finish the bit. Closure is cute.",
        "Psst! Make the laugh happen sooner.",
        "Listen! One strong line can carry the whole thing.",
        "Hey! Stop protecting the premise. Test it.",
        "You there! Clean rewrite. Dirty thought. Go.",
        "Psst! Fix the joke you keep avoiding.",
        "Oi! Make that setup less needy.",
        "Listen! One new angle can wake up an old bit.",
        "Hey! Write one joke before the mood leaves.",
        "You there! Add a sharper word and move on.",
        "Psst! That idea deserves better than \"later.\"",
        "Listen! One finished joke beats ten flirty fragments.",
        "Hey! Give that ending a spine.",
        "Oi! The punchline needs more bite and less hope.",
        "You there! Write one line your future self will rob.",
        "Psst! Make that premise actually pull its weight.",
        "Listen! Shorter story. Smarter joke. Lesser ego.",
        "Hey! One rewrite is not a personality. Do it.",
        "You there! Fix the part where people drift away.",
        "Oi! Stop stalling and tag the damn bit.",
        "Psst! Open the app and act booked.",
        "Listen! The first draft was rude. Try again.",
        "Hey! Make that joke clearer, then meaner.",
        "You there! A joke in your head pays nothing.",
        "Psst! One better word could save the line.",
        "Oi! Give the old bit a new target.",
        "Listen! The laugh is usually one draft deeper.",
        "Hey! Write one joke before you overidentify with chaos.",
        "You there! Make the setup earn its ride.",
        "Psst! One real writing session beats a week of posing.",
        "Oi! Tighten it until it stops wandering.",
        "Listen! That premise has legs. Teach it direction.",
        "Hey! Fix the opener and stop being precious.",
        "You there! Add the tag. The joke is asking politely.",
        "Psst! Make one observation worth stage time.",
        "Oi! Rewrite it like you're saying it tonight.",
        "Listen! One decent joke is a real asset.",
        "Hey! Turn that bad memory into a tax write-off spiritually.",
        "You there! Stop saving the better angle for later.",
        "Psst! Clean up the setup and trust the hit.",
        "Oi! Your notes are full of cowards. Pick one.",
        "Listen! Find the strongest line and build there.",
        "Hey! Make the joke shorter and the confidence louder.",
        "You there! That half-bit still wants custody.",
        "Psst! One sharper tag and this thing lives.",
        "Oi! Fix the premise before blaming the audience.",
        "Listen! The app is open. Do your little miracle.",
        "Hey! Give that joke a real ending for once.",
        "You there! One punchline today is still momentum.",
        "Psst! Make the bit tighter than your schedule.",
        "Listen! Write one joke now and call it discipline."
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

    deinit {
        NotificationCenter.default.removeObserver(self, name: .NSSystemTimeZoneDidChange, object: nil)
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
                print(" [Notifications] schedule failed: \(error)")
            } else {
                print(" [Notifications] scheduled for \(hour):\(String(format: "%02d", minute)) tomorrow")
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
