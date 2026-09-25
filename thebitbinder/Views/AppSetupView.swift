//
//  AppSetupView.swift
//  thebitbinder
//
//  First-launch setup with a compatibility route to direct preferences.
//  Native iOS style: system blue, white background, clean typography.
//

import SwiftUI

struct AppSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userPreferences: UserPreferences
    @StateObject private var syncService = iCloudSyncService.shared

    // Persisted preferences
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("jokesViewMode") private var jokesViewMode: JokesViewMode = .grid
    @AppStorage("setupSelectedTabs") private var selectedTabsRaw: String = ""
    @AppStorage("homeSelectedSections") private var selectedHomeSectionsRaw: String = ""
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    // Local state
    @State private var currentPage = 0
    @State private var nameText = ""
    @State private var selectedTabs: Set<AppScreen> = []
    @State private var selectedHomeSections: Set<HomeSection> = []
    @State private var iCloudSyncEnabled = false

    /// Existing callers can open direct preferences without repeating onboarding.
    var isFirstLaunch: Bool = true

    // All configurable tabs (excluding Settings — always shown)
    private let configurableTabs: [AppScreen] = [
        .home, .brainstorm, .jokes, .sets, .recordings, .notebookSaver
    ]

    private let defaultTabs: Set<AppScreen> = [.home, .jokes, .sets, .notebookSaver]

    // First launch keeps only the essential steps; tabs/home/layout default
    // to sensible values and stay editable later in Settings.
    private let pageCount = 4

    var body: some View {
        if isFirstLaunch {
            onboarding
        } else {
            AppCustomizationView()
        }
    }

    private var onboarding: some View {
        VStack(spacing: 0) {
            // Progress dots, with an optional Skip on first launch
            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                if isFirstLaunch && currentPage < pageCount - 1 {
                    HStack {
                        Spacer()
                        Button("Skip") { finishSetup() }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 20)
                    }
                }
            }
            .padding(.top, 16)

            TabView(selection: $currentPage) {
                welcomePage.readableWidth().tag(0)
                privacyPage.readableWidth().tag(1)
                namePage.readableWidth().tag(2)
                readyPage.readableWidth().tag(3)
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
                        .background(ActionColors.blue)
                        .foregroundStyle(ActionColors.foreground)
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
                            .background(ActionColors.blue)
                            .foregroundStyle(ActionColors.foreground)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .interactiveDismissDisabled(isFirstLaunch)
        .onAppear {
            nameText = userPreferences.userName == "there" ? "" : userPreferences.userName
            loadSelectedTabs()
            loadSelectedHomeSections()
            iCloudSyncEnabled = syncService.isSyncEnabled
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

    private var privacyPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Start With Clear Data Rules")
                    .font(.title2.bold())

                Text("BitBinder stores your material on this device by default. Sync and cloud AI are both optional.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                VStack(spacing: 12) {
                    privacyFactRow(
                        icon: "iphone",
                        title: "Local First",
                        detail: "Your jokes, recordings, and notes stay on this device unless you turn on a cloud feature."
                    )
                    privacyFactRow(
                        icon: "icloud",
                        title: "Optional iCloud Sync",
                        detail: "Turn this on if you want your library synced through your private iCloud account."
                    )
                    privacyFactRow(
                        icon: "sparkles.rectangle.stack",
                        title: "AI Stays Optional",
                        detail: "On-device tools are preferred. Cloud AI is only used when you choose to configure a cloud provider."
                    )
                }
                .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    Toggle(isOn: $iCloudSyncEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable iCloud Sync")
                                .font(.body)
                            Text("Off by default for new installs")
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
                    summaryRow(icon: "icloud", label: "iCloud Sync", value: iCloudSyncEnabled ? "On" : "Off")
                    Divider().padding(.leading, 56)
                    summaryRow(icon: "dock.rectangle", label: "Tabs", value: "\(selectedTabs.count) selected")
                    Divider().padding(.leading, 56)
                    summaryRow(icon: "house", label: "Home", value: "\(selectedHomeSections.count) sections")
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

    private func privacyFactRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

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

    private func loadSelectedHomeSections() {
        if selectedHomeSectionsRaw.isEmpty {
            selectedHomeSections = Set(HomeSection.allCases)
        } else {
            let raw = selectedHomeSectionsRaw.split(separator: ",").map(String.init)
            selectedHomeSections = Set(raw.compactMap { HomeSection(rawValue: $0) })
            if selectedHomeSections.isEmpty {
                selectedHomeSections = Set(HomeSection.allCases)
            }
        }
    }

    private func saveSelectedTabs() {
        selectedTabsRaw = configurableTabs.filter { selectedTabs.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    private func saveSelectedHomeSections() {
        selectedHomeSectionsRaw = HomeSection.allCases.filter { selectedHomeSections.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    private func finishSetup() {
        saveNameIfNeeded()
        saveSelectedTabs()
        saveSelectedHomeSections()
        applyPrivacyPreferences()
        hasCompletedSetup = true
        dismiss()
    }

    private func applyPrivacyPreferences() {
        Task { @MainActor in
            if iCloudSyncEnabled {
                await syncService.enableiCloudSync()
            } else {
                syncService.disableiCloudSync()
            }
        }
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
