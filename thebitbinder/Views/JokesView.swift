//
//  JokesView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ImportErrorMessage: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct JokesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Joke> { !$0.isDeleted }, sort: \Joke.dateModified, order: .reverse) private var jokes: [Joke]
    @Query(filter: #Predicate<JokeFolder> { !$0.isDeleted }) private var folders: [JokeFolder]
    @Query(filter: #Predicate<RoastTarget> { !$0.isDeleted }, sort: \RoastTarget.dateModified, order: .reverse) private var roastTargets: [RoastTarget]
    @Query(sort: \BrainstormIdea.dateCreated, order: .reverse) private var brainstormIdeas: [BrainstormIdea]
    
    // Roast mode — toggled from Settings
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    // Roast sheet state
    @State private var showingAddRoastTarget = false
    @State private var roastTargetToDelete: RoastTarget?
    @State private var showingDeleteRoastAlert = false
    
    @AppStorage("jokesViewMode") private var viewMode: JokesViewMode = .grid
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
    @State private var showingImportHistory = false
    @State private var showingExportAlert = false
    @State private var selectedFolder: JokeFolder?
    @State private var showRecentlyAdded = false
    @State private var searchText = ""
    @State private var exportedPDFURL: URL?
    @State private var selectedPhotos: [PhotosPickerItem] = []
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
    
    // Batch select/delete mode
    @State private var isSelectMode = false
    @State private var selectedJokeIDs: Set<UUID> = []
    
    // Navigation state for grid items (prevents accidental taps)
    @State private var selectedJokeForDetail: Joke?
    
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
                        }
                    }
                )
                
                // All Jokes
                FolderChip(
                    name: "All",
                    icon: "tray.full.fill",
                    isSelected: selectedFolder == nil && !showRecentlyAdded && !showingHitsFilter,
                    roastMode: roastMode,
                    action: {
                        selectedFolder = nil
                        showRecentlyAdded = false
                        showingHitsFilter = false
                    }
                )
                
                // Recently Added
                FolderChip(
                    name: "Recent",
                    icon: "clock.fill",
                    isSelected: showRecentlyAdded && !showingHitsFilter,
                    roastMode: roastMode,
                    action: {
                        showRecentlyAdded = true
                        selectedFolder = nil
                        showingHitsFilter = false
                    }
                )
                
                // Folder chips
                ForEach(folders) { folder in
                    FolderChip(
                        name: folder.name,
                        isSelected: selectedFolder?.id == folder.id && !showRecentlyAdded && !showingHitsFilter,
                        roastMode: roastMode,
                        action: {
                            selectedFolder = folder
                            showRecentlyAdded = false
                            showingHitsFilter = false
                        }
                    )
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
        .padding(.vertical, 10)
    }
    
    // MARK: - Grid Zoom Bar
    
    @ViewBuilder
    private func gridZoomBar(scale: Binding<Double>, roastMode: Bool = false) -> some View {
        HStack(spacing: 12) {
            // Zoom out button
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    scale.wrappedValue = min(2.0, scale.wrappedValue + 0.5)
                }
                haptic(.light)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(roastMode ? .orange : .accentColor)
            }
            .disabled(scale.wrappedValue >= 2.0)
            .opacity(scale.wrappedValue >= 2.0 ? 0.4 : 1.0)
            
            // Column preset buttons
            HStack(spacing: 6) {
                gridColumnButton(columns: 4, scale: scale, roastMode: roastMode)
                gridColumnButton(columns: 3, scale: scale, roastMode: roastMode)
                gridColumnButton(columns: 2, scale: scale, roastMode: roastMode)
            }
            
            // Zoom in button
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    scale.wrappedValue = max(0.5, scale.wrappedValue - 0.5)
                }
                haptic(.light)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(roastMode ? .orange : .accentColor)
            }
            .disabled(scale.wrappedValue <= 0.5)
            .opacity(scale.wrappedValue <= 0.5 ? 0.4 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.95))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func gridColumnButton(columns: Int, scale: Binding<Double>, roastMode: Bool) -> some View {
        let targetScale = 4.0 / Double(columns)
        let isActive = abs(scale.wrappedValue - targetScale) < 0.1
        
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                scale.wrappedValue = targetScale
            }
            haptic(.light)
        } label: {
            HStack(spacing: 2) {
                ForEach(0..<columns, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive ? (roastMode ? Color.orange : Color.accentColor) : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 10)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? (roastMode ? Color.orange : Color.accentColor).opacity(0.15) : Color.clear)
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        JokesEmptyState(
            roastMode: roastMode,
            hasFilter: selectedFolder != nil || showRecentlyAdded || showingHitsFilter || !searchText.isEmpty,
            onAddJoke: { showingAddJoke = true }
        )
    }

    // MARK: - Roast Section

    @ViewBuilder
    private var roastSection: some View {
        if roastTargets.isEmpty {
            // Empty roast state
            BitBinderEmptyState(
                icon: "flame.fill",
                title: "No Roast Targets Yet",
                subtitle: "Add someone to start writing jokes about them",
                actionTitle: "Add Target",
                action: { showingAddRoastTarget = true },
                roastMode: true
            )
        } else {
            if roastViewMode == .grid {
                ScrollView {
                    LazyVGrid(columns: roastColumns, spacing: 0) {
                        ForEach(roastTargets) { target in
                            NavigationLink(destination: RoastTargetDetailView(target: target)) {
                                RoastTargetGridCard(target: target, scale: effectiveRoastScale)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    roastTargetToDelete = target
                                    showingDeleteRoastAlert = true
                                } label: {
                                    Label("Delete Target", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: effectiveRoastScale)
                }
                .scrollContentBackground(.hidden)
                .simultaneousGesture(roastPinchGesture)
            } else {
                List {
                    ForEach(roastTargets) { target in
                        NavigationLink(destination: RoastTargetDetailView(target: target)) {
                            RoastTargetListRow(target: target)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                roastTargetToDelete = target
                                showingDeleteRoastAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    
    // A stable key that changes whenever any filter input changes.
    // Used by .task(id:) to re-run filtering only when something actually changed.
    private var filterKey: String {
        let folder = selectedFolder?.id.uuidString ?? "nil"
        let hits   = showingHitsFilter ? "1" : "0"
        let recent = showRecentlyAdded  ? "1" : "0"
        let search = debouncedSearchText
        let count  = jokes.count
        return "\(folder)|\(hits)|\(recent)|\(search)|\(count)"
    }

    var filteredJokes: [Joke] { cachedFilteredJokes }

    private func rebuildFilteredJokes() {
        let base: [Joke]
        if showingHitsFilter {
            base = jokes.filter { $0.isHit }
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

        cachedFilteredJokes = filtered.sorted { $0.dateModified > $1.dateModified }
    }
    
    var body: some View {
        mainContent
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
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
                .fullScreenCover(item: $smartImportResult) { result in
                    SmartImportReviewView(
                        importResult: result,
                        selectedFolder: selectedFolder,
                        onComplete: {
                            smartImportResult = nil
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
                .overlay { importOverlay }
                // Rebuild filtered list whenever filter inputs change
                .task(id: filterKey) {
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
                                                .contextMenu {
                                                    if joke.isHit {
                                                        Button {
                                                            joke.isHit = false
                                                            joke.dateModified = Date()
                                                        } label: {
                                                            Label("Remove from Hits", systemImage: "star.slash")
                                                        }
                                                    } else {
                                                        Button {
                                                            joke.isHit = true
                                                            joke.dateModified = Date()
                                                        } label: {
                                                            Label("Add to Hits", systemImage: "star.fill")
                                                        }
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
                        .scrollContentBackground(.hidden)
                        .highPriorityGesture(jokesPinchGesture)
                        .navigationDestination(item: $selectedJokeForDetail) { joke in
                            JokeDetailView(joke: joke)
                        }
                    } else {
                        List {
                            ForEach(filteredJokes) { joke in
                                if isSelectMode {
                                    jokeListSelectableRow(joke: joke)
                                } else {
                                    NavigationLink(destination: JokeDetailView(joke: joke)) {
                                        JokeRowView(joke: joke, roastMode: roastMode, showFullContent: showFullContent)
                                            .id(joke.id)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
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
                                        .tint(AppTheme.Colors.hitsGold)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            HapticEngine.shared.starToggle(!joke.isHit)
                                            joke.isHit.toggle()
                                            joke.dateModified = Date()
                                        } label: {
                                            Label(joke.isHit ? "Remove Hit" : "The Hits", systemImage: joke.isHit ? "star.slash.fill" : "star.fill")
                                        }
                                        .tint(AppTheme.Colors.hitsGold)
                                    }
                                }
                            }
                            .onDelete(perform: deleteJokes)
                        }
                        .listStyle(.insetGrouped)
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
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
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
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                
                JokeRowView(joke: joke, showFullContent: showFullContent)
            }
        }
        .listRowSeparator(.hidden)
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
        .background(Color(UIColor.secondarySystemBackground))
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

    @State private var showingExportAllRoasts = false
    @State private var roastExportURL: URL?
    
    @ToolbarContentBuilder
    private var combinedToolbarContent: some ToolbarContent {
        if roastMode {
            ToolbarItem(placement: .principal) {
                Menu {
                    Section {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                roastViewMode = roastViewMode == .grid ? .list : .grid
                            }
                        } label: {
                            Label(roastViewMode == .grid ? "List View" : "Grid View",
                                  systemImage: roastViewMode.icon)
                        }
                    }
                    
                    Divider()
                    
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
                        .foregroundColor(AppTheme.Colors.roastAccent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddRoastTarget = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        } else {
            ToolbarItem(placement: .principal) {
                Menu {
                    Section(header: Text("View")) {
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
                    Divider()
                    Section(header: Text("Organization")) {
                        Button(action: { showingCreateFolder = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        Button(action: { showingAutoOrganize = true }) {
                            Label("Auto-Organize Jokes", systemImage: "wand.and.stars")
                        }
                        Button(action: { showingImportHistory = true }) {
                            Label("Import History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                    }
                    Divider()
                    Section(header: Text("Selection")) {
                        Button(action: {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedJokeIDs.removeAll() }
                        }) {
                            Label(isSelectMode ? "Cancel Multi-Select" : "Select Multiple Jokes",
                                  systemImage: isSelectMode ? "xmark.circle" : "checkmark.circle")
                        }
                    }
                    Divider()
                    Section(header: Text("Export")) {
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section(header: Text("Create")) {
                        Button(action: { showingAddJoke = true }) {
                            Label("Write a Joke", systemImage: "square.and.pencil")
                        }
                        Button(action: { showingTalkToText = true }) {
                            Label("Talk-to-Text", systemImage: "mic.badge.plus")
                        }
                    }
                    Divider()
                    Section(header: Text("Import")) {
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
        }
    }

    @ViewBuilder
    private var importOverlay: some View {
        if isProcessingImages {
            Color.black.opacity(0.5)
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

                    let result = try await FileImportService.shared.importWithPipeline(from: tmpURL)
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

                let result = try await FileImportService.shared.importWithPipeline(from: tmpURL)
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
    
    private func processDocuments(_ urls: [URL]) {
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
                    let result = try await FileImportService.shared.importWithPipeline(from: url)
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
            jokesToExport = jokes.filter { !$0.isDeleted }
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
        let jokesToExport = jokes.filter { !$0.isDeleted }
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
        let targetsToExport = roastTargets.filter { !$0.isDeleted && $0.jokeCount > 0 }
        guard !targetsToExport.isEmpty else { return }
        
        if let url = PDFExportService.exportRoastsToPDF(targets: targetsToExport, fileName: "BitBinder_AllRoasts") {
            shareFile(url)
        }
    }
    
    private func exportAllRoastsToText() {
        let targetsToExport = roastTargets.filter { !$0.isDeleted && $0.jokeCount > 0 }
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
        let newKey = content.normalizedPrefix()
        // Check against existing jokes in current filtered set and full list
        if jokes.contains(where: { $0.content.normalizedPrefix() == newKey }) { return true }
        if let title = title, !title.isEmpty {
            let t = title.lowercased().trimmingCharacters(in: .whitespaces)
            if jokes.contains(where: { $0.title.lowercased().trimmingCharacters(in: .whitespaces) == t }) { return true }
        }
        return false
    }
    
    private func checkPendingVoiceMemoImports() {
        // Use App Group shared defaults for extension communication
        let appGroupIdentifier = "group.The-BitBinder.thebitbinder"
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil else {
            print(" [VoiceMemo] App Group container unavailable")
            return
        }
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print(" [VoiceMemo] App Group not available")
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
        
        // Clear pending imports
        sharedDefaults.removeObject(forKey: "pendingVoiceMemoImports")
        sharedDefaults.synchronize()
        
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
    
    private func encodeParsingFlags(_ flags: ImportParsingFlags) -> String {
        (try? String(data: JSONEncoder().encode(flags), encoding: .utf8)) ?? "{}"
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

// MARK: - Roast Target Components
// Note: FolderChip, JokeRowView, JokeCardView, TheHitsChip, JokesViewMode are now in JokeComponents.swift

struct RoastTargetCard: View {
    let target: RoastTarget

    var body: some View {
        VStack(spacing: 14) {
            // Avatar — async background decode
            AsyncAvatarView(
                photoData: target.photoData,
                size: 58,
                fallbackInitial: String(target.name.prefix(1).uppercased()),
                accentColor: AppTheme.Colors.roastAccent
            )
            .overlay(Circle().stroke(AppTheme.Colors.roastAccent.opacity(0.5), lineWidth: 1.5))

            // Name + count
            VStack(spacing: 3) {
                Text(target.name)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
            }

            // Flame meter
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < min(target.jokeCount, 5) ? "flame.fill" : "flame")
                        .font(.system(size: 9))
                        .foregroundColor(i < min(target.jokeCount, 5) ? AppTheme.Colors.roastAccent : Color.white.opacity(0.20))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.Colors.roastCard))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

struct RoastTargetGridCard: View {
    let target: RoastTarget
    var scale: CGFloat = 1.0
    private let accentColor = AppTheme.Colors.roastAccent
    
    /// Safe property accessors to prevent crashes on invalidated models
    private var safeName: String { target.isValid ? target.name : "" }
    private var safeJokeCount: Int { target.isValid ? target.jokeCount : 0 }
    private var safePhotoData: Data? { target.isValid ? target.photoData : nil }

    private var avatarSize: CGFloat { max(40, 70 * scale) }
    private var initialFontSize: CGFloat { max(14, 24 * scale) }
    private var nameFontSize: CGFloat { max(9, 13 * scale) }
    private var badgeFontSize: CGFloat { max(7, 10 * scale) }
    private var iconSize: CGFloat { max(6, 8 * scale) }
    private var verticalPadding: CGFloat { max(6, 10 * scale) }

    var body: some View {
        VStack(spacing: max(4, 6 * scale)) {
            // Avatar — async background decode
            AsyncAvatarView(
                photoData: safePhotoData,
                size: avatarSize,
                fallbackInitial: String(safeName.prefix(1).uppercased()),
                accentColor: accentColor
            )
            .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 2))

            // Name
            Text(safeName)
                .font(.system(size: nameFontSize, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Joke count badge
            HStack(spacing: max(3, 4 * scale)) {
                Image(systemName: "flame.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(accentColor)
                Text("\(safeJokeCount) roast\(safeJokeCount == 1 ? "" : "s")")
                    .font(.system(size: badgeFontSize, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, 6)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .stroke(accentColor.opacity(0.15), lineWidth: 0.5)
        )
    }
}

struct RoastTargetListRow: View {
    let target: RoastTarget
    private let accentColor = AppTheme.Colors.roastAccent
    
    /// Safe property accessors to prevent crashes on invalidated models
    private var safeName: String { target.isValid ? target.name : "" }
    private var safeJokeCount: Int { target.isValid ? target.jokeCount : 0 }
    private var safePhotoData: Data? { target.isValid ? target.photoData : nil }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Avatar — async background decode
            AsyncAvatarView(
                photoData: safePhotoData,
                size: 50,
                fallbackInitial: String(safeName.prefix(1).uppercased()),
                accentColor: accentColor
            )
            .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 1.5))

            // Target info
            VStack(alignment: .leading, spacing: 4) {
                Text(safeName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                    Text("\(safeJokeCount) roast\(safeJokeCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}
