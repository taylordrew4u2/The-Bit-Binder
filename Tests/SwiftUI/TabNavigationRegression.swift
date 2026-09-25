import Foundation

@main
struct TabNavigationRegression {
    static func main() {
        let defaults = AppScreen.visibleTabs(from: "", roastMode: false, temporaryTab: nil)
        precondition(defaults == [.home, .jokes, .sets, .notebookSaver, .settings])

        // Every combination of saved tabs must have a valid selection, even if
        // preferences contain an old value or Home was removed during setup.
        let choices = AppScreen.tabBarOrder
        for mask in 0..<(1 << choices.count) {
            let raw = choices.enumerated().compactMap { index, screen in
                mask & (1 << index) == 0 ? nil : screen.rawValue
            }.joined(separator: ",")
            for roastMode in [false, true] {
                let tabs = AppScreen.visibleTabs(from: raw, roastMode: roastMode, temporaryTab: nil)
                for stored in AppScreen.allCases.map(\.rawValue) + ["Old screen", ""] {
                    for firstLaunch in [false, true] {
                        let selected = AppScreen.resolvedSelection(
                            raw: stored, visibleTabs: tabs, firstLaunch: firstLaunch
                        )
                        precondition(tabs.contains(selected))
                    }
                }
            }

            // Assistant navigation must expose every standard destination
            // without mutating the saved customization or duplicating a tab.
            let configured = AppScreen.customTabBarScreens(from: raw, roastMode: false)
            for destination in AppScreen.allCases {
                let tabs = AppScreen.visibleTabs(from: raw, roastMode: false, temporaryTab: destination)
                precondition(tabs.contains(destination))
                precondition(Set(tabs).count == tabs.count)
                precondition(tabs.last == .settings)
                precondition(AppScreen.resolvedSelection(raw: destination.rawValue, visibleTabs: tabs) == destination)
                precondition(AppScreen.visibleTabs(from: raw, roastMode: false, temporaryTab: nil) == configured)
                precondition(AppScreen.visibleTabs(from: raw, roastMode: true, temporaryTab: destination) == [.jokes])
            }
        }

        let withoutHome = AppScreen.visibleTabs(from: "Jokes,Sets", roastMode: false, temporaryTab: nil)
        precondition(AppScreen.resolvedSelection(raw: "Photo Notebook", visibleTabs: withoutHome) == .jokes)
        precondition(AppScreen.resolvedSelection(raw: "Home", visibleTabs: withoutHome, firstLaunch: true) == .jokes)
        print("Tab navigation regression checks passed")
    }
}
