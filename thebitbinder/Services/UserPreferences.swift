import Foundation

@MainActor
final class UserPreferences: ObservableObject {
    private var openAIKeyStore = OpenAIKeychainStore.shared

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

    @Published var openAIAPIKey: String {
        didSet {
            openAIKeyStore.apiKey = openAIAPIKey
        }
    }

    init() {
        self.userName = UserDefaults.standard.string(forKey: "userName") ?? "there"
        let stored = UserDefaults.standard.object(forKey: "bitBuddyEnabled")
        self.bitBuddyEnabled = (stored as? Bool) ?? true
        self.openAIAPIKey = openAIKeyStore.migrateLegacyValueIfNeeded()
    }
}
