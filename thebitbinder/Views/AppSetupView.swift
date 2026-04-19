//
//  AppSetupView.swift
//  thebitbinder
//
//  First-launch setup wizard and re-configurable preferences.
//  Native iOS style: system blue, white background, clean typography.
//

import SwiftUI

struct AppSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userPreferences: UserPreferences

    // Persisted preferences
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("jokesViewMode") private var jokesViewMode: JokesViewMode = .grid
    @AppStorage("showFullContent") private var showFullContent = true
    @AppStorage("setupSelectedTabs") private var selectedTabsRaw: String = ""
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    // Local state
    @State private var currentPage = 0
    @State private var nameText = ""
    @State private var selectedTabs: Set<AppScreen> = []

    /// When true, presented as the first-launch onboarding. When false,
    /// it's opened from Settings so we skip the welcome page.
    var isFirstLaunch: Bool = true

    // All configurable tabs (excluding Settings — always shown)
    private let configurableTabs: [AppScreen] = [
        .home, .brainstorm, .jokes, .sets, .recordings, .notebookSaver
    ]

    private let defaultTabs: Set<AppScreen> = [.home, .jokes, .sets, .notebookSaver]

    private var pageCount: Int { isFirstLaunch ? 5 : 4 }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 16)

            TabView(selection: $currentPage) {
                if isFirstLaunch {
                    welcomePage.tag(0)
                    namePage.tag(1)
                    tabsPage.tag(2)
                    jokeViewPage.tag(3)
                    readyPage.tag(4)
                } else {
                    namePage.tag(0)
                    tabsPage.tag(1)
                    jokeViewPage.tag(2)
                    readyPage.tag(3)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Navigation
            HStack {
                if currentPage > 0 {
                    Button {
                        withAnimation { currentPage -= 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                } else {
                    Spacer().frame(width: 80)
                }

                Spacer()

                if currentPage < pageCount - 1 {
                    Button {
                        withAnimation { currentPage += 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                } else {
                    Button {
                        finishSetup()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled(isFirstLaunch)
        .onAppear {
            nameText = userPreferences.userName == "there" ? "" : userPreferences.userName
            loadSelectedTabs()
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "text.quote")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)

                Text("Welcome to BitBinder")
                    .font(.largeTitle.bold())

                Text("Your comedy writing toolkit.\nLet's set things up the way you like.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer(minLength: 60)
            }
        }
    }

    private var namePage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "person.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("What should we call you?")
                    .font(.title2.bold())

                TextField("Your name", text: $nameText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
                    .padding(.horizontal, 40)
                    .submitLabel(.done)
                    .onSubmit {
                        saveNameIfNeeded()
                    }

                Text("This shows on your Home screen greeting.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer(minLength: 60)
            }
        }
        .onChange(of: nameText) { _, _ in
            saveNameIfNeeded()
        }
    }

    private var tabsPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "dock.rectangle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Choose Your Tabs")
                    .font(.title2.bold())

                Text("Pick which sections appear in your bottom bar.\nYou can always change this later.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 0) {
                    ForEach(configurableTabs, id: \.self) { screen in
                        tabRow(for: screen)
                        if screen != configurableTabs.last {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Settings is always available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Roast mode toggle
                VStack(spacing: 0) {
                    Toggle(isOn: $roastMode) {
                        Label("Roast Mode", systemImage: "flame.fill")
                            .font(.body)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                Text("Roast Mode organizes material by target instead of folder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)

                Spacer(minLength: 60)
            }
        }
    }

    private var jokeViewPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                Image(systemName: "rectangle.grid.1x2")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("How Do You Want to See Jokes?")
                    .font(.title2.bold())

                // View mode picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Layout")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 12) {
                        viewModeCard(mode: .list, icon: "list.bullet", title: "List")
                        viewModeCard(mode: .grid, icon: "square.grid.2x2", title: "Grid")
                    }
                }
                .padding(.horizontal, 20)

                // Content preview toggle
                VStack(spacing: 0) {
                    Toggle(isOn: $showFullContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Full Content")
                                .font(.body)
                            Text("Display joke text in lists and cards")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                Spacer(minLength: 60)
            }
        }
    }

    private var readyPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundColor(.green)

                Text("You're All Set")
                    .font(.largeTitle.bold())

                Text("You can change any of these settings\nanytime in Settings.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Summary
                VStack(spacing: 0) {
                    summaryRow(icon: "person.circle", label: "Name", value: nameText.isEmpty ? "Not set" : nameText)
                    Divider().padding(.leading, 56)
                    summaryRow(icon: "dock.rectangle", label: "Tabs", value: "\(selectedTabs.count) selected")
                    Divider().padding(.leading, 56)
                    summaryRow(icon: jokesViewMode.icon, label: "Joke View", value: jokesViewMode.rawValue)
                    Divider().padding(.leading, 56)
                    summaryRow(icon: "flame", label: "Roast Mode", value: roastMode ? "On" : "Off")
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Components

    private func tabRow(for screen: AppScreen) -> some View {
        let isSelected = selectedTabs.contains(screen)
        return Button {
            if isSelected {
                // Don't allow deselecting Jokes — it's required
                if screen != .jokes {
                    selectedTabs.remove(screen)
                }
            } else {
                // Max 5 tabs (iOS tab bar limit)
                if selectedTabs.count < 5 {
                    selectedTabs.insert(screen)
                }
            }
            saveSelectedTabs()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? screen.selectedIcon : screen.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(screen.rawValue)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(tabDescription(for: screen))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : Color(UIColor.tertiaryLabel))
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func viewModeCard(mode: JokesViewMode, icon: String, title: String) -> some View {
        let isSelected = jokesViewMode == mode
        return Button {
            jokesViewMode = mode
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func tabDescription(for screen: AppScreen) -> String {
        switch screen {
        case .home:          return "Dashboard with stats and quick actions"
        case .brainstorm:    return "Freeform ideas and premises"
        case .jokes:         return "Your joke library (always included)"
        case .sets:          return "Set lists for performances"
        case .recordings:    return "Audio recordings and transcriptions"
        case .notebookSaver: return "Photos and scanned notes"
        case .settings:      return ""
        }
    }

    private func saveNameIfNeeded() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userPreferences.userName = trimmed
        }
    }

    private func loadSelectedTabs() {
        if selectedTabsRaw.isEmpty {
            selectedTabs = defaultTabs
        } else {
            let raw = selectedTabsRaw.split(separator: ",").map(String.init)
            selectedTabs = Set(raw.compactMap { AppScreen(rawValue: $0) })
            // Ensure Jokes is always included
            selectedTabs.insert(.jokes)
        }
    }

    private func saveSelectedTabs() {
        selectedTabsRaw = selectedTabs.map(\.rawValue).joined(separator: ",")
    }

    private func finishSetup() {
        saveNameIfNeeded()
        saveSelectedTabs()
        hasCompletedSetup = true
        dismiss()
    }
}

#Preview("First Launch") {
    AppSetupView(isFirstLaunch: true)
        .environmentObject(UserPreferences())
}

#Preview("From Settings") {
    NavigationStack {
        AppSetupView(isFirstLaunch: false)
            .environmentObject(UserPreferences())
    }
}
