//
//  BrainstormView.swift
//  thebitbinder
//
//  Brainstorm tab for quick joke thoughts with zoomable grid
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct BrainstormView: View {
    private enum LayoutMode: String {
        case board
        case list
    }

    private struct BoardLayout {
        let boardSize: CGSize
        let noteWidth: CGFloat
        let noteHeight: CGFloat
        let columnCount: Int
        let rowCount: Int
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let horizontalInset: CGFloat
        let verticalInset: CGFloat
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BrainstormIdea> { !$0.isTrashed }, sort: \BrainstormIdea.dateCreated, order: .reverse) private var ideas: [BrainstormIdea]
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("showFullContent") private var showFullContent = true
    @AppStorage("brainstormGridScale") private var brainstormGridScale: Double = 1.0
    @AppStorage("brainstormLayoutMode") private var brainstormLayoutMode: String = LayoutMode.list.rawValue
    
    @State private var showAddSheet = false
    @GestureState private var pinchMagnification: CGFloat = 1.0
    @State private var isRecording = false
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var showingPermissionAlert = false
    
    // Batch select/delete mode
    @State private var isSelectMode = false
    @State private var selectedIdeaIDs: Set<UUID> = []

    // Destructive-action confirmations — tapping Delete on a thought (or on
    // the batch-delete button) stages the action here and presents a
    // confirmation alert before anything is actually removed. Prevents
    // accidental data loss from a fat-fingered context-menu tap.
    @State private var ideaToDelete: BrainstormIdea?
    @State private var showingBatchDeleteConfirmation = false
    
    // Programmatic navigation — avoids NavigationLink gesture conflicts with MagnifyGesture
    @State private var selectedIdea: BrainstormIdea?
    
    // Persistence error surfacing
    @State private var showingTrash = false
    @State private var showTalkToText = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false
    @State private var dragOffsets: [UUID: CGSize] = [:]
    
    // Pinch-to-zoom
    private var effectiveGridScale: CGFloat {
        min(max(CGFloat(brainstormGridScale) * pinchMagnification, 0.5), 2.0)
    }
    
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                brainstormGridScale = Double(min(max(CGFloat(brainstormGridScale) * value.magnification, 0.5), 2.0))
            }
    }

    private var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: brainstormLayoutMode) ?? .board }
        set { brainstormLayoutMode = newValue.rawValue }
    }

    private var batchDeleteAlertTitle: String {
        let count = selectedIdeaIDs.count
        return "Delete \(count) Thought\(count == 1 ? "" : "s")?"
    }

    private var recordingMenuLabel: String {
        isRecording ? "Stop Recording" : "Voice Note"
    }

    private var recordingMenuIcon: String {
        isRecording ? "stop.circle.fill" : "mic.fill"
    }

    private var layoutMenuLabel: String {
        layoutMode == .board ? "Show as List" : "Show as Sticky Notes"
    }

    private var layoutMenuIcon: String {
        layoutMode == .board ? "list.bullet.rectangle" : "square.grid.3x3.fill"
    }

    @ViewBuilder
    private var brainstormContent: some View {
        if ideas.isEmpty {
            emptyState
        } else if layoutMode == .board {
            brainstormBoard
        } else {
            brainstormList
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            brainstormContent
        }
        .navigationDestination(item: $selectedIdea) { idea in
            BrainstormDetailView(idea: idea)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                addIdeaButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                moreActionsMenu()
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            BrainstormTrashView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddBrainstormIdeaSheet(isVoiceNote: false, initialText: "")
        }
        .sheet(isPresented: $showTalkToText) {
            TalkToTextView(selectedFolder: nil, saveToBrainstorm: true)
        }
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable microphone access in Settings to use voice recording.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
        // Single-idea delete confirmation. Bound to `ideaToDelete` being
        // non-nil so we don't need a separate @State Bool.
        .alert("Delete This Thought?", isPresented: Binding(
            get: { ideaToDelete != nil },
            set: { if !$0 { ideaToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { ideaToDelete = nil }
            Button("Delete", role: .destructive) {
                if let idea = ideaToDelete {
                    withAnimation {
                        idea.moveToTrash()
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        print(" [BrainstormView] Failed to save after soft-delete: \(error)")
                        persistenceError = "Could not delete thought: \(error.localizedDescription)"
                        showingErrorAlert = true
                    }
                    ideaToDelete = nil
                }
            }
        } message: {
            Text("This thought will be moved to the Trash. You can restore it from there.")
        }
        // Batch-delete confirmation. Title adapts to count for grammar.
        .alert(
            batchDeleteAlertTitle,
            isPresented: $showingBatchDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                batchDeleteSelectedIdeas()
            }
        } message: {
            Text("These thoughts will be moved to the Trash. You can restore them from there.")
        }
        .tint(Color.bitbinderAccent)
        .onChange(of: speechManager.isRecording) { oldValue, newValue in
            if oldValue && !newValue && isRecording {
                isRecording = false
            }
        }
        .onChange(of: speechManager.error) { _, newValue in
            if let msg = newValue {
                persistenceError = msg
                showingErrorAlert = true
                speechManager.error = nil
            }
        }
    }

    @ViewBuilder
    private func addIdeaButton() -> some View {
        Button {
            showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Add idea")
        }
    }

    @ViewBuilder
    private func moreActionsMenu() -> some View {
        Menu {
            Button {
                toggleRecording()
            } label: {
                Label(recordingMenuLabel, systemImage: recordingMenuIcon)
            }

            Button {
                showTalkToText = true
            } label: {
                Label("Talk to Text", systemImage: "mic.badge.plus")
            }

            Section {
                Button(action: { showFullContent.toggle() }) {
                    Label(
                        showFullContent ? "Show Titles Only" : "Show Full Content",
                        systemImage: showFullContent ? "list.bullet" : "text.justify.leading"
                    )
                }

                Button {
                    brainstormLayoutMode = layoutMode == .board ? LayoutMode.list.rawValue : LayoutMode.board.rawValue
                } label: {
                    Label(layoutMenuLabel, systemImage: layoutMenuIcon)
                }

                if !ideas.isEmpty {
                    Button {
                        isSelectMode.toggle()
                        if !isSelectMode {
                            selectedIdeaIDs.removeAll()
                        }
                    } label: {
                        Label(
                            isSelectMode ? "Cancel Select" : "Select Multiple",
                            systemImage: isSelectMode ? "xmark.circle" : "checkmark.circle"
                        )
                    }
                }
            }

            Section {
                Button {
                    showingTrash = true
                } label: {
                    Label("Trash", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("More Actions")
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        BrainstormEmptyState(
            roastMode: roastMode,
            onAddIdea: { showAddSheet = true }
        )
    }
    
    // MARK: - Board
    private var brainstormBoard: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let layout = boardLayout(for: geo.size)

                ZStack {
                    boardBackground(boardSize: layout.boardSize)

                    ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                        boardNote(idea: idea, index: index, layout: layout)
                    }
                }
                .frame(width: layout.boardSize.width, height: layout.boardSize.height, alignment: .topLeading)
                .background(Color(UIColor.systemGroupedBackground))
            }

            if isSelectMode {
                brainstormBatchActionBar
            }
        }
    }

    private var brainstormList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(ideas) { idea in
                    if isSelectMode {
                        listSelectableCard(idea: idea)
                            .listRowSeparatorTint(Color(red: 0.6, green: 0.7, blue: 0.85).opacity(0.3))
                    } else {
                        Button {
                            selectedIdea = idea
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.content.components(separatedBy: .newlines).first ?? idea.content)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(idea.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    if showFullContent {
                                        Text(idea.content)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                ideaToDelete = idea
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                promoteToJoke(idea)
                            } label: {
                                Label("Promote", systemImage: "arrow.up.doc.fill")
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button {
                                promoteToJoke(idea)
                            } label: {
                                Label("Promote to Joke", systemImage: "arrow.up.doc.fill")
                            }
                            Divider()
                            Button(role: .destructive) {
                                ideaToDelete = idea
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowSeparatorTint(Color(red: 0.6, green: 0.7, blue: 0.85).opacity(0.3))
                    }
                }
            }
            .listStyle(.plain)

            if isSelectMode {
                brainstormBatchActionBar
            }
        }
    }
    
    @ViewBuilder
    private func boardNote(idea: BrainstormIdea, index: Int, layout: BoardLayout) -> some View {
        let isSelected = selectedIdeaIDs.contains(idea.id)
        let noteCenter = resolvedPosition(for: idea, index: index, layout: layout)
        let dragOffset = dragOffsets[idea.id] ?? .zero

        IdeaCard(idea: idea, scale: 1.0, roastMode: roastMode, showFullContent: showFullContent)
            .frame(width: layout.noteWidth)
            .position(x: noteCenter.x + dragOffset.width, y: noteCenter.y + dragOffset.height)
            .scaleEffect(isSelectMode && isSelected ? 0.96 : 1.0)
            .overlay(alignment: .topTrailing) {
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? Color.accentColor : .white.opacity(0.92))
                        .padding(8)
                }
            }
            .dsShadow(.light)
            .onTapGesture {
                if isSelectMode {
                    toggleIdeaSelection(idea)
                } else {
                    selectedIdea = idea
                }
            }
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard !isSelectMode else { return }
                        dragOffsets[idea.id] = value.translation
                    }
                    .onEnded { value in
                        guard !isSelectMode else { return }
                        dragOffsets[idea.id] = nil
                        let nextPoint = CGPoint(
                            x: noteCenter.x + value.translation.width,
                            y: noteCenter.y + value.translation.height
                        )
                        updateBoardPosition(for: idea, point: nextPoint, layout: layout)
                    }
            )
            .contextMenu {
                Button {
                    promoteToJoke(idea)
                } label: {
                    Label("Promote to Joke", systemImage: "arrow.up.doc.fill")
                }
                Divider()
                Button(role: .destructive) {
                    ideaToDelete = idea
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func boardLayout(for viewport: CGSize) -> BoardLayout {
        let safeWidth = max(320, viewport.width)
        let safeHeight = max(420, viewport.height)
        let horizontalInset: CGFloat = 18
        let verticalInset: CGFloat = 18
        let boardWidth = max(0, safeWidth - (horizontalInset * 2))
        let boardHeight = max(0, safeHeight - (verticalInset * 2))

        let noteHeight: CGFloat = showFullContent ? 152 : 116
        let minNoteWidth: CGFloat = 120
        let maxNoteWidth: CGFloat = 178
        let targetColumns = min(4, max(2, Int(ceil(sqrt(Double(max(ideas.count, 1)))))))
        let columnCount = min(max(targetColumns, 1), max(1, ideas.count))
        let rowCount = max(1, Int(ceil(Double(max(ideas.count, 1)) / Double(columnCount))))
        let horizontalSpacing: CGFloat = 12
        let verticalSpacing: CGFloat = 12

        let availableWidth = boardWidth - CGFloat(columnCount - 1) * horizontalSpacing - 24
        let noteWidth = min(maxNoteWidth, max(minNoteWidth, availableWidth / CGFloat(max(columnCount, 1))))

        return BoardLayout(
            boardSize: CGSize(width: boardWidth, height: boardHeight),
            noteWidth: noteWidth,
            noteHeight: noteHeight,
            columnCount: columnCount,
            rowCount: rowCount,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            horizontalInset: 12,
            verticalInset: 12
        )
    }

    private func resolvedPosition(for idea: BrainstormIdea, index: Int, layout: BoardLayout) -> CGPoint {
        if idea.boardPositionX >= 0, idea.boardPositionY >= 0 {
            return clampedBoardPoint(
                CGPoint(x: idea.boardPositionX, y: idea.boardPositionY),
                layout: layout
            )
        }

        let row = index / layout.columnCount
        let column = index % layout.columnCount
        let baseX = layout.horizontalInset + layout.noteWidth / 2 + CGFloat(column) * (layout.noteWidth + layout.horizontalSpacing)
        let baseY = layout.verticalInset + layout.noteHeight / 2 + CGFloat(row) * (layout.noteHeight + layout.verticalSpacing)

        return clampedBoardPoint(
            CGPoint(x: baseX, y: baseY),
            layout: layout
        )
    }

    private func clampedBoardPoint(_ point: CGPoint, layout: BoardLayout) -> CGPoint {
        let halfWidth = layout.noteWidth / 2
        let halfHeight = layout.noteHeight / 2
        let x = min(max(point.x, halfWidth + layout.horizontalInset), layout.boardSize.width - halfWidth - layout.horizontalInset)
        let y = min(max(point.y, halfHeight + layout.verticalInset), layout.boardSize.height - halfHeight - layout.verticalInset)
        return CGPoint(x: x, y: y)
    }

    private func updateBoardPosition(for idea: BrainstormIdea, point: CGPoint, layout: BoardLayout) {
        let clamped = clampedBoardPoint(point, layout: layout)
        idea.boardPositionX = clamped.x
        idea.boardPositionY = clamped.y

        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormView] Failed to save board position: \(error)")
            persistenceError = "Could not save note position: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    @ViewBuilder
    private func boardBackground(boardSize: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(UIColor.systemGroupedBackground))
            .frame(width: boardSize.width, height: boardSize.height)
    }

    @ViewBuilder
    private func listSelectableCard(idea: BrainstormIdea) -> some View {
        let isSelected = selectedIdeaIDs.contains(idea.id)

        Button {
            toggleIdeaSelection(idea)
        } label: {
            ZStack(alignment: .topTrailing) {
                IdeaCard(idea: idea, scale: effectiveGridScale, roastMode: roastMode, showFullContent: showFullContent)
                    .opacity(isSelected ? 0.72 : 1.0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color.accentColor : .gray.opacity(0.55))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }

    private var brainstormBatchActionBar: some View {
        HStack(spacing: 16) {
            Button {
                selectedIdeaIDs = Set(ideas.map(\.id))
            } label: {
                Text("Select All")
                    .font(.subheadline)
            }
            
            Spacer()
            
            Text("\(selectedIdeaIDs.count) selected")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(role: .destructive) {
                // Stage for confirmation — actual batch delete happens
                // in the alert handler below.
                showingBatchDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.bold())
            }
            .disabled(selectedIdeaIDs.isEmpty)
            .tint(.accentColor)
            
            Button {
                isSelectMode = false
                selectedIdeaIDs.removeAll()
            } label: {
                Text("Done")
                    .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
    
    private func toggleIdeaSelection(_ idea: BrainstormIdea) {
        if selectedIdeaIDs.contains(idea.id) {
            selectedIdeaIDs.remove(idea.id)
        } else {
            selectedIdeaIDs.insert(idea.id)
        }
    }
    
    private func batchDeleteSelectedIdeas() {
        withAnimation {
            for idea in ideas where selectedIdeaIDs.contains(idea.id) {
                idea.moveToTrash()
            }
            selectedIdeaIDs.removeAll()
            isSelectMode = false
            do {
                try modelContext.save()
            } catch {
                print(" [BrainstormView] Failed to save after batch soft-delete: \(error)")
                persistenceError = "Could not delete thoughts: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }
    
    // MARK: - Speech Recognition
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            requestPermissionAndStartRecording()
        }
    }
    
    private func requestPermissionAndStartRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    if #available(iOS 17.0, *) {
                        AVAudioApplication.requestRecordPermission { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    self.startRecording()
                                } else {
                                    self.showingPermissionAlert = true
                                }
                            }
                        }
                    } else {
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    self.startRecording()
                                } else {
                                    self.showingPermissionAlert = true
                                }
                            }
                        }
                    }
                default:
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    private func startRecording() {
        guard !isRecording, !speechManager.isRecording else { return }
        speechManager.startRecording()
        isRecording = true
    }
    
    private func stopRecording() {
        speechManager.stopRecording()
        
        // Save the transcribed text as a new idea
        let text = speechManager.transcribedText
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let newIdea = BrainstormIdea(
                content: text,
                colorHex: BrainstormIdea.randomColor(),
                isVoiceNote: true
            )
            modelContext.insert(newIdea)
            do {
                try modelContext.save()
            } catch {
                print(" [BrainstormView] Failed to save voice note idea: \(error)")
                persistenceError = "Could not save voice note: \(error.localizedDescription)"
                showingErrorAlert = true
            }
            speechManager.transcribedText = ""
        }
        
        // Reset recording state with animation so pulsing ring is cleanly removed
        withAnimation(.easeOut(duration: 0.2)) {
            isRecording = false
        }
    }
    
    // MARK: - Promote to Joke
    
    private func promoteToJoke(_ idea: BrainstormIdea) {
        // Create a new joke from the brainstorm idea
        let title = String(idea.content.prefix(60))
        let joke = Joke(content: idea.content, title: title, folder: nil)
        joke.importSource = "Brainstorm"
        
        modelContext.insert(joke)
        
        // Save joke first — only soft-delete the idea once it's confirmed persisted
        do {
            try modelContext.save()
        } catch {
            // Save failed — remove the unsaved joke to avoid a phantom entry
            modelContext.delete(joke)
            print(" [BrainstormView] Failed to save promoted joke: \(error)")
            return
        }
        
        // Only soft-delete the idea after the joke is confirmed saved
        withAnimation {
            idea.moveToTrash()
        }
        
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormView] Joke saved but failed to trash original idea: \(error)")
        }
        
        // Notify user with haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// SpeechRecognitionManager is defined in Services/SpeechRecognitionManager.swift

