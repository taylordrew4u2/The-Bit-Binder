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
    
    var body: some View {
        MainTabView()
            .preferredColorScheme(roastMode ? .dark : nil)
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
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.system(size: 14))
                                    }
                                }
                            }

                        }
                }
                .tabItem {
                    Label(
                        roastMode ? screen.roastName : screen.rawValue,
                        systemImage: selectedTab.wrappedValue == screen
                            ? (roastMode ? screen.roastSelectedIcon : screen.selectedIcon)
                            : (roastMode ? screen.roastIcon : screen.icon)
                    )
                }
                .tag(screen)
            }
        }
        .tint(Color.bitbinderAccent)
        .onAppear {
            if !hasCompletedSetup {
                showSetup = true
            }
            // Mark first launch complete after showing Home
            if !hasLaunchedBefore {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    hasLaunchedBefore = true
                }
            }
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
                    .contentShape(Circle().inset(by: -10)) // bigger tap/drag target
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
        .bitBuddyDrawer(controller: bitBuddyDrawer, roastMode: roastMode)
        .bitBuddyCompactWindow(presenter: bitBuddyPresenter, roastMode: roastMode)
        .onChange(of: bitBuddyPresenter.mode) { _, mode in
            // Keep the full-drawer controller in sync with the presenter so
            // existing call sites that open .full still route correctly.
            bitBuddyDrawer.isOpen = (mode == .full)
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
