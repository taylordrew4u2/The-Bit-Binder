import Foundation

@MainActor
final class UserPreferences: ObservableObject {

    @Published var userName: String {
        didSet {
            UserDefaults.standard.set(userName, forKey: "userName")
        }
    }

    @Published var bitBuddyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(bitBuddyEnabled, forKey: "bitBuddyEnabled")
        }
    }

    init() {
        self.userName = UserDefaults.standard.string(forKey: "userName") ?? "there"
        let stored = UserDefaults.standard.object(forKey: "bitBuddyEnabled")
        self.bitBuddyEnabled = (stored as? Bool) ?? true

        // When another device changes these via iCloud key-value sync, the new
        // values arrive in UserDefaults but this long-lived object won't notice
        // on its own. Refresh from local defaults so the name (and BitBuddy
        // toggle) update live instead of only after a relaunch.
        NotificationCenter.default.addObserver(
            forName: .iCloudKVDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadFromDefaults() }
        }
    }

    /// Reloads synced values from UserDefaults without pushing them back out.
    /// Only assigns when the value actually differs to avoid redundant writes.
    private func reloadFromDefaults() {
        let name = UserDefaults.standard.string(forKey: "userName") ?? "there"
        if name != userName { userName = name }

        let enabled = (UserDefaults.standard.object(forKey: "bitBuddyEnabled") as? Bool) ?? true
        if enabled != bitBuddyEnabled { bitBuddyEnabled = enabled }
    }
}
