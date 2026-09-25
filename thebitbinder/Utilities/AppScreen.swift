import Foundation

enum AppScreen: String, CaseIterable {
    case home = "Home"
    case brainstorm = "Brainstorm"
    case jokes = "Jokes"
    case sets = "Sets"
    case recordings = "Recordings"
    case notebookSaver = "Photo Notebook"
    case settings = "Settings"

    static var roastScreens: [AppScreen] {
        [.jokes]
    }

    // Default screens for the tab bar when no custom selection exists
    static var defaultTabBarScreens: [AppScreen] {
        [.home, .jokes, .sets, .notebookSaver]
    }

    static var defaultRoastTabBarScreens: [AppScreen] {
        [.jokes]
    }

    /// Ordered list of all screens that can appear in the tab bar.
    /// Used to maintain a stable ordering regardless of selection order.
    static var tabBarOrder: [AppScreen] {
        [.home, .brainstorm, .jokes, .sets, .recordings, .notebookSaver]
    }

    /// Returns visible tabs for the current mode.
    /// Roast Mode intentionally exposes only Roasts until the user exits it.
    /// Standard mode uses the user's custom tab selection plus Settings.
    static func customTabBarScreens(from raw: String, roastMode: Bool) -> [AppScreen] {
        if roastMode {
            return defaultRoastTabBarScreens
        }

        let defaults = defaultTabBarScreens
        guard !raw.isEmpty else { return defaults + [.settings] }

        let selected = Set(raw.split(separator: ",").compactMap { AppScreen(rawValue: String($0)) })
        // Filter to ordered list, always include Settings at the end
        let ordered = tabBarOrder.filter { selected.contains($0) }
        return (ordered.isEmpty ? defaults : ordered) + [.settings]
    }

    /// An assistant destination can be visible for this visit without changing saved tabs.
    static func visibleTabs(from raw: String, roastMode: Bool, temporaryTab: AppScreen?) -> [AppScreen] {
        let configured = customTabBarScreens(from: raw, roastMode: roastMode)
        guard !roastMode, let temporaryTab, !configured.contains(temporaryTab) else { return configured }
        return (tabBarOrder + [.settings]).filter { configured.contains($0) || $0 == temporaryTab }
    }

    static func resolvedSelection(raw: String, visibleTabs: [AppScreen], firstLaunch: Bool = false) -> AppScreen {
        precondition(!visibleTabs.isEmpty, "The app must always have a visible tab")
        if firstLaunch, visibleTabs.contains(.home) { return .home }
        if let stored = AppScreen(rawValue: raw), visibleTabs.contains(stored) { return stored }
        return visibleTabs[0]
    }
}
