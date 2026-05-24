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
    @AppStorage("showFullContent") private var showFullContent = true
    @AppStorage("roastSortOption") private var sortOption: RoastJokeSortOption = .newest
    @AppStorage("roastTargetDisplayMode") private var roastTargetDisplayModeRaw = RoastTargetDisplayMode.cards.rawValue
    @AppStorage("roastTargetHeaderCollapsed") private var isHeaderCollapsed = true
    @AppStorage("roastTextScale") private var roastTextScale = 1.0
    @Bindable var target: RoastTarget
    
    // Query all non-deleted roast jokes for this target - SwiftData will auto-update the view
    @Query private var allRoastJokes: [RoastJoke]

    @State private var showingAddRoast = false
    @State private var editingJoke: RoastJoke?
    @State private var showingEditTarget = false
    @State private var showingTalkToText = false
    @State private var showingRecordingSheet = false
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
    private var roastBodyFontSize: CGFloat { 17 * roastTextScale }
    private var roastSupportFontSize: CGFloat { max(12, 14 * roastTextScale) }
    private var displayMode: RoastTargetDisplayMode {
        RoastTargetDisplayMode(rawValue: roastTargetDisplayModeRaw) ?? .cards
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

    private enum RoastTargetDisplayMode: String {
        case cards
        case preview
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
            filterChips

            if showingFontSlider {
                fontSliderBar
            }

            Divider().opacity(0.3)

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
        .sheet(item: $editingJoke) { joke in
            EditRoastJokeView(joke: joke)
        }
        .sheet(isPresented: $showingEditTarget) {
            EditRoastTargetView(target: target)
        }
        .sheet(isPresented: $showingTalkToText) {
            TalkToTextRoastView(target: target)
        }
        .sheet(isPresented: $showingRecordingSheet) {
            RecordRoastSetView(target: target)
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
        let heat = min(100, target.jokeCount * 4)
        return ZStack(alignment: .topTrailing) {
            if heat >= 60 {
                Circle()
                    .fill(RadialGradient(
                        colors: [FirePalette.core.opacity(DS.Opacity.medium), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    ))
                    .frame(width: 200, height: 200)
                    .blur(radius: 20)
                    .offset(x: 40, y: -30)
            }

            VStack(spacing: isHeaderCollapsed ? DS.Spacing.sm : DS.Spacing.md) {
                HStack(alignment: .center, spacing: DS.Spacing.md) {
                    if isHeaderCollapsed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(safeTargetName)
                                .font(.headline.bold())
                                .foregroundColor(FirePalette.text)

                            HeatBar(heat: heat)
                                .frame(width: 140)

                            Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s")")
                                .font(.caption.weight(.medium))
                                .foregroundColor(FirePalette.sub)
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

                            HeatBar(heat: heat)
                                .frame(width: 200)
                                .padding(.top, 2)
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
        ScrollView {
            LazyVStack(spacing: 16) {
                targetWorkspaceSection

                if displayGroups.isEmpty {
                    emptyState
                } else {
                    if displayMode == .preview {
                        previewModeView
                    } else {
                        ForEach(displayGroups) { group in
                            roastGroupView(group)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .trailing))
                                ))
                        }
                    }

                    if displayMode == .cards {
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
                }
            }
            .padding(.vertical, 8)
        }
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
                subtitle: "Facts, quirks, habits, history, look, job, contradictions, anything roastable.",
                icon: "list.bullet.clipboard"
            )

            if target.traits.isEmpty {
                Text("Add bullet points about \(safeTargetName).")
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
                            }
                            .padding(DS.Spacing.sm)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous))

                Button {
                    addTraitFromInput()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(canAddTrait ? accentColor : FirePalette.sub)
                }
                .buttonStyle(.plain)
                .disabled(!canAddTrait)
            }
        }
        .padding(DS.Spacing.lg)
        .background(FirePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Corner.lg, style: .continuous)
                .strokeBorder(FirePalette.edge, lineWidth: 0.5)
        )
    }

    private var roastScratchpadSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            workspaceHeader(
                title: "Roast Notepad",
                subtitle: "Flesh out loose ideas here. Highlight a line or phrase, then promote it to a roast.",
                icon: "square.and.pencil"
            )

            SelectableRoastNotepad(
                text: $target.notes,
                selectedText: $selectedScratchpadText,
                placeholder: "Start writing premises, angles, alternate punchlines, tags, or rough roast ideas..."
            )
            .frame(minHeight: 180)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous)
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
        .padding(DS.Spacing.lg)
        .background(FirePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Corner.lg, style: .continuous)
                .strokeBorder(FirePalette.edge, lineWidth: 0.5)
        )
    }

    private func workspaceHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundColor(FirePalette.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(FirePalette.sub)
            }
        }
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
            )
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 3)
            .padding(.horizontal, 16)
        } else {
            // Standalone roast — no group wrapper, no label
            roastCard(for: group.opener)
        }
    }

    private func roastCard(for joke: RoastJoke, nested: Bool = false, embeddedInGroup: Bool = false) -> some View {
        DraggableRoastCard(
            joke: joke,
            showFullContent: showFullContent,
            accentColor: accentColor,
            embeddedInGroup: embeddedInGroup,
            onTap: {
                editingJoke = joke
            },
            onTrash: {
                withAnimation(.easeOut(duration: 0.25)) {
                    trashJoke(joke)
                }
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
                        label: group.opener.isOpeningRoast ? openerLabel(for: group.opener).uppercased() : "ROAST",
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
            HStack(spacing: 8) {
                Text(sequence)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundColor(FirePalette.text)
                Text(label)
                    .font(.caption2.weight(.bold))
            }
                .foregroundColor(accentColor)

            if !joke.setup.isEmpty {
                Text(joke.setup)
                    .font(.system(size: roastBodyFontSize, weight: .semibold, design: .serif))
                    .foregroundColor(FirePalette.text)
                    .lineSpacing(6)
            }

            Text(joke.content)
                .font(.system(size: roastBodyFontSize, weight: .regular, design: .serif))
                .foregroundColor(FirePalette.text)
                .lineSpacing(7)

            if !joke.punchline.isEmpty {
                Text("Punchline: \(joke.punchline)")
                    .font(.system(size: roastSupportFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(FirePalette.sub)
            }

            if !joke.performanceNotes.isEmpty {
                Text("Notes: \(joke.performanceNotes)")
                    .font(.system(size: roastSupportFontSize, weight: .regular, design: .rounded))
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
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingAddRoast = true
            } label: {
                Image(systemName: "plus")
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Section("View") {
                    Button {
                        roastTargetDisplayModeRaw = RoastTargetDisplayMode.cards.rawValue
                    } label: {
                        Label("Grouped Cards", systemImage: displayMode == .cards ? "checkmark.rectangle.stack.fill" : "rectangle.stack")
                    }

                    Button {
                        roastTargetDisplayModeRaw = RoastTargetDisplayMode.preview.rawValue
                    } label: {
                        Label("Preview Text", systemImage: displayMode == .preview ? "checkmark.circle.fill" : "text.page")
                    }

                    Button(action: { showFullContent.toggle() }) {
                        Label(showFullContent ? "Compact View" : "Full Content", systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                    }
                }

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
                    Button(action: { showingRecordingSheet = true }) {
                        Label("Record Set", systemImage: "record.circle")
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
            updateSelection(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateSelection(from: textView)
        }

        private func updateSelection(from textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0,
                  let textRange = Range(range, in: textView.text) else {
                selectedText = ""
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
        cardContent
            .background(
                Group {
                    if embeddedInGroup {
                        Color.clear
                    } else {
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .fill(Color(FirePalette.card))
                            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                    }
                }
            )
            .overlay(
                Group {
                    if !embeddedInGroup {
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                    }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
            .contextMenu {
                contextMenuContent
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
            onToggleOpening?()
        } label: {
            Label(joke.isOpeningRoast ? "Remove as Opener" : "Mark as Opening Roast", systemImage: joke.isOpeningRoast ? "star.circle" : "star.circle.fill")
        }

        if joke.isOpeningRoast && openerCount > 1 {
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
                Label("Change Opener Number", systemImage: "arrow.up.arrow.down")
            }
        }
        
        if !joke.isOpeningRoast && !openingRoastsForTarget.isEmpty {
            Button {
                onAssignAsBackup?(nil)
            } label: {
                Label(
                    joke.parentOpeningRoastID == nil ? "Backup: None (Unassigned)" : "Remove Backup Assignment",
                    systemImage: joke.parentOpeningRoastID == nil ? "checkmark.circle" : "arrow.uturn.backward.circle"
                )
            }

            ForEach(Array(openingRoastsForTarget.enumerated()), id: \.element.id) { _, opening in
                Button {
                    onAssignAsBackup?(opening.id)
                } label: {
                    Label(
                        joke.parentOpeningRoastID == opening.id
                            ? "Backup for \(openerLabel(for: opening))"
                            : "Assign to \(openerLabel(for: opening))",
                        systemImage: joke.parentOpeningRoastID == opening.id ? "checkmark.circle.fill" : "arrow.turn.down.right"
                    )
                }
            }
        }
        
        Divider()
        
        Button {
            onTap?()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        
        Divider()
        
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
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
        guard let targetName = joke.target?.name else { return [] }
        return allRoastJokes.filter { roast in
            guard !roast.isTrashed,
                  roast.isOpeningRoast,
                  roast.id != joke.id,
                  let name = roast.target?.name else { return false }
            return name == targetName
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
                            Text("ROAST")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $joke.content)
                                .focused($isContentFocused)
                                .frame(minHeight: 120)
                                .padding(DS.Spacing.md)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous))
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
                                        let count = joke.target?.openingRoastCount ?? 3
                                        Text(joke.isOpeningRoast ? "\(openerLabel(for: joke)) for this target" : "One of \(count) main roast\(count == 1 ? "" : "s") for this target")
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

    private var accentColor: Color { FirePalette.core }

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
                }

                Section("Name") {
                    TextField("Name", text: $target.name)
                        .font(.headline)
                }

                Section("Notes (optional)") {
                    TextField("e.g. friend, coworker, celebrity...", text: $target.notes)
                }
                
                Section {
                    Picker("Main Roasts", selection: $target.openingRoastCount) {
                        ForEach(1...10, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Performance Settings")
                } footer: {
                    Text("Number of main opening roasts to prepare for this target during live performance.")
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Photo data is already set via onChange handler with downscaling
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
                if let photoData = target.photoData {
                    photoImage = UIImage(data: photoData)
                }
            }
        }
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
            let label = group.opener.isOpeningRoast ? "OPENER \(openerIndex(for: group.opener, in: groups))" : "ROAST"
            text += "\(index + 1). \(label)\n"
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
