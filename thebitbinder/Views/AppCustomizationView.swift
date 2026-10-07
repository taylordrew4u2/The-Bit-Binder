import SwiftUI

/// Direct preferences for returning users. Existing storage keys keep their choices intact.
struct AppCustomizationView: View {
    @EnvironmentObject private var userPreferences: UserPreferences
    @AppStorage("appTextSize") private var textSizeRaw = AppTextSize.system.rawValue
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("setupSelectedTabs") private var selectedTabsRaw = ""
    @AppStorage("jokesViewMode") private var jokesViewMode: JokesViewMode = .grid
    @AppStorage("showFullContent") private var showPreviews = true

    private var selectedTabs: Set<AppScreen> {
        Set(AppScreen.customTabBarScreens(from: selectedTabsRaw, roastMode: false)).union([.jokes])
    }

    var body: some View {
        Form {
            Section {
                Picker("Text Size", selection: Binding(
                    get: { AppTextSize(rawValue: textSizeRaw) ?? .system },
                    set: { textSizeRaw = $0.rawValue }
                )) {
                    ForEach(AppTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                Toggle("Roast Mode", isOn: $roastMode)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your device's text size. Accessibility sizes always take priority. Roast Mode groups material by subject.")
            }

            Section {
                ForEach(AppScreen.tabBarOrder, id: \.self) { screen in
                    Toggle(isOn: tabBinding(for: screen)) {
                        Label(screen.displayName, systemImage: screen.icon)
                    }
                    .disabled(screen == .jokes)
                }
            } header: {
                Text("Navigation")
            } footer: {
                Text("Choose your standard-mode tabs. Jokes and Settings stay available. Extra tabs appear in More on smaller screens.")
            }

            Section {
                Picker("Joke Layout", selection: $jokesViewMode) {
                    Text("List").tag(JokesViewMode.list)
                    Text("Grid").tag(JokesViewMode.grid)
                }
                Toggle("Show Previews", isOn: $showPreviews)
                Toggle("BitBuddy", isOn: $userPreferences.bitBuddyEnabled)
            } header: {
                Text("Writing")
            } footer: {
                Text("Previews show a short excerpt in your library. Sets always let you read the full joke. BitBuddy offers writing help and punch-up suggestions.")
            }

            Section("Privacy") {
                NavigationLink {
                    iCloudSyncSettingsView()
                } label: {
                    Label("iCloud Sync", systemImage: "icloud")
                }
                NavigationLink {
                    DataSafetyView()
                } label: {
                    Label("Privacy & Data Safety", systemImage: "shield.checkered")
                }
            }
        }
        .navigationTitle("Customize App")
        .navigationBarTitleDisplayMode(.inline)
        .readableWidth()
    }

    private func tabBinding(for screen: AppScreen) -> Binding<Bool> {
        Binding(
            get: { selectedTabs.contains(screen) },
            set: { isSelected in
                guard screen != .jokes else { return }
                var selection = selectedTabs
                if isSelected { selection.insert(screen) } else { selection.remove(screen) }
                selectedTabsRaw = AppScreen.tabBarOrder.filter { selection.contains($0) }
                    .map(\.rawValue).joined(separator: ",")
            }
        )
    }
}

#Preview {
    NavigationStack {
        AppCustomizationView()
    }
    .environmentObject(UserPreferences())
}
