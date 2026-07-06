//
//  RoastTargetDetailView.swift
//  thebitbinder
//
//  Shows a roast target's profile and all roast jokes for them.
//  Users can add, edit, reorder, and export roast jokes here.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct RoastTargetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("roastSortOption") private var sortOption: RoastJokeSortOption = .newest
    @AppStorage("roastTargetWorkspaceMode") private var workspaceModeRaw = RoastTargetWorkspaceMode.both.rawValue
    @AppStorage("roastTargetHeaderCollapsed") private var isHeaderCollapsed = true
    @AppStorage("thingsIKnowCollapsed") private var isThingsIKnowCollapsed = false
    @AppStorage("roastNotepadCollapsed") private var isRoastNotepadCollapsed = false
    @AppStorage("roastTextScale") private var roastTextScale = 1.0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var target: RoastTarget
    
    // Query all non-deleted roast jokes for this target - SwiftData will auto-update the view
    @Query private var allRoastJokes: [RoastJoke]

    @State private var showingAddRoast = false
    @State private var editingJoke: RoastJoke?
    @State private var showingEditJoke = false
    @State private var showingEditTarget = false
    @State private var showingTalkToText = false
    @State private var showingDeleteTargetAlert = false
    @State private var searchText = ""
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    @State private var showingRoastTrash = false
    @State private var showingExportSheet = false
    @State private var exportedFileURL: URL?
    @State private var showingFontSlider = false
    @State private var newTraitText = ""
    @State private var selectedScratchpadText = ""
    @State private var scratchpadSaveTask: Task<Void, Never>?
    
    // Filter state
    @State private var filterMode: RoastFilterMode = .all
    
    private var accentColor: Color { FirePalette.core }
    private var roastBodyFontSize: CGFloat { 15 * roastTextScale }
    private var roastSupportFontSize: CGFloat { max(12, 12 * roastTextScale) }
    private var workspaceMode: RoastTargetWorkspaceMode {
        get { RoastTargetWorkspaceMode(rawValue: workspaceModeRaw) ?? .both }
        nonmutating set { workspaceModeRaw = newValue.rawValue }
    }
    private var showsRoasts: Bool {
        workspaceMode == .roasts || workspaceMode == .both
    }
    private var canAddTrait: Bool {
        !newTraitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canPromoteSelection: Bool {
        !selectedScratchpadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct RoastDisplayGroup: Identifiable {
        let opener: RoastJoke
        let backups: [RoastJoke]

        var id: UUID { opener.id }
    }

    private enum RoastTargetWorkspaceMode: String, CaseIterable, Identifiable {
        case workspace
        case roasts
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .workspace: return "Notes"
            case .roasts: return "Roasts"
            case .both: return "Both"
            }
        }

        var icon: String {
            switch self {
            case .workspace: return "note.text"
            case .roasts: return "text.quote"
            case .both: return "rectangle.split.2x1"
            }
        }
    }

    private struct TargetSocialProfile: Identifiable {
        let id: String
        let label: String
        let displayValue: String
        let icon: String
        let url: URL
    }

    private enum SocialProfileKind {
        case instagram
        case tiktok
        case x
        case facebook
        case website
    }

    enum RoastFilterMode: String, CaseIterable {
        case all = "All"
        case openers = "Openers"
        case backups = "Backups"

        var icon: String {
            switch self {
            case .all: return "text.quote"
            case .openers: return "star.circle.fill"
            case .backups: return "arrow.turn.down.right"
            }
        }
    }
    
    /// Jokes for this target only, filtered from the @Query
    private var jokesForTarget: [RoastJoke] {
        guard target.isValid else { return [] }
        return allRoastJokes.filter { joke in
            !joke.isTrashed && joke.target?.id == target.id
        }
    }
    
    private var filteredJokes: [RoastJoke] {
        guard target.isValid else { return [] }
        
        let baseJokes = jokesForTarget
        
        // First apply filter
        let filtered: [RoastJoke]
        switch filterMode {
        case .all:
            filtered = sortJokes(baseJokes, by: sortOption)
        case .openers:
            filtered = sortJokes(baseJokes.filter { $0.isOpeningRoast }, by: sortOption)
        case .backups:
            filtered = sortJokes(baseJokes.filter { $0.parentOpeningRoastID != nil && !$0.isOpeningRoast }, by: sortOption)
        }
        
        // Then apply search
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return filtered }
        return filtered.filter {
            $0.content.lowercased().contains(trimmed) ||
            $0.setup.lowercased().contains(trimmed) ||
            $0.punchline.lowercased().contains(trimmed)
        }
    }

    private var visibleJokes: [RoastJoke] {
        let baseJokes = jokesForTarget
        let allByID = Dictionary(uniqueKeysWithValues: baseJokes.map { ($0.id, $0) })
        var visible = filteredJokes
        var seen = Set(visible.map(\.id))

        for joke in filteredJokes {
            guard let parentID = joke.parentOpeningRoastID,
                  let opener = allByID[parentID],
                  !seen.contains(opener.id) else { continue }
            visible.append(opener)
            seen.insert(opener.id)
        }

        return sortJokes(visible, by: sortOption)
    }

    private var displayGroups: [RoastDisplayGroup] {
        let jokes = visibleJokes
        let visibleIDs = Set(jokes.map(\.id))
        let orderByID = Dictionary(uniqueKeysWithValues: jokes.enumerated().map { ($1.id, $0) })
        let backupsByParent = Dictionary(grouping: jokes.filter { joke in
            guard let parentID = joke.parentOpeningRoastID else { return false }
            return visibleIDs.contains(parentID)
        }) { $0.parentOpeningRoastID! }

        let topLevelJokes = jokes.filter { joke in
            guard let parentID = joke.parentOpeningRoastID else { return true }
            return !visibleIDs.contains(parentID)
        }

        return topLevelJokes.map { joke in
            let backups = (backupsByParent[joke.id] ?? []).sorted {
                (orderByID[$0.id] ?? .max) < (orderByID[$1.id] ?? .max)
            }
            return RoastDisplayGroup(opener: joke, backups: backups)
        }
    }
    
    /// Sort jokes by the given option
    private func sortJokes(_ jokes: [RoastJoke], by option: RoastJokeSortOption) -> [RoastJoke] {
        switch option {
        case .custom:
            return jokes.sorted { $0.displayOrder < $1.displayOrder }
        case .newest:
            return jokes.sorted { $0.dateCreated > $1.dateCreated }
        case .oldest:
            return jokes.sorted { $0.dateCreated < $1.dateCreated }
        case .relatability:
            return jokes.sorted { $0.relatabilityScore > $1.relatabilityScore }
        }
    }
    
    /// Safe access to target name to prevent crashes on invalidated models
    private var safeTargetName: String {
        target.isValid ? target.name : ""
    }

    private var socialProfiles: [TargetSocialProfile] {
        guard target.isValid else { return [] }

        var profiles: [TargetSocialProfile] = []
        if let instagram = socialProfile(
            id: "instagram",
            label: "Instagram",
            rawValue: target.instagramHandle,
            icon: "camera.circle",
            kind: .instagram
        ) {
            profiles.append(instagram)
        }
        if let tiktok = socialProfile(
            id: "tiktok",
            label: "TikTok",
            rawValue: target.tiktokHandle,
            icon: "music.note",
            kind: .tiktok
        ) {
            profiles.append(tiktok)
        }
        if let x = socialProfile(
            id: "x",
            label: "X",
            rawValue: target.xHandle,
            icon: "at",
            kind: .x
        ) {
            profiles.append(x)
        }
        if let facebook = socialProfile(
            id: "facebook",
            label: "Facebook",
            rawValue: target.facebookURL,
            icon: "person.2.circle",
            kind: .facebook
        ) {
            profiles.append(facebook)
        }
        if let website = socialProfile(
            id: "website",
            label: "Website",
            rawValue: target.websiteURL,
            icon: "link.circle",
            kind: .website
        ) {
            profiles.append(website)
        }
        return profiles
    }
    
    /// Opening roasts for this target (for backup assignment)
    private var openingRoastsForTarget: [RoastJoke] {
        guard target.isValid else { return [] }
        return jokesForTarget.filter { $0.isOpeningRoast }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private func openerLabel(for joke: RoastJoke) -> String {
        guard let index = openingRoastsForTarget.firstIndex(where: { $0.id == joke.id }) else {
            return "Opener"
        }
        return "Opener \(index + 1)"
    }

    var body: some View {
        VStack(spacing: 0) {
            targetHeaderCard
            workspaceModeControl

            if showsRoasts {
                filterChips

                if showingFontSlider {
                    fontSliderBar
                }

                Divider().opacity(0.3)
            }

            targetWorkspaceAndRoasts
        }
        .background(FirePalette.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search roasts")
        .toolbar { toolbarContent }
        .alert("Delete \(safeTargetName)?", isPresented: $showingDeleteTargetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTarget()
            }
        } message: {
            Text("This will move \(safeTargetName) and all \(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s") to trash.")
        }
        .alert("Error", isPresented: $showingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showingAddRoast) {
            AddRoastJokeView(target: target)
        }
        .sheet(isPresented: $showingEditJoke, onDismiss: {
            editingJoke = nil
        }) {
            if let editingJoke {
                EditRoastJokeView(joke: editingJoke)
            }
        }
        .sheet(isPresented: $showingEditTarget) {
            EditRoastTargetView(target: target)
        }
        .sheet(isPresented: $showingTalkToText) {
            TalkToTextRoastView(target: target)
        }
        .sheet(isPresented: $showingExportSheet) {
            RoastExportSheet(target: target, exportedURL: $exportedFileURL)
        }
        .navigationDestination(isPresented: $showingRoastTrash) {
            RoastJokeTrashView(target: target)
        }
        .onChange(of: target.notes) { _, _ in
            scheduleScratchpadSave()
        }
        .onDisappear {
            scratchpadSaveTask?.cancel()
            if target.isValid {
                target.dateModified = Date()
                saveContext("target scratchpad")
            }
        }
    }
    
    // MARK: - View Components

    private var fontSliderBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "textformat.size.smaller")
                    .font(.caption2)
                    .foregroundColor(FirePalette.sub)

                Slider(value: $roastTextScale, in: 0.6...2.0, step: 0.05)
                    .tint(accentColor)

                Image(systemName: "textformat.size.larger")
                    .font(.caption)
                    .foregroundColor(FirePalette.sub)

                Button {
                    roastTextScale = 1.0
                } label: {
                    Text("Reset")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(accentColor)
                }
            }

            Text("\(Int(roastTextScale * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundColor(FirePalette.sub)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(FirePalette.card)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var targetHeaderCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: isHeaderCollapsed ? DS.Spacing.sm : DS.Spacing.md) {
                HStack(alignment: .center, spacing: DS.Spacing.md) {
                    if isHeaderCollapsed {
                        RoastSubjectAvatar(
                            photoData: target.photoData,
                            fallbackInitial: String(safeTargetName.prefix(1).uppercased()),
                            accentColor: accentColor,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(safeTargetName)
                                .font(.headline.bold())
                                .foregroundColor(FirePalette.text)

                            HStack(spacing: DS.Spacing.sm) {
                                Text("\(target.jokeCount)")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundColor(accentColor)

                                Text("roast\(target.jokeCount == 1 ? "" : "s")")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(FirePalette.sub)
                            }
                        }

                        Spacer()
                    } else {
                        Spacer()

                        VStack(spacing: DS.Spacing.md) {
                            RoastSubjectAvatar(
                                photoData: target.photoData,
                                fallbackInitial: String(safeTargetName.prefix(1).uppercased()),
                                accentColor: accentColor
                            )

                            Text(safeTargetName)
                                .font(.title3.bold())
                                .foregroundColor(FirePalette.text)
                        }

                        Spacer()
                    }
                }

                if !isHeaderCollapsed {
                    if !target.notes.isEmpty {
                        Text(target.notes)
                            .font(.subheadline)
                            .foregroundColor(FirePalette.sub)
                            .multilineTextAlignment(.center)
                    }

                    if !target.traits.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            ForEach(target.traits, id: \.self) { trait in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(accentColor)
                                    Text(trait)
                                        .font(.subheadline)
                                        .foregroundColor(FirePalette.sub)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.xxl)
                    }

                    if !socialProfiles.isEmpty {
                        socialProfileLinks
                    }

                    HStack(spacing: DS.Spacing.lg) {
                        StatBadge(
                            count: target.jokeCount,
                            label: "roast",
                            icon: "text.quote",
                            color: accentColor
                        )
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHeaderCollapsed.toggle()
                }
            } label: {
                Image(systemName: isHeaderCollapsed ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accentColor, FirePalette.card)
            }
            .padding(DS.Spacing.md)
        }
        .background(FirePalette.card)
    }

    private var socialProfileLinks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(socialProfiles) { profile in
                    Button {
                        openURL(profile.url)
                    } label: {
                        Label {
                            Text(profile.label)
                                .font(.caption.weight(.semibold))
                        } icon: {
                            Image(systemName: profile.icon)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(accentColor)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(accentColor.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(accentColor.opacity(0.24), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(profile.label): \(profile.displayValue)")
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private func socialProfile(
        id: String,
        label: String,
        rawValue: String,
        icon: String,
        kind: SocialProfileKind
    ) -> TargetSocialProfile? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let handle = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let urlString: String
        let displayValue: String
        switch kind {
        case .instagram:
            guard !handle.isEmpty else { return nil }
            urlString = "https://instagram.com/\(handle)"
            displayValue = "@\(handle)"
        case .tiktok:
            guard !handle.isEmpty else { return nil }
            urlString = "https://www.tiktok.com/@\(handle)"
            displayValue = "@\(handle)"
        case .x:
            guard !handle.isEmpty else { return nil }
            urlString = "https://x.com/\(handle)"
            displayValue = "@\(handle)"
        case .facebook:
            urlString = absoluteURLString(from: trimmed, defaultHost: "facebook.com")
            displayValue = trimmed
        case .website:
            urlString = absoluteURLString(from: trimmed, defaultHost: nil)
            displayValue = trimmed
        }

        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            return nil
        }

        return TargetSocialProfile(
            id: id,
            label: label,
            displayValue: displayValue,
            icon: icon,
            url: url
        )
    }

    private func absoluteURLString(from rawValue: String, defaultHost: String?) -> String {
        let lowercased = rawValue.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return rawValue
        }
        if let defaultHost, !rawValue.contains(".") {
            return "https://\(defaultHost)/\(rawValue)"
        }
        return "https://\(rawValue)"
    }

    private var workspaceModeControl: some View {
        VStack(spacing: 0) {
            Picker("Target workspace mode", selection: Binding(
                get: { workspaceMode },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        workspaceMode = newValue
                    }
                }
            )) {
                ForEach(RoastTargetWorkspaceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .accessibilityLabel("Target workspace mode")

            Divider().opacity(0.25)
        }
        .background(FirePalette.bg.opacity(0.96))
    }
    
    private var filterChips: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(RoastFilterMode.allCases, id: \.rawValue) { mode in
                        FilterChip(
                            title: mode.rawValue,
                            icon: mode.icon,
                            isSelected: filterMode == mode,
                            accentColor: accentColor
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filterMode = mode
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
            }

            // Sort menu pinned outside the scroll so it never disappears
            Menu {
                ForEach(RoastJokeSortOption.allCases) { option in
                    Button {
                        sortOption = option
                    } label: {
                        Label(option.rawValue, systemImage: option.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sortOption.icon)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(DS.Opacity.light))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5)
                )
            }
            .accessibilityLabel("Sort roasts by \(sortOption.rawValue)")
            .padding(.trailing, DS.Spacing.md)
        }
        .padding(.vertical, 10)
        .background(FirePalette.bg.opacity(0.95))
    }
    
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: filterMode == .all ? "text.quote" : filterMode.icon)
                .font(.largeTitle)
                .foregroundColor(accentColor.opacity(DS.Opacity.scrim))

            if filterMode == .all {
                Text("No roasts yet")
                    .font(.title3.bold())
                    .foregroundColor(FirePalette.text)

                Text("Start roasting \(safeTargetName)")
                    .font(.subheadline)
                    .foregroundColor(FirePalette.sub)

                EmberCTAButton(title: "Write First Roast") {
                    showingAddRoast = true
                }
                .padding(.top, DS.Spacing.sm)
            } else {
                Text("No \(filterMode.rawValue.lowercased()) roasts")
                    .font(.title3.bold())
                    .foregroundColor(FirePalette.text)
                Text("Roasts will appear here once you mark them as \(filterMode.rawValue.lowercased())")
                    .font(.subheadline)
                    .foregroundColor(FirePalette.sub)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.lg)
    }
    
    private var targetWorkspaceAndRoasts: some View {
        Group {
            switch workspaceMode {
            case .workspace:
                workspaceScrollView
            case .roasts:
                roastsScrollView
            case .both:
                if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        workspaceScrollView
                            .frame(minWidth: 320, idealWidth: 390, maxWidth: 460)

                        Divider().opacity(0.4)

                        roastsScrollView
                    }
                } else {
                    combinedScrollView
                }
            }
        }
    }

    private var workspaceScrollView: some View {
        ScrollView {
            targetWorkspaceSection
                .padding(.top, 12)
                .padding(.bottom, DS.Spacing.lg)
        }
        .background(FirePalette.bg)
    }

    private var combinedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                targetWorkspaceSection
                roastsContent
            }
            .padding(.vertical, 8)
        }
    }

    private var roastsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                roastsContent
            }
            .padding(.vertical, 8)
        }
        .background(FirePalette.bg)
    }

    @ViewBuilder
    private var roastsContent: some View {
        if displayGroups.isEmpty {
            emptyState
                .frame(minHeight: 360)
        } else {
            ForEach(displayGroups) { group in
                roastGroupView(group)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .trailing))
                    ))
            }

            addAnotherRoastButton
        }
    }

    private var addAnotherRoastButton: some View {
        Button {
            showingAddRoast = true
        } label: {
            HStack(spacing: DS.Spacing.sm + 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous)
                        .fill(accentColor.opacity(DS.Opacity.light))
                        .frame(width: 42, height: 42)
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(accentColor)
                }

                Text("Add another roast")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(accentColor)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DS.Spacing.lg)
        }
        .buttonStyle(.plain)
    }

    private var targetWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            thingsIKnowSection
            roastScratchpadSection
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.sm)
    }

    private var thingsIKnowSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            workspaceHeader(
                title: "Things I Know",
                detail: target.traits.isEmpty ? "No details yet" : "\(target.traits.count) detail\(target.traits.count == 1 ? "" : "s")",
                icon: "list.bullet.clipboard",
                isCollapsed: $isThingsIKnowCollapsed
            )

            if !isThingsIKnowCollapsed {
                if target.traits.isEmpty {
                    Text("No details saved for \(safeTargetName).")
                        .font(.subheadline)
                        .foregroundColor(FirePalette.sub)
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(Array(target.traits.enumerated()), id: \.offset) { index, trait in
                            if index < target.traits.count {
                                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                    Text("•")
                                        .font(.headline.weight(.bold))
                                        .foregroundColor(accentColor)
                                        .padding(.top, 1)

                                    TextField("What do you know?", text: Binding(
                                        get: { index < target.traits.count ? target.traits[index] : trait },
                                        set: { newValue in
                                            guard index < target.traits.count else { return }
                                            target.traits[index] = newValue
                                            persistTargetFacts()
                                        }
                                    ), axis: .vertical)
                                    .font(.subheadline)
                                    .foregroundColor(FirePalette.text)

                                    Button {
                                        removeTrait(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(FirePalette.sub)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove detail")
                                }
                                .padding(DS.Spacing.sm)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
                            }
                        }
                    }
                }

                HStack(spacing: DS.Spacing.sm) {
                    TextField("Add a bullet point", text: $newTraitText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundColor(FirePalette.text)
                        .padding(DS.Spacing.md)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit(addTraitFromInput)

                    Button {
                        addTraitFromInput()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(canAddTrait ? accentColor : FirePalette.sub)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddTrait)
                    .accessibilityLabel("Add detail")
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(FirePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous)
                .strokeBorder(FirePalette.edge, lineWidth: 0.5)
        )
    }

    private var roastScratchpadSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            workspaceHeader(
                title: "Roast Notepad",
                detail: target.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Empty" : "Drafting",
                icon: "square.and.pencil",
                isCollapsed: $isRoastNotepadCollapsed
            )

            if !isRoastNotepadCollapsed {
                SelectableRoastNotepad(
                    text: $target.notes,
                    selectedText: $selectedScratchpadText,
                    placeholder: "Start writing premises, angles, alternate punchlines, tags, or rough roast ideas..."
                )
                .frame(minHeight: 180)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous)
                        .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                )

                HStack(spacing: DS.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedScratchpadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No text selected" : "Selected text ready")
                            .font(.caption.weight(.medium))
                            .foregroundColor(FirePalette.sub)
                        if !selectedScratchpadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(selectedScratchpadText.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundColor(FirePalette.text.opacity(0.8))
                        }
                    }

                    Spacer()

                    Button {
                        promoteSelectedScratchpadText()
                    } label: {
                        Label("Promote to Roast", systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, 10)
                            .background(canPromoteSelection ? AnyShapeStyle(FirePalette.emberCTA) : AnyShapeStyle(Color.white.opacity(0.06)))
                            .foregroundColor(canPromoteSelection ? .white : FirePalette.sub)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPromoteSelection)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(FirePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous)
                .strokeBorder(FirePalette.edge, lineWidth: 0.5)
        )
    }

    private func workspaceHeader(title: String, detail: String, icon: String, isCollapsed: Binding<Bool>? = nil) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(accentColor)
                .frame(width: 26)

            Text(title)
                .font(.headline.bold())
                .foregroundColor(FirePalette.text)

            Spacer()

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundColor(FirePalette.sub)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.1))
                .clipShape(Capsule())

            if let isCollapsed {
                Image(systemName: isCollapsed.wrappedValue ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                    .font(.title3)
                    .foregroundColor(accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let isCollapsed else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.wrappedValue.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCollapsed == nil ? [] : .isButton)
        .accessibilityLabel(isCollapsed == nil ? Text(title) : Text(isCollapsed!.wrappedValue ? "\(title), collapsed" : "\(title), expanded"))
    }

    @ViewBuilder
    private func roastGroupView(_ group: RoastDisplayGroup) -> some View {
        let isOpener = group.opener.isOpeningRoast
        let hasBackups = !group.backups.isEmpty

        if isOpener || hasBackups {
            // Grouped card for openers and their backups
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    groupedRoastSectionLabel(
                        openerLabel(for: group.opener).uppercased(),
                        joke: group.opener
                    )
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.md)

                    roastCard(for: group.opener, embeddedInGroup: true)
                }
                .background(FirePalette.card)

                if hasBackups {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(accentColor.opacity(0.3))
                            .frame(width: 3)
                            .padding(.leading, DS.Spacing.lg + 4)

                        VStack(alignment: .leading, spacing: 0) {
                            groupedRoastSectionLabel(group.backups.count == 1 ? "BACKUP" : "BACKUPS")
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.top, DS.Spacing.sm)

                            ForEach(group.backups) { backup in
                                VStack(alignment: .leading, spacing: 0) {
                                    roastCard(for: backup, nested: true, embeddedInGroup: true)

                                    if backup.id != group.backups.last?.id {
                                        Divider()
                                            .overlay(FirePalette.edge.opacity(0.5))
                                            .padding(.horizontal, DS.Spacing.md)
                                    }
                                }
                            }

                            Spacer().frame(height: DS.Spacing.sm)
                        }
                    }
                    .background(FirePalette.card.opacity(0.6))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Corner.lg, style: .continuous)
                    .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
            .padding(.horizontal, 16)
        } else {
            // Standalone roast — no group wrapper, no label
            roastCard(for: group.opener)
        }
    }

    private func roastCard(for joke: RoastJoke, nested: Bool = false, embeddedInGroup: Bool = false) -> some View {
        DraggableRoastCard(
            joke: joke,
            showFullContent: true,
            accentColor: accentColor,
            embeddedInGroup: embeddedInGroup,
            onTap: {
                editRoast(joke)
            },
            onTrash: {
                withAnimation(.easeOut(duration: 0.25)) {
                    trashJoke(joke)
                }
            },
            onDuplicate: {
                duplicateRoast(joke)
            },
            onToggleOpening: {
                toggleOpeningRoast(joke)
            },
            onSetOpenerPosition: { position in
                setOpenerPosition(joke, to: position)
            },
            openerCount: openingRoastsForTarget.count,
            currentOpenerPosition: currentOpenerPosition(for: joke),
            onAssignAsBackup: { parentID in
                assignAsBackup(joke, to: parentID)
            },
            openingRoastsForTarget: openingRoastsForTarget.filter { $0.id != joke.id }
        )
        .padding(.leading, nested ? 0 : 0)
    }

    private var previewModeView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            ForEach(Array(displayGroups.enumerated()), id: \.element.id) { index, group in
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    previewTextBlock(
                        sequence: "\(index + 1)",
                        label: group.opener.isOpeningRoast ? openerLabel(for: group.opener).uppercased() : "",
                        joke: group.opener
                    )

                    ForEach(Array(group.backups.enumerated()), id: \.element.id) { backupIndex, backup in
                        previewTextBlock(
                            sequence: "\(index + 1)\(Character(UnicodeScalar(65 + backupIndex)!))",
                            label: group.backups.count == 1 ? "BACKUP" : "BACKUP \(backupIndex + 1)",
                            joke: backup
                        )
                        .padding(.leading, DS.Spacing.md)
                    }
                }
                .padding(.bottom, index == displayGroups.count - 1 ? 0 : DS.Spacing.md)
                .overlay(alignment: .bottom) {
                    if index != displayGroups.count - 1 {
                        Divider()
                            .overlay(FirePalette.edge)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .textSelection(.enabled)
    }

    private func previewTextBlock(sequence: String, label: String, joke: RoastJoke) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                HStack(spacing: 8) {
                    Text(sequence)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundColor(FirePalette.text)
                    Text(label)
                        .font(.caption2.weight(.bold))
                }
                .foregroundColor(accentColor)
            } else {
                Text(sequence)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundColor(accentColor)
            }

            if !joke.setup.isEmpty {
                Text(joke.setup)
                    .font(.system(size: roastBodyFontSize, weight: .regular))
                    .foregroundColor(FirePalette.text)
                    .lineSpacing(6)
            }

            Text(joke.content)
                .font(.system(size: roastBodyFontSize, weight: .regular))
                .foregroundColor(FirePalette.text)
                .lineSpacing(7)

            if !joke.punchline.isEmpty {
                Text("Punchline: \(joke.punchline)")
                    .font(.system(size: roastSupportFontSize, weight: .regular))
                    .foregroundColor(FirePalette.sub)
            }

            if !joke.performanceNotes.isEmpty {
                Text("Notes: \(joke.performanceNotes)")
                    .font(.system(size: roastSupportFontSize, weight: .regular))
                    .foregroundColor(FirePalette.sub)
                    .italic()
            }
        }
    }

    private func groupedRoastSectionLabel(_ title: String, joke: RoastJoke? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(accentColor)

            if let joke, joke.isOpeningRoast, openingRoastsForTarget.count > 1 {
                openerPositionPicker(for: joke)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func openerPositionPicker(for joke: RoastJoke) -> some View {
        let current = currentOpenerPosition(for: joke)
        let total = openingRoastsForTarget.count

        HStack(spacing: 3) {
            ForEach(1...total, id: \.self) { position in
                Button {
                    if position != current {
                        setOpenerPosition(joke, to: position)
                    }
                } label: {
                    Text("\(position)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundColor(position == current ? .white : accentColor)
                        .frame(width: 22, height: 22)
                        .background(position == current ? accentColor : accentColor.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showingEditTarget = true
            } label: {
                Image(systemName: "pencil")
            }
            .accessibilityLabel("Edit target")
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingAddRoast = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add roast")
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Section("Text Size") {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingFontSlider.toggle()
                        }
                    } label: {
                        Label("Adjust Text Size", systemImage: "textformat.size")
                    }
                }
                
                Divider()
                
                Section("Other Ways to Add") {
                    Button(action: { showingTalkToText = true }) {
                        Label("Talk-to-Text", systemImage: "mic.badge.plus")
                    }
                }
                
                Divider()
                
                Button(action: { showingExportSheet = true }) {
                    Label("Export Roasts", systemImage: "square.and.arrow.up")
                }
                
                Button { showingRoastTrash = true } label: {
                    Label("Trash", systemImage: "trash")
                }
                
                Divider()
                
                Button(role: .destructive, action: { showingDeleteTargetAlert = true }) {
                    Label("Delete Target", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Target options")
        }
    }
    
    // MARK: - Actions
    
    private func deleteTarget() {
        target.moveToTrash()
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("⚠️ [RoastTargetDetailView] Failed to persist delete: \(error)")
            persistenceError = "Could not delete \(safeTargetName): \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }

    private func trashJoke(_ joke: RoastJoke) {
        joke.moveToTrash()
        saveContext("trash joke")
    }

    private func editRoast(_ joke: RoastJoke) {
        editingJoke = joke
        showingEditJoke = true
    }

    private func duplicateRoast(_ joke: RoastJoke) {
        let duplicate = RoastJoke(
            content: joke.content,
            title: joke.title.isEmpty ? "" : "\(joke.title) Copy",
            target: target
        )
        duplicate.setup = joke.setup
        duplicate.punchline = joke.punchline
        duplicate.performanceNotes = joke.performanceNotes
        duplicate.relatabilityScore = joke.relatabilityScore
        duplicate.displayOrder = (jokesForTarget.map(\.displayOrder).max() ?? -1) + 1
        modelContext.insert(duplicate)
        target.dateModified = Date()
        saveContext("duplicate roast")
    }
    
    private func toggleOpeningRoast(_ joke: RoastJoke) {
        joke.isOpeningRoast.toggle()
        if joke.isOpeningRoast {
            // Clear parent if becoming an opening roast
            joke.parentOpeningRoastID = nil
        }
        joke.dateModified = Date()
        saveContext("opening roast toggle")
    }
    
    private func assignAsBackup(_ joke: RoastJoke, to parentID: UUID?) {
        joke.parentOpeningRoastID = parentID
        if parentID != nil {
            // Can't be an opening roast if it's a backup
            joke.isOpeningRoast = false
        }
        joke.dateModified = Date()
        saveContext("backup assignment")
    }

    private func canMoveOpener(_ joke: RoastJoke, direction: Int) -> Bool {
        guard let currentIndex = openingRoastsForTarget.firstIndex(where: { $0.id == joke.id }) else {
            return false
        }

        let targetIndex = currentIndex + direction
        return openingRoastsForTarget.indices.contains(targetIndex)
    }

    private func moveOpener(_ joke: RoastJoke, direction: Int) {
        guard let currentIndex = openingRoastsForTarget.firstIndex(where: { $0.id == joke.id }) else {
            return
        }

        let targetIndex = currentIndex + direction
        guard openingRoastsForTarget.indices.contains(targetIndex) else {
            return
        }

        let otherOpener = openingRoastsForTarget[targetIndex]
        let currentOrder = joke.displayOrder
        joke.displayOrder = otherOpener.displayOrder
        otherOpener.displayOrder = currentOrder
        joke.dateModified = Date()
        otherOpener.dateModified = Date()
        sortOption = .custom
        haptic(.light)
        saveContext("opener reorder")
    }

    private func setOpenerPosition(_ joke: RoastJoke, to newPosition: Int) {
        var openers = openingRoastsForTarget
        guard let currentIndex = openers.firstIndex(where: { $0.id == joke.id }) else { return }
        let targetIndex = newPosition - 1
        guard targetIndex >= 0, targetIndex < openers.count, targetIndex != currentIndex else { return }

        let moved = openers.remove(at: currentIndex)
        openers.insert(moved, at: targetIndex)

        for (i, opener) in openers.enumerated() {
            opener.displayOrder = i
            opener.dateModified = Date()
        }

        sortOption = .custom
        haptic(.light)
        saveContext("opener position change")
    }

    private func currentOpenerPosition(for joke: RoastJoke) -> Int {
        guard let index = openingRoastsForTarget.firstIndex(where: { $0.id == joke.id }) else { return 0 }
        return index + 1
    }

    private func addTraitFromInput() {
        let trimmed = newTraitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        target.traits.append(trimmed)
        newTraitText = ""
        persistTargetFacts()
        haptic(.light)
    }

    private func removeTrait(at index: Int) {
        guard target.traits.indices.contains(index) else { return }
        target.traits.remove(at: index)
        persistTargetFacts()
        haptic(.light)
    }

    private func persistTargetFacts() {
        target.dateModified = Date()
        saveContext("target facts")
    }

    private func promoteSelectedScratchpadText() {
        let selected = selectedScratchpadText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, target.isValid else { return }

        let joke = RoastJoke(content: selected, target: target)
        joke.displayOrder = jokesForTarget.count
        modelContext.insert(joke)
        target.dateModified = Date()
        selectedScratchpadText = ""
        saveContext("promote scratchpad text")
        haptic(.success)
    }

    private func scheduleScratchpadSave() {
        scratchpadSaveTask?.cancel()
        scratchpadSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, target.isValid else { return }
            target.dateModified = Date()
            saveContext("target scratchpad")
        }
    }

    private func saveContext(_ action: String) {
        do {
            try modelContext.save()
        } catch {
            print("⚠️ [RoastTargetDetailView] Failed to persist \(action): \(error)")
            persistenceError = "Could not save changes: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
}

// MARK: - Supporting Views

struct SelectableRoastNotepad: View {
    @Binding var text: String
    @Binding var selectedText: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundColor(FirePalette.sub.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            SelectableRoastTextView(text: $text, selectedText: $selectedText)
                .padding(6)
        }
    }
}

private struct SelectableRoastTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = UIColor(FirePalette.text)
        textView.tintColor = UIColor(FirePalette.core)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedText: $selectedText)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var selectedText: String

        init(text: Binding<String>, selectedText: Binding<String>) {
            _text = text
            _selectedText = selectedText
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            updateSelection(from: textView, clearWhenEmpty: true)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateSelection(from: textView, clearWhenEmpty: false)
        }

        private func updateSelection(from textView: UITextView, clearWhenEmpty: Bool) {
            let range = textView.selectedRange
            guard range.length > 0,
                  let textRange = Range(range, in: textView.text) else {
                if clearWhenEmpty {
                    selectedText = ""
                }
                return
            }
            selectedText = String(textView.text[textRange])
        }
    }
}

// MARK: - Draggable Roast Card

struct DraggableRoastCard: View {
    let joke: RoastJoke
    var showFullContent: Bool = true
    let accentColor: Color
    var embeddedInGroup: Bool = false
    var onTap: (() -> Void)? = nil
    var onTrash: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onToggleOpening: (() -> Void)? = nil
    var onSetOpenerPosition: ((Int) -> Void)? = nil
    var openerCount: Int = 0
    var currentOpenerPosition: Int = 0
    var onAssignAsBackup: ((UUID?) -> Void)? = nil
    var openingRoastsForTarget: [RoastJoke] = []
    
    @State private var showDeleteConfirm = false
    
    private let cardCornerRadius: CGFloat = DS.Corner.lg

    private func openerLabel(for roast: RoastJoke) -> String {
        guard let index = openingRoastsForTarget.firstIndex(where: { $0.id == roast.id }) else {
            return "Opener"
        }
        return "Opener \(index + 1)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                cardSurface

                quickActionsMenu
                    .padding(.top, DS.Spacing.sm)
                    .padding(.trailing, DS.Spacing.sm)
            }

            roastRoleControls
        }
        .padding(.horizontal, embeddedInGroup ? 0 : 16)
        .confirmationDialog("Delete Roast?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                onTrash?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This roast will be moved to trash.")
        }
    }

    private var cardSurface: some View {
        Button {
            onTap?()
        } label: {
            cardContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Group {
                        if embeddedInGroup {
                            Color.clear
                        } else {
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(Color(FirePalette.card))
                        }
                    }
                )
                .overlay(
                    Group {
                        if !embeddedInGroup {
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                                .allowsHitTesting(false)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Edit roast")
    }

    private var quickActionsMenu: some View {
        Menu {
            contextMenuContent
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(accentColor, FirePalette.card)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Roast actions")
    }

    private var roastRoleControls: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                Button {
                    onTap?()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(accentColor)

                if joke.isOpeningRoast {
                    Label(currentOpenerPosition > 0 ? "Opener \(currentOpenerPosition)" : "Opener", systemImage: "star.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(accentColor)

                    if openerCount > 1 {
                        openerPositionMenu
                    }

                    Button {
                        onToggleOpening?()
                    } label: {
                        Text("Remove opener")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(FirePalette.sub)
                } else {
                    Button {
                        onToggleOpening?()
                    } label: {
                        Label("Make opener", systemImage: "star.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(accentColor)

                    if openingRoastsForTarget.isEmpty {
                        Text("Make an opener first to assign backups")
                            .font(.caption)
                            .foregroundColor(FirePalette.sub)
                            .lineLimit(1)
                    } else {
                        backupAssignmentMenu
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
        .padding(.top, 2)
        .background(embeddedInGroup ? Color.clear : Color(FirePalette.card))
    }

    private var openerPositionMenu: some View {
        Menu {
            ForEach(1...openerCount, id: \.self) { position in
                Button {
                    onSetOpenerPosition?(position)
                } label: {
                    Label(
                        "Opener \(position)",
                        systemImage: position == currentOpenerPosition ? "checkmark.circle.fill" : "\(position).circle"
                    )
                }
                .disabled(position == currentOpenerPosition)
            }
        } label: {
            Label("Position", systemImage: "arrow.up.arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundColor(accentColor)
        }
        .buttonStyle(.plain)
    }

    private var backupAssignmentMenu: some View {
        Menu {
            Button {
                onAssignAsBackup?(nil)
            } label: {
                Label(
                    "None",
                    systemImage: joke.parentOpeningRoastID == nil ? "checkmark.circle.fill" : "circle"
                )
            }

            ForEach(openingRoastsForTarget) { opening in
                Button {
                    onAssignAsBackup?(opening.id)
                } label: {
                    Label(
                        openerLabel(for: opening),
                        systemImage: joke.parentOpeningRoastID == opening.id ? "checkmark.circle.fill" : "star.circle"
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Label("Backup for", systemImage: "arrow.turn.down.right")
                    .font(.caption.weight(.semibold))

                Text(currentBackupLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(accentColor.opacity(0.24), lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assign backup")
    }

    private var currentBackupLabel: String {
        guard let parentID = joke.parentOpeningRoastID,
              let opener = openingRoastsForTarget.first(where: { $0.id == parentID }) else {
            return "None"
        }
        return openerLabel(for: opener)
    }

    private var cardContent: some View {
        RoastJokeCardContent(
            joke: joke,
            showFullContent: showFullContent,
            accentColor: accentColor,
            showsDragHandle: false,
            currentOpenerPosition: currentOpenerPosition
        )
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            UIPasteboard.general.string = copyableRoastText
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }

        Button {
            onDuplicate?()
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        
        Divider()
        
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private var copyableRoastText: String {
        var parts: [String] = []
        if !joke.setup.isEmpty {
            parts.append(joke.setup)
        }
        parts.append(joke.content)
        if !joke.punchline.isEmpty {
            parts.append(joke.punchline)
        }
        if !joke.performanceNotes.isEmpty {
            parts.append("Notes: \(joke.performanceNotes)")
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Edit Roast Joke Sheet

struct EditRoastJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var joke: RoastJoke
    @Query private var allRoastJokes: [RoastJoke]
    
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showAdvancedOptions = false
    @State private var showOpeningAssignment = false
    @FocusState private var isContentFocused: Bool
    
    private var accentColor: Color { FirePalette.core }
    
    /// Safe content accessor
    private var safeContent: String {
        joke.isValid ? joke.content : ""
    }
    
    private var canSave: Bool {
        !safeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Get other opening roasts for this same target (for backup assignment)
    private var openingRoastsForTarget: [RoastJoke] {
        guard let targetID = joke.target?.id else { return [] }
        return allRoastJokes.filter { roast in
            guard !roast.isTrashed,
                  roast.isOpeningRoast,
                  roast.id != joke.id,
                  let roastTargetID = roast.target?.id else { return false }
            return roastTargetID == targetID
        }.sorted { $0.displayOrder < $1.displayOrder }
    }
    
    /// Get the opening roast this joke is a backup for
    private var parentOpeningRoast: RoastJoke? {
        guard let parentID = joke.parentOpeningRoastID else { return nil }
        return allRoastJokes.first { $0.id == parentID && !$0.isTrashed }
    }

    private func openerLabel(for roast: RoastJoke) -> String {
        guard let index = openingRoastsForTarget.firstIndex(where: { $0.id == roast.id }) else {
            return "Opener"
        }
        return "Opener \(index + 1)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main content area
                ScrollView {
                    VStack(spacing: 16) {
                        // The roast content - main focus
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $joke.content)
                                .focused($isContentFocused)
                                .frame(minHeight: 120)
                                .padding(DS.Spacing.md)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous))

                            HStack(spacing: DS.Spacing.md) {
                                Button {
                                    UIPasteboard.general.string = copyableJokeText
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(accentColor)
                                .disabled(copyableJokeText.isEmpty)

                                Button {
                                    pasteIntoJoke()
                                } label: {
                                    Label("Paste", systemImage: "doc.on.clipboard")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(accentColor)
                                .disabled(UIPasteboard.general.string?.isEmpty ?? true)

                                Spacer()
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        
                        // Optional structure fields - collapsible
                        DisclosureGroup(isExpanded: $showAdvancedOptions) {
                            VStack(spacing: 16) {
                                // Setup
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Setup / Premise")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    TextField("The lead-in...", text: $joke.setup, axis: .vertical)
                                        .padding(DS.Spacing.sm + 2)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
                                }
                                
                                // Punchline
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Punchline")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    TextField("The payoff...", text: $joke.punchline, axis: .vertical)
                                        .padding(DS.Spacing.sm + 2)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
                                }
                                
                                // Performance notes
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Notes")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    TextField("Timing, delivery, reactions...", text: $joke.performanceNotes, axis: .vertical)
                                        .padding(DS.Spacing.sm + 2)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
                                }
                                
                        // Relatability score
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Audience Relatability")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 12) {
                                        ForEach(1...5, id: \.self) { score in
                                            Button {
                                                joke.relatabilityScore = joke.relatabilityScore == score ? 0 : score
                                            } label: {
                                                Image(systemName: score <= joke.relatabilityScore ? "person.fill" : "person")
                                                    .font(.title2)
                                                    .foregroundColor(score <= joke.relatabilityScore ? accentColor : .gray.opacity(DS.Opacity.scrim))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.subheadline)
                                Text("Structure & Notes")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(accentColor)
                        }
                        .padding(.horizontal, 16)
                        
                        // Opening Roast / Backup Assignment Section
                        DisclosureGroup(isExpanded: $showOpeningAssignment) {
                            VStack(spacing: 16) {
                                // Opening Roast toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Mark as Opening Roast")
                                            .font(.subheadline.weight(.medium))
                                        Text(joke.isOpeningRoast ? "\(openerLabel(for: joke)) for this target" : "Use this as a headline roast for this target")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { joke.isOpeningRoast },
                                        set: { newValue in
                                            joke.isOpeningRoast = newValue
                                            if newValue {
                                                // Clear parent if becoming opening
                                                joke.parentOpeningRoastID = nil
                                            }
                                        }
                                    ))
                                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                    .labelsHidden()
                                }
                                .padding(12)
                                .background(joke.isOpeningRoast ? Color.bitbinderAccent.opacity(DS.Opacity.light) : Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous))
                                
                                // Backup assignment (only if not an opening roast)
                                if !joke.isOpeningRoast {
                                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                        Text("Assign as Backup For")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                        
                                        if openingRoastsForTarget.isEmpty {
                                            HStack {
                                                Image(systemName: "info.circle")
                                                    .foregroundColor(.secondary)
                                                Text("No opening roasts set for this target yet")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(DS.Spacing.md)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
                                        } else {
                                            RoastSelectionRow(
                                                title: "None (Unassigned)",
                                                isSelected: joke.parentOpeningRoastID == nil,
                                                accentColor: .bitbinderAccent
                                            ) {
                                                joke.parentOpeningRoastID = nil
                                            }
                                            
                                            ForEach(Array(openingRoastsForTarget.enumerated()), id: \.element.id) { index, opening in
                                                RoastSelectionRow(
                                                    title: "\(openerLabel(for: opening)): \(opening.truncatedPreview(40))",
                                                    leadingNumber: index + 1,
                                                    isSelected: joke.parentOpeningRoastID == opening.id,
                                                    accentColor: .bitbinderAccent
                                                ) {
                                                    joke.parentOpeningRoastID = opening.id
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: joke.isOpeningRoast ? "star.circle.fill" : "arrow.turn.down.right")
                                    .font(.subheadline)
                                    .foregroundColor(Color.accentColor)
                                Text(joke.isOpeningRoast ? openerLabel(for: joke) : (joke.parentOpeningRoastID != nil ? "Backup Roast" : "Set Type"))
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(Color.accentColor)
                        }
                        .padding(.horizontal, 16)
                        
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                showAdvancedOptions = joke.hasStructure || !joke.performanceNotes.isEmpty
                showOpeningAssignment = joke.isOpeningRoast || joke.parentOpeningRoastID != nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveJoke()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(canSave ? accentColor : .secondary)
                    .disabled(!canSave)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Save") {
                            saveJoke()
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(canSave ? accentColor : .secondary)
                        .disabled(!canSave)
                    }
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func saveJoke() {
        guard joke.isValid else {
            saveErrorMessage = "This roast was deleted and cannot be saved."
            showSaveError = true
            return
        }
        
        joke.dateModified = Date()
        do {
            try modelContext.save()
            dismiss()
        } catch {
            #if DEBUG
            print("⚠️ [EditRoastJokeView] Failed to save: \(error)")
            #endif
            saveErrorMessage = "Could not save changes: \(error.localizedDescription)"
            showSaveError = true
        }
    }

    private var copyableJokeText: String {
        var parts: [String] = []
        if !joke.setup.isEmpty {
            parts.append(joke.setup)
        }
        parts.append(joke.content)
        if !joke.punchline.isEmpty {
            parts.append(joke.punchline)
        }
        if !joke.performanceNotes.isEmpty {
            parts.append("Notes: \(joke.performanceNotes)")
        }
        return parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pasteIntoJoke() {
        guard let pasted = UIPasteboard.general.string,
              !pasted.isEmpty else { return }
        if joke.content.isEmpty {
            joke.content = pasted
        } else {
            joke.content += "\n\(pasted)"
        }
    }
}

// MARK: - Edit Roast Target Sheet

struct EditRoastTargetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var target: RoastTarget

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @FocusState private var focusedField: Field?

    private var accentColor: Color { FirePalette.core }

    private enum Field: Hashable {
        case name
        case notes
        case instagram
        case tiktok
        case x
        case facebook
        case website
        case detail(Int)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            RoastEditableAvatar(
                                uiImage: photoImage,
                                photoData: target.photoData,
                                accentColor: accentColor
                            )
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Change target photo")
                }

                Section("Name") {
                    TextField("Name", text: $target.name)
                        .font(.headline)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                }

                Section("Notes (optional)") {
                    TextField("e.g. friend, coworker, celebrity...", text: $target.notes)
                        .focused($focusedField, equals: .notes)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .instagram }
                }

                Section("Social media (optional)") {
                    TextField("@instagram", text: $target.instagramHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .instagram)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .tiktok }
                        .accessibilityLabel("Instagram handle")

                    TextField("@tiktok", text: $target.tiktokHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .tiktok)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .x }
                        .accessibilityLabel("TikTok handle")

                    TextField("@x or @twitter", text: $target.xHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .x)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .facebook }
                        .accessibilityLabel("X handle")

                    TextField("facebook.com/profile", text: $target.facebookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .facebook)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .website }
                        .accessibilityLabel("Facebook profile")

                    TextField("website or link", text: $target.websiteURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .website)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .detail(0) }
                        .accessibilityLabel("Website or social link")
                }
                
                Section {
                    ForEach(Array(target.traits.enumerated()), id: \.offset) { index, _ in
                        if index < target.traits.count {
                            HStack {
                                TextField("e.g. works in finance, always late...", text: Binding(
                                    get: { index < target.traits.count ? target.traits[index] : "" },
                                    set: { newValue in
                                        if index < target.traits.count {
                                            target.traits[index] = newValue
                                        }
                                    }
                                ))
                                .focused($focusedField, equals: .detail(index))
                                .submitLabel(.done)
                                if target.traits.count > 1 {
                                    Button {
                                        if index < target.traits.count {
                                            target.traits.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(Color.destructive.opacity(DS.Opacity.heavy))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove detail")
                                }
                            }
                        }
                    }
                    Button {
                        target.traits.append("")
                    } label: {
                        Label("Add another", systemImage: "plus.circle")
                            .foregroundColor(accentColor)
                    }
                } header: {
                    Text("What do you know about them?")
                } footer: {
                    Text("Bullet points — habits, quirks, job, looks, anything roastable.")
                }
            }
            .roastFormTheme()
            .navigationTitle("Edit Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Photo data is already set via onChange handler with downscaling
                        normalizeSocialFields()
                        target.dateModified = Date()
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            #if DEBUG
                            print(" [EditRoastTargetView] Failed to save: \(error)")
                            #endif
                            saveErrorMessage = "Could not save changes: \(error.localizedDescription)"
                            showSaveError = true
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .task(id: selectedPhoto) {
                await loadSelectedPhoto()
            }
            .onAppear {
                focusedField = .name
                if let photoData = target.photoData {
                    photoImage = UIImage(data: photoData)
                }
            }
        }
    }

    private func normalizeSocialFields() {
        target.instagramHandle = normalizedHandle(target.instagramHandle)
        target.tiktokHandle = normalizedHandle(target.tiktokHandle)
        target.xHandle = normalizedHandle(target.xHandle)
        target.facebookURL = target.facebookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        target.websiteURL = target.websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedHandle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        guard let data = try? await selectedPhoto.loadTransferable(type: Data.self),
              !Task.isCancelled,
              let original = UIImage(data: data) else {
            return
        }

        let scaled = RoastTargetPhotoHelper.downscale(original, maxLongEdge: 800)
        let scaledData = scaled.jpegData(compressionQuality: 0.8)

        await MainActor.run {
            guard target.photoData != scaledData else {
                self.selectedPhoto = nil
                return
            }
            target.photoData = scaledData
            photoImage = scaled
            self.selectedPhoto = nil
        }
    }
}

// MARK: - Export Sheet

struct RoastExportSheet: View {
    let target: RoastTarget
    @Binding var exportedURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var exportFormat: ExportFormat = .text
    @State private var includeStructure = true
    @State private var includeNotes = true
    @State private var isExporting = false
    @State private var showShareSheet = false
    
    enum ExportFormat: String, CaseIterable {
        case text = "Plain Text"
        case pdf = "PDF"
        case markdown = "Markdown"
        
        var icon: String {
            switch self {
            case .text: return "doc.text"
            case .pdf: return "doc.richtext"
            case .markdown: return "text.badge.checkmark"
            }
        }
    }

    private func appendTextBody(for joke: RoastJoke, to text: inout String, indent: String = "") {
        if includeStructure && joke.hasStructure {
            if !joke.setup.isEmpty {
                text += "\(indent)SETUP: \(joke.setup)\n"
            }
            text += "\(indent)\(joke.content)\n"
            if !joke.punchline.isEmpty {
                text += "\(indent)PUNCHLINE: \(joke.punchline)\n"
            }
        } else {
            text += "\(indent)\(joke.content)\n"
        }

        if includeNotes && !joke.performanceNotes.isEmpty {
            text += "\(indent)NOTES: \(joke.performanceNotes)\n"
        }
    }

    private func appendMarkdownBody(for joke: RoastJoke, to md: inout String) {
        if includeStructure && joke.hasStructure {
            if !joke.setup.isEmpty {
                md += "**Setup:** \(joke.setup)\n\n"
            }
            md += "\(joke.content)\n\n"
            if !joke.punchline.isEmpty {
                md += "**Punchline:** \(joke.punchline)\n\n"
            }
        } else {
            md += "\(joke.content)\n\n"
        }

        if includeNotes && !joke.performanceNotes.isEmpty {
            md += "*Notes: \(joke.performanceNotes)*\n\n"
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Label(format.rawValue, systemImage: format.icon)
                                .tag(format)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                
                Section("Include") {
                    Toggle("Joke Structure (Setup/Punchline)", isOn: $includeStructure)
                    Toggle("Performance Notes", isOn: $includeNotes)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.headline)
                        Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s") for \(target.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Export Roasts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        exportRoasts()
                    }
                    .disabled(isExporting)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
    
    private func exportRoasts() {
        isExporting = true
        
        Task {
            let url: URL?
            
            switch exportFormat {
            case .text:
                url = exportAsText()
            case .pdf:
                url = PDFExportService.exportRoastsToPDF(targets: [target], fileName: "Roasts_\(target.name)")
            case .markdown:
                url = exportAsMarkdown()
            }
            
            await MainActor.run {
                isExporting = false
                if let url = url {
                    exportedURL = url
                    showShareSheet = true
                }
            }
        }
    }
    
    private func exportGroups() -> [ExportGroup] {
        let allJokes = target.sortedJokes
        let openers = allJokes.filter { $0.isOpeningRoast }.sorted { $0.displayOrder < $1.displayOrder }
        let assignedIDs = Set(openers.map(\.id))

        var groups: [ExportGroup] = []

        for opener in openers {
            let backups = allJokes.filter { $0.parentOpeningRoastID == opener.id }
                .sorted { $0.displayOrder < $1.displayOrder }
            groups.append(ExportGroup(opener: opener, backups: backups))
        }

        let unassigned = allJokes.filter { joke in
            !joke.isOpeningRoast && (joke.parentOpeningRoastID == nil || !assignedIDs.contains(joke.parentOpeningRoastID!))
        }
        for joke in unassigned {
            groups.append(ExportGroup(opener: joke, backups: []))
        }

        return groups
    }

    private struct ExportGroup {
        let opener: RoastJoke
        let backups: [RoastJoke]
    }

    private func exportAsText() -> URL? {
        var text = "ROASTS FOR \(target.name.uppercased())\n"
        text += String(repeating: "=", count: 40) + "\n\n"

        if !target.notes.isEmpty {
            text += "About: \(target.notes)\n\n"
        }

        if !target.traits.isEmpty {
            text += "Traits:\n"
            for trait in target.traits {
                text += "• \(trait)\n"
            }
            text += "\n"
        }

        text += String(repeating: "-", count: 40) + "\n\n"

        let groups = exportGroups()

        for (index, group) in groups.enumerated() {
            if group.opener.isOpeningRoast {
                text += "\(index + 1). OPENER \(openerIndex(for: group.opener, in: groups))\n"
            } else {
                text += "\(index + 1).\n"
            }
            appendTextBody(for: group.opener, to: &text, indent: "   ")

            if !group.backups.isEmpty {
                text += "   BACKUPS:\n"
                for (backupIndex, backup) in group.backups.enumerated() {
                    text += "   ↳ \(index + 1)\(Character(UnicodeScalar(65 + backupIndex)!)) BACKUP \(backupIndex + 1)\n"
                    appendTextBody(for: backup, to: &text, indent: "      ")
                }
            }

            text += "\n"
        }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "Roasts_\(target.name.replacingOccurrences(of: " ", with: "_")).txt"
        let fileURL = documentsURL.appendingPathComponent(fileName)

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("⚠️ Failed to write text export: \(error)")
            return nil
        }
    }

    private func exportAsMarkdown() -> URL? {
        var md = "# Roasts for \(target.name)\n\n"

        if !target.notes.isEmpty {
            md += "> \(target.notes)\n\n"
        }

        if !target.traits.isEmpty {
            md += "## Traits\n"
            for trait in target.traits {
                md += "- \(trait)\n"
            }
            md += "\n"
        }

        let groups = exportGroups()

        for (index, group) in groups.enumerated() {
            let label = group.opener.isOpeningRoast ? "Opener \(openerIndex(for: group.opener, in: groups))" : "Roast"
            md += "## \(index + 1). \(label)\(group.opener.title.isEmpty ? "" : " — \(group.opener.title)")\n\n"
            appendMarkdownBody(for: group.opener, to: &md)

            if group.opener.relatabilityScore > 0 {
                md += "`Relatability: \(group.opener.relatabilityScore)/5`\n\n"
            }

            if !group.backups.isEmpty {
                md += "### Backups\n\n"
                for (backupIndex, backup) in group.backups.enumerated() {
                    md += "#### \(index + 1)\(Character(UnicodeScalar(65 + backupIndex)!)) Backup \(backupIndex + 1)\n\n"
                    appendMarkdownBody(for: backup, to: &md)
                }
            }

            md += "---\n\n"
        }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "Roasts_\(target.name.replacingOccurrences(of: " ", with: "_")).md"
        let fileURL = documentsURL.appendingPathComponent(fileName)

        do {
            try md.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("⚠️ Failed to write markdown export: \(error)")
            return nil
        }
    }

    private func openerIndex(for joke: RoastJoke, in groups: [ExportGroup]) -> Int {
        var count = 0
        for group in groups {
            if group.opener.isOpeningRoast {
                count += 1
                if group.opener.id == joke.id { return count }
            }
        }
        return count
    }
}
