import Foundation

enum AppDeepLinkKeys {
    static let settingsDestination = "bitbuddy.settings.destination"
}

enum AppDeepLinkDestination: String, Identifiable {
    case helpFAQ

    var id: String { rawValue }
}

enum AppDeepLinkStore {
    static func setSettingsDestination(_ destination: AppDeepLinkDestination) {
        UserDefaults.standard.set(destination.rawValue, forKey: AppDeepLinkKeys.settingsDestination)
    }

    static func consumeSettingsDestination() -> AppDeepLinkDestination? {
        guard let raw = UserDefaults.standard.string(forKey: AppDeepLinkKeys.settingsDestination),
              let destination = AppDeepLinkDestination(rawValue: raw) else {
            return nil
        }

        UserDefaults.standard.removeObject(forKey: AppDeepLinkKeys.settingsDestination)
        return destination
    }
}
