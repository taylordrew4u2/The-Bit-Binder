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
    }
}