// MARK: - Idea Card (simplified)

struct IdeaCard: View {
    let idea: BrainstormIdea
    let scale: CGFloat
    let roastMode: Bool
    var showFullContent: Bool = true

    private var previewText: String {
        idea.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text(previewText.isEmpty ? "Untitled thought" : previewText)
                    .font(showFullContent ? .subheadline : .headline)
                    .foregroundColor(.primary)
                    .lineLimit(showFullContent ? 4 : 2)

                Spacer(minLength: 4)

                if idea.isVoiceNote {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                    .foregroundColor(Color.bitbinderAccent)
                }
            }

            HStack(spacing: 6) {
                Text(idea.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundColor(Color(UIColor.tertiaryLabel))

                Spacer()
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Brainstorm Empty State

struct BrainstormEmptyState: View {
    var roastMode: Bool = false
    var onAddIdea: (() -> Void)? = nil
    
    var body: some View {
        BitBinderEmptyState(
            icon: roastMode ? "flame.fill" : "lightbulb.fill",
            title: roastMode ? "No Ideas Yet" : "No Ideas Yet",
            subtitle: "Tap + to write or use the mic to capture thoughts by voice",
            actionTitle: "Add Idea",
            action: onAddIdea,
            roastMode: roastMode
        )
    }
}

#Preview {
    BrainstormView()
        .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
