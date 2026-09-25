//
//  ContentView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var takeoverProgress: CGFloat = 0
    @State private var showTakeover = false
    @State private var previousRoastMode = false

    var body: some View {
        ZStack {
            MainTabView()
                .preferredColorScheme(roastMode ? .dark : nil)

            if showTakeover {
                RoastTakeoverOverlay(progress: takeoverProgress, entering: roastMode)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: roastMode) { _, entering in
            guard previousRoastMode != entering else { return }
            previousRoastMode = entering
            runTakeover()
        }
        .onAppear {
            previousRoastMode = roastMode
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                showTakeover = false
                takeoverProgress = 0
            }
        }
    }

    private func runTakeover() {
        if reduceMotion || scenePhase != .active {
            return
        }
        showTakeover = true
        takeoverProgress = 0
        haptic(.medium)
        withAnimation(.easeIn(duration: 0.45)) {
            takeoverProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showTakeover = false
            takeoverProgress = 0
        }
    }
}

/// Flame-wipe overlay that sweeps upward during roast mode transitions.
struct RoastTakeoverOverlay: View {
    let progress: CGFloat
    let entering: Bool

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let charredHeight = progress * h

            ZStack {
                // Charred region
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, entering ? FirePalette.bg2 : Color(UIColor.systemBackground).opacity(0.9), entering ? FirePalette.bg : Color(UIColor.systemBackground)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: charredHeight)
                }

                // Flame front
                if progress > 0 && progress < 1 {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: max(0, h - charredHeight - 60))
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, FirePalette.bright.opacity(0.4), FirePalette.core, Color(red: 0.91, green: 0.27, blue: 0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 120)
                            .blur(radius: 6)
                        Spacer()
                    }
                }

                // Badge bloom at center
                if progress >= 0.35 && progress < 0.95 {
                    RoastModeBadge(lit: entering)
                        .scaleEffect(0.6 + (progress - 0.35) * 1.2)
                        .opacity(Double(min(1, (progress - 0.3) * 3)))
                }
            }
        }
    }
}

// MARK: - App Screens

extension AppScreen {
    /// Maps the active tab to BitBuddy's section enum so the chatbot knows
    /// which page the user is on when they ask a question. Returns nil for
    /// .home — Home is a meta-page (overview), and the assistant should rely
    /// on routing instead of pretending it's "in" a feature area.
    var bitBuddySection: BitBuddySection? {
        switch self {
        case .home:          return nil
        case .brainstorm:    return .brainstorm
        case .jokes:         return .jokes
        case .sets:          return .setLists
        case .recordings:    return .recordings
        case .notebookSaver: return .notebook
        case .settings:      return .settings
        }
    }

    /// User-facing tab label. Kept separate from `rawValue` because the raw
    /// value backs persisted tab selections (`selectedTabRawValue`,
    /// `setupSelectedTabs`) and must stay stable even when the label changes.
    var displayName: String {
        switch self {
        case .notebookSaver: return "Notepad"
        default:             return rawValue
        }
    }

    var icon: String {
        switch self {
        case .home:          return "house"
        case .brainstorm:    return "lightbulb"
        case .jokes:         return "text.quote"
        case .sets:          return "list.bullet.rectangle.portrait"
        case .recordings:    return "waveform"
        case .notebookSaver: return "note.text"
        case .settings:      return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home:          return "house.fill"
        case .brainstorm:    return "lightbulb.fill"
        case .jokes:         return "text.quote"
        case .sets:          return "list.bullet.rectangle.portrait.fill"
        case .recordings:    return "waveform"
        case .notebookSaver: return "note.text"
        case .settings:      return "gearshape.fill"
        }
    }

    var roastName: String {
        switch self {
        case .home:          return "Home"
        case .brainstorm:    return "Ideas"
        case .jokes:         return "Roasts"
        case .sets:          return "Roast Sets"
        case .recordings:    return "Recordings"
        case .notebookSaver: return "Notepad"
        case .settings:      return "Settings"
        }
    }

    var roastIcon: String {
        switch self {
        case .jokes:         return "flame"
        default:             return icon
        }
    }
    
