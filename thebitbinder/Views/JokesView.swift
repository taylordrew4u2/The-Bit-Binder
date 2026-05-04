//
//  JokesView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Identifiable wrapper for the URLs the user just picked in the document
/// picker, so `.sheet(item:)` can present the extraction-hints preflight.
struct PendingDocumentImport: Identifiable {
    let id = UUID()
    let urls: [URL]

    var summary: String {
        if urls.count == 1 {
            return urls[0].lastPathComponent
        }
        return "\(urls.count) files"
    }
}

struct ImportErrorMessage: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct JokesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Joke> { !$0.isTrashed }, sort: \Joke.dateModified, order: .reverse) private var jokes: [Joke]
    @Query(filter: #Predicate<JokeFolder> { !$0.isTrashed }) private var folders: [JokeFolder]
    @Query(filter: #Predicate<RoastTarget> { !$0.isTrashed }, sort: \RoastTarget.dateModified, order: .reverse) private var roastTargets: [RoastTarget]
    @Query(sort: \BrainstormIdea.dateCreated, order: .reverse) private var brainstormIdeas: [BrainstormIdea]
    
    // Roast mode — toggled from Settings
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    // Roast sheet state
    @State private var showingAddRoastTarget = false
    @State private var roastTargetToDelete: RoastTarget?
    @State private var showingDeleteRoastAlert = false
    
    @AppStorage("jokesViewMode") private var viewMode: JokesViewMode = .list
    @AppStorage("roastViewMode") private var roastViewMode: JokesViewMode = .list
    @AppStorage("showFullContent") private var showFullContent = true
    @AppStorage("jokesGridScale") private var jokesGridScale: Double = 1.0
    @AppStorage("roastGridScale") private var roastGridScale: Double = 1.0
    @GestureState private var jokesPinchMagnification: CGFloat = 1.0
    @GestureState private var roastPinchMagnification: CGFloat = 1.0

    // Pinch-to-zoom
    private var effectiveJokesScale: CGFloat {
        min(max(CGFloat(jokesGridScale) * jokesPinchMagnification, 0.5), 2.0)
    }
    private var effectiveRoastScale: CGFloat {
        min(max(CGFloat(roastGridScale) * roastPinchMagnification, 0.5), 2.0)
    }
    private var jokesPinchGesture: some Gesture {
        MagnifyGesture()
            .updating($jokesPinchMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let newScale = CGFloat(jokesGridScale) * value.magnification
                jokesGridScale = Double(min(max(newScale, 0.5), 2.0))
            }
    }
    private var roastPinchGesture: some Gesture {
        MagnifyGesture()
            .updating($roastPinchMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let newScale = CGFloat(roastGridScale) * value.magnification
                roastGridScale = Double(min(max(newScale, 0.5), 2.0))
            }
    }

    // Grid columns derived from scale
    private var jokesColumns: [GridItem] {
        let count = max(2, Int(4 / effectiveJokesScale))
        return Array(repeating: GridItem(.flexible(), spacing: 0), count: count)
    }
    private var roastColumns: [GridItem] {
        let count = max(2, Int(4 / effectiveRoastScale))
        return Array(repeating: GridItem(.flexible(), spacing: 0), count: count)
    }
    
    @State private var showingAddJoke = false
    @State private var showingScanner = false
    @State private var showingImagePicker = false
    @State private var showingFilePicker = false
    @State private var showingCreateFolder = false
    @State private var showingAutoOrganize = false
    @State private var showingGuidedOrganize = false
    @State private var showingImportHistory = false
    @State private var showingExportAlert = false
    @State private var selectedFolder: JokeFolder?
    @State private var showRecentlyAdded = false
    @State private var searchText = ""
    @State private var exportedPDFURL: URL?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    // TODO: Consider grouping the 16+ import-related @State vars below into a
    // single `ImportState` struct to reduce view-body invalidation surface.
    // Deferred because the binding plumbing through JokesSheetsModifier and
    // JokesAlertsModifier makes the refactor non-trivial.
    @State private var isProcessingImages = false
    @State private var processingCurrent: Int = 0
    @State private var processingTotal: Int = 0
    @State private var importSummary: (added: Int, skipped: Int) = (0, 0)
    @State private var showingImportSummary = false
    @State private var folderPendingDeletion: JokeFolder?
    @State private var showingDeleteFolderAlert = false
    @State private var showingMoveJokesSheet = false
    @State private var showingAudioImport = false
    @State private var showingTalkToText = false
    @State private var showingGagGrabber = false
    
    @State private var reviewCandidates: [JokeImportCandidate] = []
    @State private var showingReviewSheet = false
    @State private var possibleDuplicates: [String] = []
    @State private var unresolvedImportFragments: [UnresolvedImportFragment] = []
    
    // Live import progress
    @State private var importStatusMessage = ""
    @State private var importedJokeNames: [String] = []
    @State private var importFileCount = 0
    @State private var importFileIndex = 0
    
    // Smart import review
    @State private var smartImportResult: ImportPipelineResult?
    @State private var importError: Error? = nil
    @State private var showingImportError = false

    // Pre-flight extraction-hints sheet. `pendingDocumentImport` is set when
    // the user picks files via the document picker; presenting the sheet
    // gathers structured hints before the pipeline runs.
    @State private var pendingDocumentImport: PendingDocumentImport?
    
    // Batch select/delete mode
    @State private var isSelectMode = false
    @State private var selectedJokeIDs: Set<UUID> = []
    
    // Navigation state for grid items (prevents accidental taps)
    @State private var selectedJokeForDetail: Joke?
    
    // Move-to-folder via long-press context menu
    @State private var jokeToMove: Joke?
    
    // Persistence error surfacing
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    
    // Performance: Debounced search and cached filtered results
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cachedFilteredJokes: [Joke] = []

    // MARK: - The Hits Button
    // This computed property returns the count for the chips
    private var hitsCount: Int {
        jokes.filter { $0.isHit }.count
    }
    // State for showing The Hits filter
    @State private var showingHitsFilter = false

    // MARK: - Open Mic
    private var openMicCount: Int {
        jokes.filter { $0.isOpenMic }.count
    }
    @State private var showingOpenMicFilter = false


    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // The Hits chip
                TheHitsChip(
                    count: hitsCount,
                    isSelected: showingHitsFilter,
                    roastMode: roastMode,
                    action: {
                        showingHitsFilter.toggle()
                        if showingHitsFilter {
                            selectedFolder = nil
                            showRecentlyAdded = false
                            showingOpenMicFilter = false
                        }
                    }
                )
                
                // Open Mic chip
                OpenMicChip(
                    count: openMicCount,
                    isSelected: showingOpenMicFilter,
                    roastMode: roastMode,
                    action: {
                        showingOpenMicFilter.toggle()
                        if showingOpenMicFilter {
                            selectedFolder = nil
                            showRecentlyAdded = false
                            showingHitsFilter = false
                        }
                    }
                )
                
                // All Jokes
                FolderChip(
                    name: "All",
                    icon: "tray.full.fill",
                    isSelected: selectedFolder == nil && !showRecentlyAdded && !showingHitsFilter && !showingOpenMicFilter,
                    roastMode: roastMode,
                    action: {
                        selectedFolder = nil
                        showRecentlyAdded = false
                        showingHitsFilter = false
                        showingOpenMicFilter = false
                    }
                )
                
                // Recently Added
                FolderChip(
                    name: "Recent",
                    icon: "clock.fill",
                    isSelected: showRecentlyAdded && !showingHitsFilter && !showingOpenMicFilter,
                    roastMode: roastMode,
                    action: {
                        showRecentlyAdded = true
                        selectedFolder = nil
                        showingHitsFilter = false
                        showingOpenMicFilter = false
                    }
                )
                
                // Folder chips
                ForEach(folders) { folder in
                    FolderChip(
                        name: folder.name,
                        isSelected: selectedFolder?.id == folder.id && !showRecentlyAdded && !showingHitsFilter && !showingOpenMicFilter,
                        roastMode: roastMode,
                        action: {
                            selectedFolder = folder
                            showRecentlyAdded = false
                            showingHitsFilter = false
                            showingOpenMicFilter = false
                        }
                    )
                    .dropDestination(for: JokeDragItem.self) { items, _ in
                        handleJokeDrop(items, onto: folder)
                        return true
                    } isTargeted: { isTargeted in
                        // Visual feedback handled by SwiftUI automatically
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            folderPendingDeletion = folder
                            showingDeleteFolderAlert = true
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private var emptyState: some View {
        JokesEmptyState(
            roastMode: roastMode,
            hasFilter: selectedFolder != nil || showRecentlyAdded || showingHitsFilter || showingOpenMicFilter || !searchText.isEmpty,
            onAddJoke: { showingAddJoke = true }
        )
    }

    // MARK: - Roast Section

    @ViewBuilder
    private var roastSection: some View {
        if roastTargets.isEmpty {
            RoastColdStateView(onAddTarget: { showingAddRoastTarget = true })
        } else {
            roastHomeView
        }
    }

    /// The "fire home" — header + ranked subject cards over the fire bg.
    @ViewBuilder
    private var roastHomeView: some View {
        let maxHeat = roastTargets.map { targetHeat($0) }.max() ?? 0
        let isCold = maxHeat < 30 && roastTargets.count <= 1

        ScrollView {
            VStack(spacing: 0) {
                RoastHomeHeader(
                    subjectCount: roastTargets.count,
                    hotCount: roastTargets.filter { targetHeat($0) >= 60 }.count,
                    isCold: isCold
                )

                let ranked = roastTargets.sorted { targetHeat($0) > targetHeat($1) }
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, target in
                    NavigationLink(destination: RoastTargetDetailView(target: target)) {
                        RoastSubjectCard(
                            target: target,
                            heat: targetHeat(target),
                            rank: index + 1
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            roastTargetToDelete = target
                            showingDeleteRoastAlert = true
                        } label: {
                            Label("Delete Target", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showingAddRoastTarget = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("Add subject")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(FirePalette.core)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(FirePalette.core.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(FirePalette.bg.ignoresSafeArea())
    }

    private func targetHeat(_ target: RoastTarget) -> Int {
        let bits = target.jokeCount
        let base = bits * 4
        return min(100, max(0, base))
    }

    
    // A stable key that changes whenever any *filter input* changes.
    // Used by .task(id:) to re-run filtering only when the user changes a
    // filter — NOT on every joke count change. Data-count changes are
    // handled separately via .onChange(of: jokes.count).
    private var filterKey: String {
        let folder = selectedFolder?.id.uuidString ?? "nil"
        let hits   = showingHitsFilter ? "1" : "0"
        let openMic = showingOpenMicFilter ? "1" : "0"
        let recent = showRecentlyAdded  ? "1" : "0"
        let search = debouncedSearchText
        return "\(folder)|\(hits)|\(openMic)|\(recent)|\(search)"
    }

    var filteredJokes: [Joke] { cachedFilteredJokes }

    private func rebuildFilteredJokes() {
        let base: [Joke]
        if showingHitsFilter {
            base = jokes.filter { $0.isHit }
        } else if showingOpenMicFilter {
            base = jokes.filter { $0.isOpenMic }
        } else if showRecentlyAdded {
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            base = jokes.filter { $0.dateCreated >= sevenDaysAgo }
        } else if let folder = selectedFolder {
            let folderId = folder.id
            base = jokes.filter { ($0.folders ?? []).contains(where: { $0.id == folderId }) }
        } else {
            base = jokes
        }

        let trimmed = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [Joke]
        if trimmed.isEmpty {
            filtered = base
        } else {
            let lower = trimmed.lowercased()
            filtered = base.filter { matchesSearch($0, lower: lower) }
        }

        if showRecentlyAdded {
            cachedFilteredJokes = filtered.sorted { $0.dateCreated > $1.dateCreated }
        } else {
            cachedFilteredJokes = filtered
        }
    }
    
    var body: some View {
        mainContent
            .searchable(text: $searchText, prompt: roastMode ? "Search targets" : "Search jokes")
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear { checkPendingVoiceMemoImports() }
            .toolbar { combinedToolbarContent }
                .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotos, matching: .images, preferredItemEncoding: .automatic)
                .onChange(of: selectedPhotos) { oldValue, newValue in
                    Task { await processSelectedPhotos(newValue) }
                }
                .modifier(JokesSheetsModifier(
                    showingAddJoke: $showingAddJoke,
                    showingScanner: $showingScanner,
                    showingCreateFolder: $showingCreateFolder,
                    showingAutoOrganize: $showingAutoOrganize,
                    showingGuidedOrganize: $showingGuidedOrganize,
                    showingAudioImport: $showingAudioImport,
                    showingTalkToText: $showingTalkToText,
                    showingFilePicker: $showingFilePicker,
                    showingAddRoastTarget: $showingAddRoastTarget,
                    showingMoveJokesSheet: $showingMoveJokesSheet,
                    showingReviewSheet: $showingReviewSheet,
                    selectedFolder: selectedFolder,
                    folders: folders,
                    folderPendingDeletion: $folderPendingDeletion,
                    reviewCandidates: reviewCandidates,
                    possibleDuplicates: possibleDuplicates,
                    unresolvedFragments: unresolvedImportFragments,
                    processScannedImages: processScannedImages,
                    processDocuments: processDocuments,
                    moveJokes: moveJokes,
                    deleteFolder: deleteFolder
                ))
                .sheet(isPresented: $showingImportHistory) {
                    ImportBatchHistoryView()
                }
                .sheet(isPresented: $showingGagGrabber) {
                    HybridGagGrabberSheet()
                }
                .fullScreenCover(item: $smartImportResult) { result in
                    SmartImportReviewView(
                        importResult: result,
                        selectedFolder: selectedFolder,
                        onComplete: {
                            smartImportResult = nil
                        }
                    )
                }
                .sheet(item: $pendingDocumentImport) { pending in
                    ExtractionHintsPreflightSheet(
                        fileNameSummary: pending.summary,
                        onContinue: { hints in
                            runDocumentImport(urls: pending.urls, hints: hints)
                        },
                        onSkip: {
                            runDocumentImport(urls: pending.urls, hints: .unspecified)
                        }
                    )
                }
                .alert("Import Couldn't Complete", isPresented: $showingImportError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    if let aiError = importError as? AIExtractionFailedError {
                        Text("GagGrabber couldn't extract jokes from your file.\n\nReason: \(aiError.reason)\n\nWhat to try:\n• Make sure your file has clear line breaks between jokes.\n• Try a different file format (PDF, TXT, DOCX).\n• Check your internet connection.\n\nDetails:\n\(aiError.detailedDescription)")
                    } else if let stringError = importError as? ImportErrorMessage {
                        Text(stringError.message)
                    } else {
                        Text("\(importError?.localizedDescription ?? "Unknown error")\n\nTip: PDFs with selectable text and clear line breaks between jokes give the best results.")
                    }
                }
                .modifier(JokesAlertsModifier(
                    showingExportAlert: $showingExportAlert,
                    showingImportSummary: $showingImportSummary,
                    showingDeleteFolderAlert: $showingDeleteFolderAlert,
                    showingDeleteRoastAlert: $showingDeleteRoastAlert,
                    showingMoveJokesSheet: $showingMoveJokesSheet,
                    exportedPDFURL: exportedPDFURL,
                    importSummary: importSummary,
                    folderPendingDeletion: $folderPendingDeletion,
                    roastTargetToDelete: $roastTargetToDelete,
                    jokes: jokes,
                    shareFile: shareFile,
                    removeJokesFromFolderAndDelete: removeJokesFromFolderAndDelete,
                    modelContext: modelContext
                ))
                .alert("Error", isPresented: $showingPersistenceError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(persistenceError ?? "An unknown error occurred")
                }
                .sheet(item: $jokeToMove) { joke in
                    MoveJokeToFolderSheet(joke: joke, allFolders: folders)
                }
                .overlay { importOverlay }
                // Rebuild filtered list whenever filter inputs change
                .task(id: filterKey) {
                    rebuildFilteredJokes()
                }
                // Also rebuild when the underlying data count changes (adds/deletes)
                .onChange(of: jokes.count) { _, _ in
                    rebuildFilteredJokes()
                }
                // Performance: Debounce search text updates
                .onChange(of: searchText) { _, newValue in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            debouncedSearchText = newValue
                        }
                    }
                }
    }

    // MARK: - Extracted Body Subviews

    @ViewBuilder
    private var mainContent: some View {
        if roastMode {
            roastSection
        } else {
            VStack(spacing: 0) {
                // Filter chips (includes The Hits)
                folderChips

                if filteredJokes.isEmpty {
                    emptyState
                } else {
                    if viewMode == .grid {
                        ScrollView {
                                LazyVGrid(columns: jokesColumns, spacing: 0) {
                                    ForEach(filteredJokes) { joke in
                                        if isSelectMode {
                                            jokeGridSelectableCard(joke: joke)
                                        } else {
                                            JokeCardView(joke: joke, scale: effectiveJokesScale, roastMode: roastMode, showFullContent: showFullContent)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    HapticEngine.shared.tap()
                                                    selectedJokeForDetail = joke
                                                }
                                                .draggable(JokeDragItem(jokeID: joke.id.uuidString)) {
                                                    // Drag preview
                                                    Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                                                        .font(.subheadline.weight(.medium))
                                                        .padding(10)
                                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                }
                                                .contextMenu {
                                                    Button {
                                                        jokeToMove = joke
                                                    } label: {
                                                        Label("Move to Folder", systemImage: "folder")
                                                    }

                                                    Divider()

                                                    Button {
                                                        joke.isHit.toggle()
                                                        joke.dateModified = Date()
                                                    } label: {
                                                        Label(joke.isHit ? "Remove from Hits" : "Add to Hits",
                                                              systemImage: joke.isHit ? "star.slash" : "star.fill")
                                                    }

                                                    Button {
                                                        joke.isOpenMic.toggle()
                                                        joke.dateModified = Date()
                                                    } label: {
                                                        Label(joke.isOpenMic ? "Remove from Open Mic" : "Open Mic",
                                                              systemImage: joke.isOpenMic ? "mic.slash" : "mic.fill")
                                                    }

                                                    Divider()

                                                    Button(role: .destructive) {
                                                        joke.moveToTrash()
                                                        do {
                                                            try modelContext.save()
                                                        } catch {
                                                            print(" [JokesView] Failed to save after trash: \(error)")
                                                            persistenceError = "Could not move joke to trash: \(error.localizedDescription)"
                                                            showingPersistenceError = true
                                                        }
                                                    } label: {
                                                        Label("Move to Trash", systemImage: "trash")
                                                    }
                                                }
                                        }
                                    }
                                }
                                .animation(.easeOut(duration: 0.2), value: effectiveJokesScale)
                        }
                        .highPriorityGesture(jokesPinchGesture)
                        .navigationDestination(item: $selectedJokeForDetail) { joke in
                            JokeDetailView(joke: joke)
                        }
                    } else {
                        List {
                            ForEach(filteredJokes) { joke in
                                if isSelectMode {
                                    jokeListSelectableRow(joke: joke)
                                        .listRowSeparatorTint(Color(red: 0.6, green: 0.7, blue: 0.85).opacity(0.3))
                                } else {
                                    NavigationLink(destination: JokeDetailView(joke: joke)) {
                                        JokeRowView(joke: joke, roastMode: roastMode, showFullContent: showFullContent)
                                            .id(joke.id)
                                    }
                                    .draggable(JokeDragItem(jokeID: joke.id.uuidString))
                                    .contextMenu {
                                        Button {
                                            jokeToMove = joke
                                        } label: {
                                            Label("Move to Folder", systemImage: "folder")
                                        }
                                        
                                        Divider()
                                        
                                        Button {
                                            joke.isHit.toggle()
                                            joke.dateModified = Date()
                                        } label: {
                                            Label(joke.isHit ? "Remove from Hits" : "Add to Hits",
                                                  systemImage: joke.isHit ? "star.slash" : "star.fill")
                                        }

                                        Button {
                                            joke.isOpenMic.toggle()
                                            joke.dateModified = Date()
                                        } label: {
                                            Label(joke.isOpenMic ? "Remove from Open Mic" : "Open Mic",
                                                  systemImage: joke.isOpenMic ? "mic.slash" : "mic.fill")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive) {
                                            joke.moveToTrash()
                                            do {
                                                try modelContext.save()
                                            } catch {
                                                print(" [JokesView] Failed to save after trash: \(error)")
                                                persistenceError = "Could not move joke to trash: \(error.localizedDescription)"
                                                showingPersistenceError = true
                                            }
                                        } label: {
                                            Label("Move to Trash", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            HapticEngine.shared.delete()
                                            joke.moveToTrash()
                                            do {
                                                try modelContext.save()
                                            } catch {
                                                print(" [JokesView] Failed to save after swipe trash: \(error)")
                                                persistenceError = "Could not move joke to trash: \(error.localizedDescription)"
                                                showingPersistenceError = true
                                            }
                                        } label: {
                                            Label("Trash", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            HapticEngine.shared.starToggle(!joke.isHit)
                                            joke.isHit.toggle()
                                            joke.dateModified = Date()
                                            do {
                                                try modelContext.save()
                                            } catch {
                                                print(" [JokesView] Failed to save hit toggle: \(error)")
                                            }
                                        } label: {
                                            Label(joke.isHit ? "Remove Hit" : "Add Hit", systemImage: joke.isHit ? "star.slash" : "star.fill")
                                        }
                                        .tint(.yellow)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            HapticEngine.shared.starToggle(!joke.isHit)
                                            joke.isHit.toggle()
                                            joke.dateModified = Date()
                                        } label: {
                                            Label(joke.isHit ? "Remove Hit" : "The Hits", systemImage: joke.isHit ? "star.slash.fill" : "star.fill")
                                        }
                                        .tint(.yellow)
                                        
                                        Button {
                                            haptic(.medium)
                                            joke.isOpenMic.toggle()
                                            joke.dateModified = Date()
                                            do {
                                                try modelContext.save()
                                            } catch {
                                                print(" [JokesView] Failed to save open mic toggle: \(error)")
                                            }
                                        } label: {
                                            Label(joke.isOpenMic ? "Remove Open Mic" : "Open Mic", systemImage: joke.isOpenMic ? "mic.slash" : "mic.fill")
                                        }
                                        .tint(.purple)
                                    }
                                    .listRowSeparatorTint(Color(red: 0.6, green: 0.7, blue: 0.85).opacity(0.3))
                                }
                            }
                            .onDelete(perform: deleteJokes)
                        }
                        .listStyle(.plain)
                    }
                }
                
                // Batch action bar
                if isSelectMode {
                    batchActionBar
                }
            }
        }
    }
    
    // MARK: - Batch Select Mode Views
    
    @ViewBuilder
    private func jokeGridSelectableCard(joke: Joke) -> some View {
        let isSelected = selectedJokeIDs.contains(joke.id)
        Button {
            toggleSelection(joke)
        } label: {
            ZStack(alignment: .topTrailing) {
                JokeCardView(joke: joke, scale: effectiveJokesScale, showFullContent: showFullContent)
                    .opacity(isSelected ? 0.7 : 1.0)
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color.accentColor : .gray.opacity(0.5))
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func jokeListSelectableRow(joke: Joke) -> some View {
        let isSelected = selectedJokeIDs.contains(joke.id)
        Button {
            toggleSelection(joke)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color.accentColor : .gray.opacity(0.5))
                
                JokeRowView(joke: joke, showFullContent: showFullContent)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var batchActionBar: some View {
        HStack(spacing: 16) {
            Button {
                selectedJokeIDs = Set(filteredJokes.map(\.id))
            } label: {
                Text("Select All")
                    .font(.subheadline)
            }
            
            Spacer()
            
            Text("\(selectedJokeIDs.count) selected")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(role: .destructive) {
                batchTrashSelected()
            } label: {
                Label("Trash", systemImage: "trash")
                    .font(.subheadline.bold())
            }
            .disabled(selectedJokeIDs.isEmpty)
            .tint(.red)
            
            Button {
                isSelectMode = false
                selectedJokeIDs.removeAll()
            } label: {
                Text("Done")
                    .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
    
    private func toggleSelection(_ joke: Joke) {
        if selectedJokeIDs.contains(joke.id) {
            selectedJokeIDs.remove(joke.id)
        } else {
            selectedJokeIDs.insert(joke.id)
        }
    }
    
    private func batchTrashSelected() {
        // Capture into a local array FIRST — iterating the live @Query
        // while mutating can skip items because SwiftData reactively
        // updates query results mid-loop.
        let jokesToTrash = jokes.filter { selectedJokeIDs.contains($0.id) }
        
        guard !jokesToTrash.isEmpty else {
            print(" [JokesView] No jokes matched selectedJokeIDs for batch trash")
            selectedJokeIDs.removeAll()
            isSelectMode = false
            return
        }
        
        for joke in jokesToTrash {
            joke.moveToTrash()
        }
        
        let count = jokesToTrash.count
        selectedJokeIDs.removeAll()
        isSelectMode = false
        
        do {
            try modelContext.save()
            print(" [JokesView] Batch trashed \(count) joke(s)")
        } catch {
            print(" [JokesView] Failed to save after batch trash: \(error)")
            persistenceError = "Could not move \(count) joke(s) to trash: \(error.localizedDescription)"
            showingPersistenceError = true
        }
        
        NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
    }

    @ToolbarContentBuilder
    private var combinedToolbarContent: some ToolbarContent {
        if roastMode {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddRoastTarget = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .accessibilityLabel("Add roast target")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("View") {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                roastViewMode = roastViewMode == .grid ? .list : .grid
                            }
                        } label: {
                            Label(roastViewMode == .grid ? "List View" : "Grid View",
                                  systemImage: roastViewMode.icon)
                        }
                    }

                    Section("Export") {
                        Button(action: exportAllRoastsToPDF) {
                            Label("Export All Roasts to PDF", systemImage: "doc.richtext")
                        }
                        Button(action: exportAllRoastsToText) {
                            Label("Export All Roasts to Text", systemImage: "doc.text")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More Actions")
                }
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Create") {
                        Button(action: { showingAddJoke = true }) {
                            Label("Write a Joke", systemImage: "square.and.pencil")
                        }
                        Button(action: { showingTalkToText = true }) {
                            Label("Talk-to-Text", systemImage: "mic.badge.plus")
                        }
                    }
                    Section("Import") {
                        Button(action: { showingGagGrabber = true }) {
                            Label {
                                Text("GagGrabber (Extract Jokes)")
                            } icon: {
                                Image("GagGrabberGlyph")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        Button(action: { showingFilePicker = true }) {
                            Label("Import from Files", systemImage: "doc.text")
                        }
                        Button(action: { showingScanner = true }) {
                            Label("Scan with Camera", systemImage: "camera.viewfinder")
                        }
                        Button(action: { showingImagePicker = true }) {
                            Label("Import from Photos", systemImage: "photo.on.rectangle")
                        }
                        Button(action: { showingAudioImport = true }) {
                            Label("Import from Voice Memos", systemImage: "waveform")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add or Import")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("View") {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = viewMode == .grid ? .list : .grid
                            }
                        } label: {
                            Label(viewMode == .grid ? "List View" : "Grid View",
                                  systemImage: viewMode.icon)
                        }
                        Button(action: { showFullContent.toggle() }) {
                            Label(showFullContent ? "Show Titles Only" : "Show Full Content",
                                  systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                        }
                    }
                    Section("Organization") {
                        Button(action: { showingCreateFolder = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        Button(action: { showingAutoOrganize = true }) {
                            Label("Auto-Organize Jokes", systemImage: "wand.and.stars")
                        }
                        Button(action: { showingGuidedOrganize = true }) {
                            Label("Guided Organize", systemImage: "hand.point.right.fill")
                        }
                        Button(action: { showingImportHistory = true }) {
                            Label("Import History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                    }
                    Section("Selection") {
                        Button(action: {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedJokeIDs.removeAll() }
                        }) {
                            Label(isSelectMode ? "Cancel Multi-Select" : "Select Multiple Jokes",
                                  systemImage: isSelectMode ? "xmark.circle" : "checkmark.circle")
                        }
                    }
                    Section("Export") {
                        Button(action: exportJokesToPDF) {
                            Label("Export Jokes to PDF", systemImage: "doc.text")
                        }
                        Button(action: exportBrainstormToPDF) {
                            Label("Export Brainstorm to PDF", systemImage: "lightbulb")
                        }
                        Button(action: exportEverythingToPDF) {
                            Label("Export Everything", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More Actions")
                }
            }
        }
    }

    @ViewBuilder
    private var importOverlay: some View {
        if isProcessingImages {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            ImportProgressCard(
                importFileCount: importFileCount,
                importFileIndex: importFileIndex,
                importStatusMessage: importStatusMessage,
                importedJokeNames: importedJokeNames
            )
        }
    }
    
    private func deleteJokes(at offsets: IndexSet) {
        let snapshot = filteredJokes
        for index in offsets {
            guard index < snapshot.count else { continue }
            // Soft-delete into trash
            snapshot[index].moveToTrash()
        }
        do {
            try modelContext.save()
        } catch {
            print(" [JokesView] Failed to save after delete: \(error)")
            persistenceError = "Could not move joke to trash: \(error.localizedDescription)"
            showingPersistenceError = true
        }
        NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
    }
    
    // MARK: - Drag & Drop
    
    private func handleJokeDrop(_ items: [JokeDragItem], onto folder: JokeFolder) {
        var movedCount = 0
        for item in items {
            guard let uuid = UUID(uuidString: item.jokeID),
                  let joke = jokes.first(where: { $0.id == uuid }) else { continue }
            
            var currentFolders = joke.folders ?? []
            if !currentFolders.contains(where: { $0.id == folder.id }) {
                currentFolders.append(folder)
                joke.folders = currentFolders
                joke.dateModified = Date()
                movedCount += 1
            }
        }
        
        guard movedCount > 0 else { return }
        
        do {
            try modelContext.save()
            HapticEngine.shared.tap()
            print(" [JokesView] Moved \(movedCount) joke(s) to folder '\(folder.name)'")
        } catch {
            print(" [JokesView] Failed to save after drag-drop move: \(error)")
            persistenceError = "Could not move joke(s) to folder: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
    
    private func moveJokes(from sourceFolder: JokeFolder, to destinationFolder: JokeFolder?) {
        let jokesInFolder = jokes.filter { ($0.folders ?? []).contains(where: { $0.id == sourceFolder.id }) }
        for joke in jokesInFolder {
            // Remove from source folder
            var current = joke.folders ?? []
            current.removeAll(where: { $0.id == sourceFolder.id })
            // Add to destination folder if specified
            if let dest = destinationFolder {
                if !current.contains(where: { $0.id == dest.id }) {
                    current.append(dest)
                }
            }
            joke.folders = current
        }
        do {
            try modelContext.save()
        } catch {
            print(" Failed to move jokes: \(error)")
        }
    }
    
    private func removeJokesFromFolderAndDelete(_ folder: JokeFolder) {
        let jokesInFolder = jokes.filter { ($0.folders ?? []).contains(where: { $0.id == folder.id }) }
        for joke in jokesInFolder {
            var current = joke.folders ?? []
            current.removeAll(where: { $0.id == folder.id })
            joke.folders = current
        }
        deleteFolder(folder)
    }
    
    private func deleteFolder(_ folder: JokeFolder) {
        // Remove jokes from this folder before trashing
        let jokesInFolder = jokes.filter { ($0.folders ?? []).contains(where: { $0.id == folder.id }) }
        for joke in jokesInFolder {
            var current = joke.folders ?? []
            current.removeAll(where: { $0.id == folder.id })
            joke.folders = current
        }
        
        folder.moveToTrash()
        do {
            try modelContext.save()
        } catch {
            print(" Failed to delete folder: \(error)")
        }
    }
    
    private func processScannedImages(_ images: [UIImage]) {
        isProcessingImages = true
        importedJokeNames = []
        importStatusMessage = "Analyzing \(images.count) scanned page\(images.count == 1 ? "" : "s")..."
        importFileCount = images.count
        importFileIndex = 0

        Task {
            var combinedAutoSaved:  [ImportedJoke] = []
            var combinedReview:     [ImportedJoke] = []
            var combinedRejected:   [LayoutBlock]  = []
            var providersUsed = Set<String>()
            var failedMessages: [String] = []  // collect per-file errors — never silently drop them

            for (idx, image) in images.enumerated() {
                await MainActor.run {
                    importFileIndex = idx + 1
                    importStatusMessage = "Reading text from scan \(importFileIndex) of \(images.count)..."
                }

                // Process each image inside an autoreleasepool so the temp file
                // data and intermediate UIImage buffers are freed between pages.
                // Using JPEG instead of PNG — ~10x smaller for camera images.
                do {
                    guard let jpegData: Data = autoreleasepool(invoking: {
                        image.jpegData(compressionQuality: 0.85)
                    }) else {
                        failedMessages.append("Image \(idx + 1): could not encode as JPEG")
                        continue
                    }
                    let tmpURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("scan_\(idx)_\(UUID().uuidString).jpg")
                    try jpegData.write(to: tmpURL)
                    defer { try? FileManager.default.removeItem(at: tmpURL) }

                    await MainActor.run { importStatusMessage = "GagGrabber extracting jokes from scan \(importFileIndex) of \(images.count)..." }

                    // Scanner path doesn't present the preflight (the user is
                    // scanning arbitrary pages, not a file they already know
                    // the shape of) but they still benefit from whatever
                    // hints they've confirmed in previous imports.
                    let result = try await FileImportService.shared.importWithPipeline(from: tmpURL, hints: .loadLastUsed())
                    combinedAutoSaved.append(contentsOf: result.autoSavedJokes)
                    combinedReview.append(contentsOf: result.reviewQueueJokes)
                    combinedRejected.append(contentsOf: result.rejectedBlocks)
                    providersUsed.insert(result.providerUsed)

                    await MainActor.run {
                        let found = result.autoSavedJokes.count + result.reviewQueueJokes.count
                        importStatusMessage = "Found \(found) joke\(found == 1 ? "" : "s") in scan \(importFileIndex)!"
                    }
                } catch {
                    print(" SCANNER: Pipeline failed for image \(idx + 1): \(error)")
                    failedMessages.append("Image \(idx + 1): \(error.localizedDescription)")
                }
            }

            let providerSummary = providersUsed.count == 1 ? (providersUsed.first ?? "Unknown") : (providersUsed.isEmpty ? "Unknown" : "Multiple")
            let combinedResult = ImportPipelineResult(
                sourceFile: "Scanned Image",
                autoSavedJokes: combinedAutoSaved,
                reviewQueueJokes: combinedReview,
                rejectedBlocks: combinedRejected,
                pipelineStats: PipelineStats(
                    totalPagesProcessed: images.count,
                    totalLinesExtracted: 0,
                    totalBlocksCreated: combinedAutoSaved.count + combinedReview.count,
                    autoSavedCount: combinedAutoSaved.count,
                    reviewQueueCount: combinedReview.count,
                    rejectedCount: combinedRejected.count,
                    extractionMethod: .visionOCR,
                    processingTimeSeconds: 0,
                    averageConfidence: 0.7
                ),
                debugInfo: nil,
                providerUsed: providerSummary
            )

            await MainActor.run {
                isProcessingImages = false
                importStatusMessage = ""
                importedJokeNames = []
                importFileCount = 0
                importFileIndex = 0

                let total = combinedAutoSaved.count + combinedReview.count
                if total > 0 {
                    self.smartImportResult = combinedResult
                    // Surface partial-failure info even when some files succeeded
                    if !failedMessages.isEmpty {
                        self.importError = ImportErrorMessage(message: "Some scans failed:\n" + failedMessages.joined(separator: "\n"))
                        self.showingImportError = true
                    }
                } else if !failedMessages.isEmpty {
                    // Every file failed — show the collected errors
                    self.importError = ImportErrorMessage(message: failedMessages.joined(separator: "\n"))
                    self.showingImportError = true
                } else {
                    self.importSummary = (0, 0)
                    self.showingImportSummary = true
                }
            }
        }
    }
    
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        isProcessingImages = true
        importedJokeNames = []
        importStatusMessage = "Analyzing \(items.count) photo\(items.count == 1 ? "" : "s")..."
        importFileCount = items.count
        importFileIndex = 0

        var combinedAutoSaved:  [ImportedJoke] = []
        var combinedReview:     [ImportedJoke] = []
        var combinedRejected:   [LayoutBlock]  = []
        var providersUsed = Set<String>()
        var failedMessages: [String] = []  // collect per-photo errors — never silently drop them

        for (idx, item) in items.enumerated() {
            await MainActor.run {
                importFileIndex = idx + 1
                importStatusMessage = "Reading text from photo \(importFileIndex) of \(importFileCount)..."
            }

            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let pngData = image.pngData() else {
                failedMessages.append("Photo \(idx + 1): could not load image data")
                continue
            }

            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("photo_\(idx)_\(UUID().uuidString).png")
            do {
                try pngData.write(to: tmpURL)
                defer { try? FileManager.default.removeItem(at: tmpURL) }

                await MainActor.run { importStatusMessage = "GagGrabber extracting jokes from photo \(importFileIndex) of \(importFileCount)..." }

                // Photo-library path mirrors the scanner — no preflight
                // (arbitrary photos, unpredictable content) but still
                // benefits from the user's last-confirmed hints.
                let result = try await FileImportService.shared.importWithPipeline(from: tmpURL, hints: .loadLastUsed())
                combinedAutoSaved.append(contentsOf: result.autoSavedJokes)
                combinedReview.append(contentsOf: result.reviewQueueJokes)
                combinedRejected.append(contentsOf: result.rejectedBlocks)
                providersUsed.insert(result.providerUsed)

                await MainActor.run {
                    let found = result.autoSavedJokes.count + result.reviewQueueJokes.count
                    importStatusMessage = "Found \(found) joke\(found == 1 ? "" : "s") in photo \(importFileIndex)!"
                }
            } catch {
                print(" PHOTOS: Pipeline failed for photo \(idx + 1): \(error)")
                failedMessages.append("Photo \(idx + 1): \(error.localizedDescription)")
            }
        }

        let providerSummary = providersUsed.count == 1 ? (providersUsed.first ?? "Unknown") : (providersUsed.isEmpty ? "Unknown" : "Multiple")
        let combinedResult = ImportPipelineResult(
            sourceFile: "Photo Library",
            autoSavedJokes: combinedAutoSaved,
            reviewQueueJokes: combinedReview,
            rejectedBlocks: combinedRejected,
            pipelineStats: PipelineStats(
                totalPagesProcessed: items.count,
                totalLinesExtracted: 0,
                totalBlocksCreated: combinedAutoSaved.count + combinedReview.count,
                autoSavedCount: combinedAutoSaved.count,
                reviewQueueCount: combinedReview.count,
                rejectedCount: combinedRejected.count,
                extractionMethod: .visionOCR,
                processingTimeSeconds: 0,
                averageConfidence: 0.7
            ),
            debugInfo: nil,
            providerUsed: providerSummary
        )

        await MainActor.run {
            selectedPhotos = []
            isProcessingImages = false
            importStatusMessage = ""
            importedJokeNames = []
            importFileCount = 0
            importFileIndex = 0

            let total = combinedAutoSaved.count + combinedReview.count
            if total > 0 {
                self.smartImportResult = combinedResult
                // Surface partial-failure info even when some photos succeeded
                if !failedMessages.isEmpty {
                    self.importError = ImportErrorMessage(message: "Some photos failed:\n" + failedMessages.joined(separator: "\n"))
                    self.showingImportError = true
                }
            } else if !failedMessages.isEmpty {
                // Every photo failed — show the collected errors
                self.importError = ImportErrorMessage(message: failedMessages.joined(separator: "\n"))
                self.showingImportError = true
            } else {
                self.importSummary = (0, 0)
                self.showingImportSummary = true
            }
        }
    }
    
    /// Entry point used by the document picker. Presents the extraction-hints
    /// preflight sheet first — `runDocumentImport(urls:hints:)` does the
    /// actual work once the user continues or skips.
    private func processDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingDocumentImport = PendingDocumentImport(urls: urls)
    }

    private func runDocumentImport(urls: [URL], hints: ExtractionHints) {
        print(" SMART IMPORT START: \(urls.count) files selected")
        isProcessingImages = true
        importedJokeNames = []
        importStatusMessage = "Analyzing \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")..."
        importFileCount = urls.count
        importFileIndex = 0

        Task {
            // For multi-file imports, we combine results from all files
            var combinedAutoSaved: [ImportedJoke] = []
            var combinedReview: [ImportedJoke] = []
            var combinedRejected: [LayoutBlock] = []
            var sourceFile = ""
            var providersUsed = Set<String>()
            var failedMessages: [String] = []  // collect per-file errors — never silently drop them
            
            for url in urls {
                await MainActor.run {
                    importFileIndex += 1
                    importStatusMessage = "GagGrabber scanning \(url.lastPathComponent)..."
                }
                
                do {
                    let result = try await FileImportService.shared.importWithPipeline(from: url, hints: hints)
                    combinedAutoSaved.append(contentsOf: result.autoSavedJokes)
                    combinedReview.append(contentsOf: result.reviewQueueJokes)
                    combinedRejected.append(contentsOf: result.rejectedBlocks)
                    sourceFile = result.sourceFile
                    providersUsed.insert(result.providerUsed)
                    
                    await MainActor.run {
                        let found = result.autoSavedJokes.count + result.reviewQueueJokes.count
                        importStatusMessage = "Found \(found) joke\(found == 1 ? "" : "s") in \(url.lastPathComponent)!"
                    }
                } catch {
                    print(" IMPORT: AI extraction failed for \(url.lastPathComponent): \(error)")
                    failedMessages.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    // Do not fall back to local extraction — surface the error below.
                    // Continue looping so other selected files can still be processed.
                }
            }
            
            let providerSummary: String = {
                let unique = Array(providersUsed)
                if unique.isEmpty { return "Unknown" }
                if unique.count == 1 { return unique[0] }
                return "Multiple"
            }()
            
            // Build combined result
            let combinedResult = ImportPipelineResult(
                sourceFile: sourceFile,
                autoSavedJokes: combinedAutoSaved,
                reviewQueueJokes: combinedReview,
                rejectedBlocks: combinedRejected,
                pipelineStats: PipelineStats(
                    totalPagesProcessed: 0,
                    totalLinesExtracted: 0,
                    totalBlocksCreated: combinedAutoSaved.count + combinedReview.count,
                    autoSavedCount: combinedAutoSaved.count,
                    reviewQueueCount: combinedReview.count,
                    rejectedCount: combinedRejected.count,
                    extractionMethod: .documentText,
                    processingTimeSeconds: 0,
                    averageConfidence: 0.7
                ),
                debugInfo: nil,
                providerUsed: providerSummary
            )
            
            await MainActor.run {
                self.isProcessingImages = false
                self.importStatusMessage = ""
                self.importedJokeNames = []
                self.importFileCount = 0
                self.importFileIndex = 0
                
                let totalJokes = combinedAutoSaved.count + combinedReview.count
                if totalJokes > 0 {
                    // Show the Smart Import Review for all AI-reviewed fragments
                    self.smartImportResult = combinedResult
                    // Surface partial-failure info even when some files succeeded
                    if !failedMessages.isEmpty {
                        self.importError = ImportErrorMessage(message: "Some files failed:\n" + failedMessages.joined(separator: "\n"))
                        self.showingImportError = true
                    }
                } else if !failedMessages.isEmpty {
                    // AI failed on every file — show the collected errors
                    self.importError = ImportErrorMessage(message: failedMessages.joined(separator: "\n"))
                    self.showingImportError = true
                } else {
                    // AI ran but found nothing at all
                    self.importSummary = (0, 0)
                    self.showingImportSummary = true
                }
            }
        }
    }
    
    // MARK: - Export Methods

    private func exportJokesToPDF() {
        let jokesToExport: [Joke]
        if selectedFolder != nil {
            jokesToExport = filteredJokes
        } else {
            jokesToExport = jokes.filter { !$0.isTrashed }
        }
        if let url = PDFExportService.exportJokesToPDF(jokes: jokesToExport) {
            exportedPDFURL = url
            showingExportAlert = true
        }
    }
    
    private func exportBrainstormToPDF() {
        if let url = PDFExportService.exportBrainstormToPDF(ideas: brainstormIdeas) {
            exportedPDFURL = url
            showingExportAlert = true
        }
    }
    
    private func exportEverythingToPDF() {
        let jokesToExport = jokes.filter { !$0.isTrashed }
        if let url = PDFExportService.exportEverythingToPDF(jokes: jokesToExport, ideas: brainstormIdeas) {
            exportedPDFURL = url
            showingExportAlert = true
        }
    }
    
    private func shareFile(_ url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            // Required for iPad — set popover source to prevent crash
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Roast Export Methods
    
    private func exportAllRoastsToPDF() {
        let targetsToExport = roastTargets.filter { !$0.isTrashed && $0.jokeCount > 0 }
        guard !targetsToExport.isEmpty else { return }
        
        if let url = PDFExportService.exportRoastsToPDF(targets: targetsToExport, fileName: "BitBinder_AllRoasts") {
            shareFile(url)
        }
    }
    
    private func exportAllRoastsToText() {
        let targetsToExport = roastTargets.filter { !$0.isTrashed && $0.jokeCount > 0 }
        guard !targetsToExport.isEmpty else { return }
        
        var text = "THE BITBINDER - ALL ROASTS\n"
        text += String(repeating: "=", count: 50) + "\n"
        text += "Exported: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n"
        text += "\(targetsToExport.count) target\(targetsToExport.count == 1 ? "" : "s"), "
        let totalRoasts = targetsToExport.reduce(0) { $0 + $1.jokeCount }
        text += "\(totalRoasts) roast\(totalRoasts == 1 ? "" : "s")\n\n"
        text += String(repeating: "=", count: 50) + "\n\n"
        
        for target in targetsToExport {
            text += "🎯 \(target.name.uppercased())\n"
            text += String(repeating: "-", count: 30) + "\n"
            
            if !target.notes.isEmpty {
                text += "About: \(target.notes)\n"
            }
            
            if !target.traits.isEmpty {
                text += "Traits: \(target.traits.joined(separator: ", "))\n"
            }
            
            text += "\n"
            
            let allJokes = target.sortedJokes
            let openingRoasts = allJokes.filter { $0.isOpeningRoast }.sorted { $0.displayOrder < $1.displayOrder }
            let backupRoasts = allJokes.filter { !$0.isOpeningRoast && $0.parentOpeningRoastID != nil }
            let unassignedRoasts = allJokes.filter { !$0.isOpeningRoast && $0.parentOpeningRoastID == nil }
            
            var jokeIndex = 1
            
            // Opening roasts section
            if !openingRoasts.isEmpty {
                text += "⭐ OPENING ROASTS (\(openingRoasts.count))\n"
                
                for (i, joke) in openingRoasts.enumerated() {
                    text += "\(i + 1). "
                    if joke.isKiller { text += "🔥 " }
                    text += "\(joke.content)\n"
                    
                    if joke.hasStructure {
                        if !joke.setup.isEmpty {
                            text += "   SETUP: \(joke.setup)\n"
                        }
                        if !joke.punchline.isEmpty {
                            text += "   PUNCHLINE: \(joke.punchline)\n"
                        }
                    }
                    
                    if !joke.performanceNotes.isEmpty {
                        text += "   NOTES: \(joke.performanceNotes)\n"
                    }
                    
                    if joke.isTested {
                        text += "   (Performed \(joke.performanceCount)x)\n"
                    }
                    
                    // Show backups for this opener
                    let backupsForOpener = backupRoasts.filter { $0.parentOpeningRoastID == joke.id }
                    if !backupsForOpener.isEmpty {
                        text += "   BACKUPS:\n"
                        for backup in backupsForOpener {
                            text += "   ↳ \(backup.content)\n"
                        }
                    }
                    
                    text += "\n"
                    jokeIndex += 1
                }
            }
            
            // Unassigned roasts section
            if !unassignedRoasts.isEmpty {
                if !openingRoasts.isEmpty {
                    text += "OTHER ROASTS (\(unassignedRoasts.count))\n"
                }
                
                for joke in unassignedRoasts {
                    text += "\(jokeIndex). "
                    if joke.isKiller { text += "⭐️ " }
                    text += "\(joke.content)\n"
                    
                    if joke.hasStructure {
                        if !joke.setup.isEmpty {
                            text += "   SETUP: \(joke.setup)\n"
                        }
                        if !joke.punchline.isEmpty {
                            text += "   PUNCHLINE: \(joke.punchline)\n"
                        }
                    }
                    
                    if !joke.performanceNotes.isEmpty {
                        text += "   NOTES: \(joke.performanceNotes)\n"
                    }
                    
                    if joke.isTested {
                        text += "   (Performed \(joke.performanceCount)x)\n"
                    }
                    
                    text += "\n"
                    jokeIndex += 1
                }
            }
            
            text += "\n" + String(repeating: "=", count: 50) + "\n\n"
        }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("BitBinder_AllRoasts.txt")
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            shareFile(fileURL)
        } catch {
            print("⚠️ Failed to write roasts text export: \(error)")
        }
    }
    
    private func isLikelyDuplicate(_ content: String, title: String?) -> Bool {
        DuplicateDetectionService.findDuplicate(
            content: content,
            title: title,
            in: modelContext
        ) != nil
    }
    
    /// Cached app group UserDefaults — created once to avoid repeated
    /// `UserDefaults(suiteName:)` instantiation which can trigger
    /// "kCFPreferencesAnyUser" console warnings.
    private static let appGroupDefaults: UserDefaults? = {
        let id = "group.The-BitBinder.thebitbinder"
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil else {
            return nil
        }
        return UserDefaults(suiteName: id)
    }()

    private func checkPendingVoiceMemoImports() {
        guard let sharedDefaults = Self.appGroupDefaults else {
            print(" [VoiceMemo] App Group container unavailable")
            return
        }
        guard let pendingImports = sharedDefaults.array(forKey: "pendingVoiceMemoImports") as? [[String: String]],
              !pendingImports.isEmpty else { return }
        
        print(" [VoiceMemo] Found \(pendingImports.count) pending voice memo imports")
        
        var importedCount = 0
        for importData in pendingImports {
            guard let transcription = importData["transcription"],
                  !transcription.isEmpty else { continue }
            
            let title = AudioTranscriptionService.generateTitle(from: transcription)
            
            // Check for duplicates
            if !isLikelyDuplicate(transcription, title: title) {
                let joke = Joke(content: transcription, title: title, folder: selectedFolder)
                modelContext.insert(joke)
                importedCount += 1
            }
        }
        
        // Clear pending imports — no synchronize() needed (deprecated since iOS 12)
        sharedDefaults.removeObject(forKey: "pendingVoiceMemoImports")
        
        if importedCount > 0 {
            do {
                try modelContext.save()
            } catch {
                print(" [JokesView] Failed to save imported voice memos: \(error)")
            }
            importSummary = (importedCount, 0)
            showingImportSummary = true
            print(" [VoiceMemo] Imported \(importedCount) voice memos")
        }
    }
}

private extension JokesView {
    func matchesSearch(_ joke: Joke, lower: String) -> Bool {
        let title = joke.title.lowercased()
        if title.contains(lower) { return true }
        let content = joke.content.lowercased()
        return content.contains(lower)
    }
}

// MARK: - Roast Mode v2 Components

/// Cold state — shown when there are zero roast subjects.
struct RoastColdStateView: View {
    let onAddTarget: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "flame")
                        .font(.system(size: 10))
                        .foregroundColor(ColdPalette.grey)
                    Text("ROAST MODE")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(ColdPalette.grey)
                        .tracking(1.4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(ColdPalette.edge, lineWidth: 0.5))

                Text("no fire yet")
                    .font(.system(size: 11))
                    .foregroundColor(ColdPalette.sub)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 20) {
                // Unlit match
                Image(systemName: "line.diagonal")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundColor(ColdPalette.grey.opacity(0.7))
                    .rotationEffect(.degrees(-20))
                    .overlay(alignment: .top) {
                        Circle()
                            .fill(ColdPalette.grey)
                            .frame(width: 16, height: 16)
                            .offset(y: -10)
                    }
                    .frame(width: 140, height: 140)

                VStack(spacing: 10) {
                    Text("Nothing to burn yet.")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(ColdPalette.text)
                        .tracking(-0.5)

                    Text("Add a subject — your mom, your coworker, your landlord. BitBuddy will start collecting bits.")
                        .font(.system(size: 14))
                        .foregroundColor(ColdPalette.sub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 280)
                }

                Button(action: onAddTarget) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame")
                            .font(.system(size: 14))
                        Text("Light the first match")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(FirePalette.emberCTA)
                    .clipShape(Capsule())
                    .shadow(color: FirePalette.core.opacity(0.3), radius: 14, y: 6)
                }
                .padding(.top, 6)

                Text("or import from Contacts")
                    .font(.system(size: 11))
                    .foregroundColor(ColdPalette.sub)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColdPalette.bg.ignoresSafeArea())
    }
}

/// Fire-mode header with hero glow and Roast Mode badge.
struct RoastHomeHeader: View {
    let subjectCount: Int
    let hotCount: Int
    let isCold: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if !isCold {
                Circle()
                    .fill(RadialGradient(
                        colors: [FirePalette.core.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 130
                    ))
                    .frame(width: 260, height: 260)
                    .blur(radius: 24)
                    .offset(x: 60, y: -40)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    RoastModeBadge(small: true, lit: !isCold)

                    if hotCount > 0 {
                        Text("\(hotCount) burning · \(subjectCount - hotCount) warm")
                            .font(.system(size: 11))
                            .foregroundColor(FirePalette.sub)
                    }
                }

                Text("Who's getting roasted?")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(FirePalette.text)
                    .tracking(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(subjectCount) people")
                    .font(.system(size: 13))
                    .foregroundColor(FirePalette.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
    }
}

/// Roast Mode pill badge.
struct RoastModeBadge: View {
    var small: Bool = false
    var lit: Bool = true

    var body: some View {
        HStack(spacing: small ? 6 : 8) {
            Image(systemName: "flame")
                .font(.system(size: small ? 10 : 14))
            Text("ROAST MODE")
                .font(.system(size: small ? 10 : 12, weight: .heavy))
                .tracking(1.4)
        }
        .foregroundColor(lit ? .white : ColdPalette.grey)
        .padding(.horizontal, small ? 12 : 18)
        .padding(.vertical, small ? 6 : 10)
        .background(
            lit
                ? AnyShapeStyle(FirePalette.emberCTA)
                : AnyShapeStyle(Color.white.opacity(0.04))
        )
        .clipShape(Capsule())
        .shadow(
            color: lit ? FirePalette.core.opacity(0.4) : .clear,
            radius: lit ? 12 : 0, y: 4
        )
        .overlay(
            lit ? nil : Capsule().strokeBorder(ColdPalette.edge, lineWidth: 0.5)
        )
    }
}

/// Subject card — matches design spec with glow hierarchy.
struct RoastSubjectCard: View {
    let target: RoastTarget
    let heat: Int
    let rank: Int

    private var isTop: Bool { rank == 1 }
    private var safeName: String { target.isValid ? target.name : "" }
    private var safeNotes: String { target.isValid ? target.notes : "" }
    private var safeBits: Int { target.isValid ? target.jokeCount : 0 }

    private var initials: String {
        safeName.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
    }

    private var avatarGradient: LinearGradient {
        if heat >= 85 {
            return LinearGradient(colors: [FirePalette.core, Color(red: 0.76, green: 0.21, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if heat >= 60 {
            return LinearGradient(colors: [FirePalette.bright, Color(red: 0.82, green: 0.48, blue: 0.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if heat >= 30 {
            return LinearGradient(colors: [Color(red: 0.36, green: 0.50, blue: 0.85), Color(red: 0.18, green: 0.29, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [Color(red: 0.48, green: 0.42, blue: 0.36), Color(red: 0.23, green: 0.19, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isTop {
                Circle()
                    .fill(RadialGradient(
                        colors: [FirePalette.core.opacity(0.27), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    ))
                    .frame(width: 140, height: 140)
                    .blur(radius: 16)
                    .offset(x: 30, y: -30)
            }

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    // Avatar
                    if let photoData = target.photoData, let img = UIImage(data: photoData) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(avatarGradient)
                            Text(initials)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(safeName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(FirePalette.text)
                            .tracking(-0.2)
                        if !safeNotes.isEmpty {
                            Text(safeNotes)
                                .font(.system(size: 12))
                                .foregroundColor(FirePalette.sub)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(safeBits)")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(FirePalette.text)
                        Text("BITS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(FirePalette.sub)
                            .tracking(0.8)
                    }
                }

                HeatBar(heat: heat)
                    .padding(.top, 12)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isTop
                    ? LinearGradient(colors: [FirePalette.card, Color(red: 0.165, green: 0.094, blue: 0.071)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [FirePalette.card, FirePalette.card], startPoint: .leading, endPoint: .trailing)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTop ? FirePalette.core.opacity(0.4) : FirePalette.edge, lineWidth: 0.5)
        )
        .shadow(color: isTop ? FirePalette.core.opacity(0.15) : .clear, radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }
}

// Legacy types kept for backward compat with any remaining references
struct RoastTargetGridCard: View {
    let target: RoastTarget
    var scale: CGFloat = 1.0
    var body: some View {
        RoastSubjectCard(target: target, heat: min(100, target.jokeCount * 4), rank: 2)
    }
}

struct RoastTargetListRow: View {
    let target: RoastTarget
    var body: some View {
        RoastSubjectCard(target: target, heat: min(100, target.jokeCount * 4), rank: 2)
    }
}
