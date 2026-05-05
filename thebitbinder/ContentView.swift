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

enum AppScreen: String, CaseIterable {
    case home = "Home"
    case brainstorm = "Brainstorm"
    case jokes = "Jokes"
    case sets = "Sets"
    case recordings = "Recordings"
    case notebookSaver = "Photo Notebook"
    case journal = "Journal"
    case settings = "Settings"

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
        case .journal:       return nil
        case .settings:      return .settings
        }
    }

    static var roastScreens: [AppScreen] {
        [.jokes, .settings]
    }

    // Default screens for the tab bar when no custom selection exists
    static var defaultTabBarScreens: [AppScreen] {
        [.home, .jokes, .sets, .notebookSaver]
    }

    static var defaultRoastTabBarScreens: [AppScreen] {
        [.jokes, .sets]
    }

    /// Ordered list of all screens that can appear in the tab bar.
    /// Used to maintain a stable ordering regardless of selection order.
    static var tabBarOrder: [AppScreen] {
        [.home, .brainstorm, .jokes, .sets, .recordings, .notebookSaver, .journal]
    }

    /// Returns the user's custom tab selection (plus Settings, always appended).
    static func customTabBarScreens(from raw: String, roastMode: Bool) -> [AppScreen] {
        let defaults = roastMode ? defaultRoastTabBarScreens : defaultTabBarScreens
        guard !raw.isEmpty else { return defaults + [.settings] }

        let selected = Set(raw.split(separator: ",").compactMap { AppScreen(rawValue: String($0)) })
        // Filter to ordered list, always include Settings at the end
        let ordered = tabBarOrder.filter { selected.contains($0) }
        return (ordered.isEmpty ? defaults : ordered) + [.settings]
    }

    var icon: String {
        switch self {
        case .home:          return "house"
        case .brainstorm:    return "lightbulb"
        case .jokes:         return "text.quote"
        case .sets:          return "list.bullet.rectangle.portrait"
        case .recordings:    return "waveform"
        case .notebookSaver: return "photo.on.rectangle"
        case .journal:       return "book.closed"
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
        case .notebookSaver: return "photo.on.rectangle.fill"
        case .journal:       return "book.closed.fill"
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
        case .notebookSaver: return "Photo Notebook"
        case .journal:       return "Journal"
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
    // Persist the selected tab across app launches
    @AppStorage("selectedTabRawValue") private var selectedTabRaw: String = AppScreen.home.rawValue
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup: Bool = false
    @AppStorage("setupSelectedTabs") private var setupSelectedTabs: String = ""
    @State private var showGagGrabber = false
    @State private var showSetup = false
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var userPreferences: UserPreferences

    // BitBuddy side drawer — replaces the old .sheet so users can chat
    // alongside whatever they're working on.
    @StateObject private var bitBuddyDrawer = BitBuddyDrawerController()
    @StateObject private var bitBuddyPresenter = BitBuddyPresentationController()

    // Draggable BitBuddy position (persisted)
    @AppStorage("bitBuddyX") private var bitBuddyX: Double = -1
    @AppStorage("bitBuddyY") private var bitBuddyY: Double = -1
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    // Computed binding for the selected tab
    private var selectedTab: Binding<AppScreen> {
        Binding(
            get: {
                // On first launch, always show Home
                if !hasLaunchedBefore {
                    return .home
                }
                // Otherwise, restore the saved tab (if valid for current mode)
                if let tab = AppScreen(rawValue: selectedTabRaw), visibleTabs.contains(tab) {
                    return tab
                }
                return roastMode ? .jokes : .home
            },
            set: { newTab in
                selectedTabRaw = newTab.rawValue
            }
        )
    }

    private var visibleTabs: [AppScreen] {
        AppScreen.customTabBarScreens(from: setupSelectedTabs, roastMode: roastMode)
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
            if !hasCompletedSetup && scenePhase == .active {
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
            // Keep BitBuddy aware of which page the user is on. Asked
            // questions like "help me here" or "what can I do on this page"
            // resolve against this rather than defaulting to a generic
            // response.
            BitBuddyService.shared.setCurrentPage(newTab.bitBuddySection)
        }
        .fullScreenCover(isPresented: $showSetup) {
            AppSetupView(isFirstLaunch: !hasLaunchedBefore)
        }
        .onChange(of: roastMode) { _, isRoast in
            haptic(.medium)
            // Redirect to valid tab when mode changes
            if !visibleTabs.contains(selectedTab.wrappedValue) {
                selectedTabRaw = (isRoast ? AppScreen.jokes : .home).rawValue
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if !hasCompletedSetup && !showSetup {
                    showSetup = true
                }
            case .background, .inactive:
                showGagGrabber = false
                showSetup = false
                bitBuddyDrawer.close()
                bitBuddyPresenter.close()
            @unknown default:
                break
            }
        }
        .onChange(of: setupSelectedTabs) { _, _ in
            // If current tab was removed, redirect
            if !visibleTabs.contains(selectedTab.wrappedValue) {
                selectedTabRaw = (visibleTabs.first ?? .home).rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToScreen)) { notification in
            if let screenRaw = notification.userInfo?["screen"] as? String,
               let screen = AppScreen(rawValue: screenRaw) {
                if visibleTabs.contains(screen) {
                    selectedTabRaw = screen.rawValue
                }
            }
        }
        .sheet(isPresented: $showGagGrabber) {
            HybridGagGrabberSheet()
        }
        .overlay(alignment: .topLeading) {
            if userPreferences.bitBuddyEnabled {
                GeometryReader { geo in
                    let bubbleSize: CGFloat = 56
                    let defaultX = geo.size.width - bubbleSize - 16
                    let defaultY = geo.size.height - 160
                    let posX = bitBuddyX < 0 ? defaultX : bitBuddyX
                    let posY = bitBuddyY < 0 ? defaultY : bitBuddyY

                    BitBuddyAvatar(roastMode: roastMode, size: bubbleSize, symbolSize: 22)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .scaleEffect(isDragging ? 1.15 : 1.0)
                        .opacity(bitBuddyPresenter.mode == .closed ? 1 : 0)
                        .contentShape(Circle().inset(by: -10))
                        .position(
                            x: min(max(bubbleSize / 2, posX + dragOffset.width), geo.size.width - bubbleSize / 2),
                            y: min(max(bubbleSize / 2, posY + dragOffset.height), geo.size.height - bubbleSize / 2)
                        )
                        .gesture(
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
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    if !isDragging {
                                        haptic(.light)
                                        bitBuddyPresenter.openCompact()
                                    }
                                }
                        )
                        .animation(.easeInOut(duration: 0.2), value: bitBuddyDrawer.isOpen)
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)
                        .allowsHitTesting(bitBuddyPresenter.mode == .closed)
                }
                .ignoresSafeArea()
            }
        }
        .bitBuddyDrawer(controller: bitBuddyDrawer, roastMode: roastMode)
        .bitBuddyCompactWindow(presenter: bitBuddyPresenter, roastMode: roastMode)
        .onChange(of: bitBuddyPresenter.mode) { _, mode in
            // Keep the full-drawer controller in sync with the presenter so
            // existing call sites that open .full still route correctly.
            bitBuddyDrawer.isOpen = (mode == .full)
        }
    }

    private var standardTabRoot: some View {
        TabView(selection: selectedTab) {
            ForEach(visibleTabs, id: \.self) { screen in
                NavigationStack {
                    screenView(for: screen)
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            // GagGrabber file upload — Jokes page only
                            if screen == .jokes {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button {
                                        showGagGrabber = true
                                    } label: {
                                        Image("GagGrabberGlyph")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 20, height: 20)
                                    }
                                }
                            }

                        }
                }
                .tabItem {
                    Label(
                        screen.rawValue,
                        systemImage: selectedTab.wrappedValue == screen ? screen.selectedIcon : screen.icon
                    )
                }
                .tag(screen)
            }
        }
    }

    private var roastModeRoot: some View {
        NavigationStack {
            JokesView()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Exit Roast Mode") {
                            roastMode = false
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showGagGrabber = true
                        } label: {
                            Image("GagGrabberGlyph")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
        }
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
            NotebookView()
        case .journal:
            JournalHomeView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Joke.self, inMemory: true)
}