    var roastSelectedIcon: String {
        switch self {
        case .jokes:         return "flame.fill"
        default:             return selectedIcon
        }
    }

    var color: Color {
        // Use system accent color for consistency
        return .accentColor
    }

    var roastColor: Color {
        switch self {
        case .jokes:         return .accentColor
        default:             return .accentColor
        }
    }
    
}

// MARK: - Main Tab View (Standard iOS TabView)

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    // Persist the selected tab across app launches
    @AppStorage("selectedTabRawValue") private var selectedTabRaw: String = AppScreen.home.rawValue
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup: Bool = false
    @AppStorage("setupSelectedTabs") private var setupSelectedTabs: String = ""
    @State private var assistantTab: AppScreen?
    @State private var showSetup = false
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var userPreferences: UserPreferences
    @ObservedObject private var audioService = AudioRecordingService.shared

    // BitBuddy side drawer — replaces the old .sheet so users can chat
    // alongside whatever they're working on.
    @StateObject private var bitBuddyDrawer = BitBuddyDrawerController()
    @StateObject private var bitBuddyPresenter = BitBuddyPresentationController()

    // Draggable BitBuddy position (persisted)
    @AppStorage("bitBuddyX") private var bitBuddyX: Double = -1
    @AppStorage("bitBuddyY") private var bitBuddyY: Double = -1
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var showingGlobalRecordingSave = false
    @State private var globalRecordingName = ""
    @State private var globalRecordingURL: URL?
    @State private var globalRecordingDuration: TimeInterval = 0
    @State private var globalRecordingError: String?
    @State private var showingGlobalRecordingError = false

    // Computed binding for the selected tab
    private var selectedTab: Binding<AppScreen> {
        Binding(
            get: {
                AppScreen.resolvedSelection(
                    raw: selectedTabRaw, visibleTabs: visibleTabs, firstLaunch: !hasLaunchedBefore
                )
            },
            set: { newTab in
                selectedTabRaw = newTab.rawValue
            }
        )
    }

    private var visibleTabs: [AppScreen] {
        AppScreen.visibleTabs(from: setupSelectedTabs, roastMode: roastMode, temporaryTab: assistantTab)
    }

    private func reconcileSelectedTab() {
        selectedTabRaw = AppScreen.resolvedSelection(
            raw: selectedTabRaw, visibleTabs: visibleTabs, firstLaunch: !hasLaunchedBefore
        ).rawValue
    }
    
    var body: some View {
        Group {
            if roastMode {
                roastModeRoot
            } else {
                standardTabRoot
            }
        }
        .tint(Color.bitbinderAccent)
        .onAppear {
            reconcileSelectedTab()
            if !roastMode && !hasCompletedSetup && scenePhase == .active {
                showSetup = true
            }
            // Mark first launch complete after showing Home
            if !hasLaunchedBefore {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    hasLaunchedBefore = true
                }
            }
            // Seed BitBuddy with the initial page so the very first chat turn
            // is page-aware (the user can ask "what is this" before tapping a
            // different tab).
            BitBuddyService.shared.setCurrentPage(selectedTab.wrappedValue.bitBuddySection)
        }
        .onChange(of: selectedTab.wrappedValue) { _, newTab in
            if let assistantTab, newTab != assistantTab {
                self.assistantTab = nil
            }
            // Keep BitBuddy aware of which page the user is on. Asked
            // questions like "help me here" or "what can I do on this page"
            // resolve against this rather than defaulting to a generic
            // response.
            BitBuddyService.shared.setCurrentPage(newTab.bitBuddySection)
        }
        .fullScreenCover(isPresented: $showSetup) {
            AppSetupView()
        }
        .onChange(of: roastMode) { _, isRoast in
            haptic(.medium)
            if isRoast {
                showSetup = false
                bitBuddyDrawer.close()
                bitBuddyPresenter.close()
            } else if !hasCompletedSetup && scenePhase == .active {
                showSetup = true
            }
            assistantTab = nil
            reconcileSelectedTab()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if !roastMode && !hasCompletedSetup && !showSetup {
                    showSetup = true
                }
            case .background, .inactive:
                showSetup = false
                bitBuddyDrawer.close()
                bitBuddyPresenter.close()
            @unknown default:
                break
            }
        }
        .onChange(of: setupSelectedTabs) { _, _ in
            assistantTab = nil
            reconcileSelectedTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToScreen)) { notification in
            if let screenRaw = notification.userInfo?["screen"] as? String,
               let screen = AppScreen(rawValue: screenRaw) {
                // Keep the user's saved tab customization; expose hidden destinations
                // for this visit so assistant navigation always has a valid target.
                let configured = AppScreen.customTabBarScreens(from: setupSelectedTabs, roastMode: roastMode)
                if !roastMode || configured.contains(screen) {
                    assistantTab = configured.contains(screen) ? nil : screen
                    selectedTabRaw = screen.rawValue
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if userPreferences.bitBuddyEnabled && !roastMode {
                GeometryReader { geo in
                    let bubbleSize: CGFloat = 56
                    let defaultX = geo.size.width - bubbleSize - 16
                    let defaultY = geo.size.height - 160
                    let posX = bitBuddyX < 0 ? defaultX : bitBuddyX
                    let posY = bitBuddyY < 0 ? defaultY : bitBuddyY

                    Button {
                        guard !isDragging else { return }
                        haptic(.light)
                        bitBuddyPresenter.openCompact()
                    } label: {
                        BitBuddyAvatar(roastMode: roastMode, size: bubbleSize, symbolSize: 22)
                            .accessibilityHidden(true)
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open BitBuddy")
                        .accessibilityHint("Opens your writing assistant")
                        .accessibilityHidden(bitBuddyPresenter.mode != .closed || bitBuddyDrawer.isOpen)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .scaleEffect(isDragging && !reduceMotion ? 1.15 : 1.0)
                        .opacity(bitBuddyPresenter.mode == .closed && !bitBuddyDrawer.isOpen ? 1 : 0)
                        .contentShape(Circle().inset(by: -10))
                        .position(
                            x: min(max(bubbleSize / 2, posX + dragOffset.width), geo.size.width - bubbleSize / 2),
                            y: min(max(bubbleSize / 2, posY + dragOffset.height), geo.size.height - bubbleSize / 2)
                        )
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { value in
                                    isDragging = true
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    let newX = (bitBuddyX < 0 ? defaultX : bitBuddyX) + value.translation.width
                                    let newY = (bitBuddyY < 0 ? defaultY : bitBuddyY) + value.translation.height
                                    bitBuddyX = min(max(bubbleSize / 2, newX), geo.size.width - bubbleSize / 2)
                                    bitBuddyY = min(max(bubbleSize / 2, newY), geo.size.height - bubbleSize / 2)
                                    dragOffset = .zero
                                    isDragging = false
                                }
                        )
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: bitBuddyDrawer.isOpen)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDragging)
                        .allowsHitTesting(bitBuddyPresenter.mode == .closed && !bitBuddyDrawer.isOpen)
                }
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            if audioService.isRecording && !roastMode {
                GlobalRecordingIndicator {
                    stopGlobalRecording()
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Stop and save recording")
            }
        }
        .alert("Save Recording", isPresented: $showingGlobalRecordingSave) {
            TextField("Recording name", text: $globalRecordingName)
            Button("Save") { saveGlobalRecording() }
            Button("Discard", role: .destructive) { discardGlobalRecording() }
        } message: {
            Text("Save or discard the recording you just stopped.")
        }
        .alert("Recording Error", isPresented: $showingGlobalRecordingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(globalRecordingError ?? "The recording could not be saved.")
        }
        .bitBuddyDrawer(controller: bitBuddyDrawer, roastMode: false)
        .bitBuddyCompactWindow(presenter: bitBuddyPresenter, roastMode: false)
        .onChange(of: bitBuddyPresenter.mode) { _, mode in
            // Keep the full-drawer controller in sync with the presenter so
            // existing call sites that open .full still route correctly.
            if mode == .full {
                bitBuddyDrawer.open()
                bitBuddyPresenter.mode = .closed
            }
        }
    }

    private func stopGlobalRecording() {
        globalRecordingName = audioService.activeRecordingName.isEmpty
            ? "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
            : audioService.activeRecordingName
        let result = audioService.stopRecording()
        globalRecordingURL = result.url
        globalRecordingDuration = result.duration
        showingGlobalRecordingSave = true
        haptic(.medium)
    }

    private func saveGlobalRecording() {
        guard let fileURL = globalRecordingURL else {
            showGlobalRecordingError("Recording file not found. Please try again.")
            return
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showGlobalRecordingError("Recording file was not created. Please try again.")
            return
        }

        let title = globalRecordingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
            : globalRecordingName.trimmingCharacters(in: .whitespacesAndNewlines)

        let recording = Recording(
            title: title,
            fileURL: fileURL.lastPathComponent,
            duration: globalRecordingDuration
        )
        modelContext.insert(recording)
        recording.captureAudioData()   // capture bytes so the audio syncs across devices

        do {
            try modelContext.save()
            audioService.clearFinishedRecording()
            clearGlobalRecordingDraft()
            haptic(.success)
        } catch {
            modelContext.delete(recording)
            showGlobalRecordingError("Could not save recording: \(error.localizedDescription)")
        }
    }

    private func discardGlobalRecording() {
        audioService.cancelRecording()
        clearGlobalRecordingDraft()
    }

    private func clearGlobalRecordingDraft() {
        globalRecordingURL = nil
        globalRecordingDuration = 0
        globalRecordingName = ""
    }

    private func showGlobalRecordingError(_ message: String) {
        globalRecordingError = message
        showingGlobalRecordingError = true
    }

    private var standardTabRoot: some View {
        TabView(selection: selectedTab) {
            ForEach(visibleTabs, id: \.self) { screen in
                Tab(value: screen) {
                    NavigationStack {
                        screenView(for: screen)
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                } label: {
                    Label(
                        screen.displayName,
                        systemImage: selectedTab.wrappedValue == screen ? screen.selectedIcon : screen.icon
                    )
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    private var roastModeRoot: some View {
        TabView(selection: selectedTab) {
            ForEach(visibleTabs, id: \.self) { screen in
                Tab(value: screen) {
                    NavigationStack {
                        screenView(for: screen)
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button("Exit Roast Mode") {
                                        roastMode = false
                                    }
                                }
                            }
                    }
                } label: {
                    Label(
                        screen.roastName,
                        systemImage: selectedTab.wrappedValue == screen ? screen.roastSelectedIcon : screen.roastIcon
                    )
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
    
    @ViewBuilder
    private func screenView(for screen: AppScreen) -> some View {
        switch screen {
        case .home:
            HomeView()
        case .brainstorm:
            BrainstormView()
        case .jokes:
            JokesView()
        case .sets:
            SetListsView()
        case .recordings:
            RecordingsView()
        case .notebookSaver:
            NotepadView()
        case .settings:
            SettingsView()
        }
    }
}

struct GlobalRecordingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    let stopAction: () -> Void

    var body: some View {
        Button(action: stopAction) {
            ZStack {
                Circle()
                    .fill(Color.recording.opacity(0.22))
                    .frame(width: 56, height: 56)
                    .scaleEffect(isPulsing && !reduceMotion ? 1.25 : 1.0)
                    .opacity(isPulsing && !reduceMotion ? 0.35 : 0.8)

                Circle()
                    .fill(Color.recording)
                    .frame(width: 42, height: 42)
                    .shadow(color: Color.recording.opacity(0.45), radius: 10, x: 0, y: 4)

                Image(systemName: "stop.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(UserPreferences())
        .modelContainer(for: [
            Joke.self, JokeFolder.self, Recording.self, SetList.self,
            NotebookPhotoRecord.self, NotebookFolder.self, RoastTarget.self,
            RoastJoke.self, BrainstormIdea.self, ImportBatch.self,
            ImportedJokeMetadata.self, UnresolvedImportFragment.self
        ], inMemory: true)
}
