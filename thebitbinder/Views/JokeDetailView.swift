//
//  JokeDetailView.swift
//  thebitbinder
//
//  Writer-first joke editor, redesigned for ADHD brains.
//  The bit is the page — no form-field chrome, no hidden panels.
//  Downstage tray keeps alt punches visible. Floating action bar
//  gives every joke a next move. Auto-save runs silently underneath.
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct JokeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var bitBuddyDrawer: BitBuddyDrawerController
    @EnvironmentObject private var userPreferences: UserPreferences
    @AppStorage("roastModeEnabled") private var roastMode = false

    @Bindable var joke: Joke
    @State private var showingFolderPicker = false
    @State private var showingDeleteAlert = false
    @State private var showingNotes = false
    @State private var showingTags = false
    @State private var showingSetListPicker = false
    @State private var folders: [JokeFolder] = []
    @State private var setLists: [SetList] = []

    @ObservedObject private var autoSave = AutoSaveManager.shared
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var isRecording = false
    @State private var showingPermissionAlert = false
    @State private var saveError: String?
    @State private var showingSaveError = false
    @State private var recordingError: String?
    @State private var showingRecordingError = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title, content
    }

    // MARK: - Computed Helpers

    private var folderChipLabel: String {
        let f = joke.folders ?? []
        if f.isEmpty { return "Unfiled" }
        if f.count == 1 { return f.first?.name ?? "Folder" }
        return "\(f.count) folders"
    }

    private var isFiled: Bool {
        !(joke.folders ?? []).isEmpty
    }

    private var wordCount: Int {
        joke.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Body

    var body: some View {
        lifecycleConfiguredEditor
    }

    private var styledEditor: some View {
        editorRoot
            .animation(EffortlessAnimation.smooth, value: focusedField == nil)
            .animation(EffortlessAnimation.smooth, value: isRecording)
            .background(Color(UIColor.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .tint(roastMode ? FirePalette.core : .accentColor)
    }

    private var alertConfiguredEditor: some View {
        styledEditor
            .alert(joke.isTrashed ? "Restore Joke" : "Move to Trash",
                   isPresented: $showingDeleteAlert) {
                deleteAlertButtons
            } message: {
                Text(joke.isTrashed
                     ? "Restore this joke from Trash?"
                     : "Are you sure? You can restore it from Trash later.")
            }
            .alert("Save Failed", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Your changes might not be saved. Try editing again.")
            }
            .alert("Recording Problem", isPresented: $showingRecordingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recordingError ?? "Couldn't transcribe your audio. Try again.")
            }
            .alert("Microphone Access Needed", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("BitBinder needs microphone and speech recognition access to transcribe your voice. Enable them in Settings.")
            }
    }

    private var sheetConfiguredEditor: some View {
        alertConfiguredEditor
            .sheet(isPresented: $showingFolderPicker) {
                MultiFolderPickerView(
                    selectedFolders: Binding(
                        get: { joke.folders ?? [] },
                        set: { joke.folders = $0; scheduleAutoSave() }
                    ),
                    allFolders: folders
                )
            }
            .sheet(isPresented: $showingSetListPicker) {
                SetListPickerForJoke(joke: joke, allSetLists: setLists)
            }
            .sheet(isPresented: $showingNotes) {
                NotesSheet(joke: joke, autoSave: { scheduleAutoSave() })
            }
            .sheet(isPresented: $showingTags) {
                TagsSheet(joke: joke, autoSave: { scheduleAutoSave() })
            }
    }

    private var lifecycleConfiguredEditor: some View {
        sheetConfiguredEditor
            .onChange(of: speechManager.isRecording) { oldValue, newValue in
                if oldValue && !newValue && isRecording {
                    stopRecordingAndAppend()
                }
            }
            .onChange(of: speechManager.error) { _, newValue in
                if let msg = newValue {
                    recordingError = msg
                    showingRecordingError = true
                    speechManager.error = nil
                    withAnimation { isRecording = false }
                }
            }
            .onChange(of: showingFolderPicker) { _, isOpen in
                if isOpen {
                    var descriptor = FetchDescriptor<JokeFolder>(
                        predicate: #Predicate { !$0.isTrashed }
                    )
                    descriptor.sortBy = [SortDescriptor(\JokeFolder.name)]
                    folders = (try? modelContext.fetch(descriptor)) ?? []
                }
            }
            .onChange(of: showingSetListPicker) { _, isOpen in
                if isOpen {
                    var descriptor = FetchDescriptor<SetList>(
                        predicate: #Predicate { !$0.isTrashed }
                    )
                    descriptor.sortBy = [SortDescriptor(\SetList.name)]
                    setLists = (try? modelContext.fetch(descriptor)) ?? []
                }
            }
            .onChange(of: joke.content) { _, _ in scheduleAutoSave() }
            .onChange(of: joke.title) { _, _ in scheduleAutoSave() }
            .onChange(of: joke.notes) { _, _ in scheduleAutoSave() }
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            // .onDisappear does NOT fire when the app is backgrounded while this
            // screen is still on top, so flush a save on any non-active phase to
            // avoid losing edits made just before the user swipes the app away.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { saveJokeNow() }
            }
    }

    private var editorRoot: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Title
                    TextField("Give it a name\u{2026}", text: $joke.title, axis: .vertical)
                        .font(.title.weight(.bold))
                        .lineLimit(3)
                        .focused($focusedField, equals: .title)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                    // Meta strip + folder chip (hidden while writing)
                    if focusedField != .content {
                        metaStrip
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                    }

                    // The bit — plain text, no container
                    bitContentSection
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    Color.clear.frame(height: 90)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 8) {
                if isRecording {
                    recordingBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if focusedField == nil || isRecording {
                    actionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Meta Strip

    private var metaStrip: some View {
        HStack(spacing: 0) {
            Text("\(wordCount) words")
            Text(" \u{00B7} ")
                .foregroundStyle(.tertiary)
            Text(joke.dateCreated.formatted(.dateTime.month(.abbreviated).day()))

            Spacer()

            Button {
                HapticEngine.shared.tap()
                showingFolderPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isFiled ? "folder.fill" : "folder")
                        .font(.system(size: 10))
                    Text(folderChipLabel)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isFiled ? .bitbinderAccent : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isFiled
                              ? Color.bitbinderAccent.opacity(0.12)
                              : Color(UIColor.tertiarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func handleAppear() {
        guard joke.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard scenePhase == .active else { return }
            focusedField = .content
        }
    }

    private func handleDisappear() {
        saveJokeNow()
        folders = []
    }

    // MARK: - BIT Content

    private var bitContentSection: some View {
        ZStack(alignment: .topLeading) {
            if joke.content.isEmpty {
                Text("Start writing your bit\u{2026}")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(UIColor.placeholderText))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $joke.content)
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(8)
                .frame(minHeight: 200)
                .focused($focusedField, equals: .content)
                .scrollContentBackground(.hidden)
                // TextEditor's UITextView adds a 5pt lineFragmentPadding on
                // each side; cancel it so the bit text left-aligns with the
                // title field above (which has no such inset).
                .padding(.horizontal, -5)
                .contextMenu {
                    Button { insertBeat("\u{2022} ") } label: {
                        Label("Bullet", systemImage: "list.bullet")
                    }
                    Button { insertBeat("\u{2014}") } label: {
                        Label("Dash", systemImage: "minus")
                    }
                    Button { insertBeat("[beat] ") } label: {
                        Label("Beat", systemImage: "pause")
                    }
                    Button { insertBeat("[act out] ") } label: {
                        Label("Act Out", systemImage: "figure.stand")
                    }
                    Button { insertBeat("[callback] ") } label: {
                        Label("Callback", systemImage: "arrow.uturn.backward")
                    }
                    Button { insertBeat("[tag] ") } label: {
                        Label("Tag", systemImage: "text.append")
                    }
                }
        }
    }

    private func insertBeat(_ text: String) {
        if joke.content.isEmpty || joke.content.hasSuffix("\n") {
            joke.content += text
        } else {
            joke.content += "\n" + text
        }
        scheduleAutoSave()
    }

    // Downstage tray and tags are now in sheets — accessed from the overflow menu.

    // MARK: - Floating Action Bar

    private var actionBar: some View {
        HStack(spacing: 4) {
            if userPreferences.bitBuddyEnabled && !roastMode {
                actionButton(icon: "sparkle", label: "Punch up") {
                    openBitBuddyPunchUp()
                    haptic(.medium)
                }
            }

            actionButton(
                icon: isRecording ? "stop.circle.fill" : "mic",
                label: isRecording ? "Stop" : "Record",
                tint: isRecording ? .red : nil,
                active: isRecording
            ) {
                toggleRecording()
            }

        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
    }

    private func actionButton(
        icon: String,
        label: String,
        tint: Color? = nil,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(tint ?? .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((tint ?? .accentColor).opacity(active ? 0.14 : 0))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - BitBuddy Punch Up

    private func openBitBuddyPunchUp() {
        guard !roastMode else { return }

        let service = BitBuddyService.shared
        service.focusedJoke = BitBuddyJokeSummary(
            id: joke.id,
            title: joke.title,
            content: joke.content,
            tags: joke.tags,
            dateCreated: joke.dateCreated
        )
        service.pendingMessage = "Punch up this joke"
        focusedField = nil
        bitBuddyDrawer.open()
    }

    // MARK: - Recording Banner

    private var recordingBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .modifier(PulseEffect())

            Text(speechManager.transcribedText.isEmpty
                 ? "Listening..."
                 : speechManager.transcribedText.suffix(80))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            Button {
                stopRecordingAndAppend()
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .padding(.horizontal, 12)
    }

    // MARK: - Speech Recognition

    private func toggleRecording() {
        if isRecording {
            stopRecordingAndAppend()
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
        speechManager.transcribedText = ""
        speechManager.startRecording()
        withAnimation { isRecording = true }
        haptic(.light)
    }

    private func stopRecordingAndAppend() {
        speechManager.stopRecording()
        let text = speechManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            if joke.content.isEmpty {
                joke.content = text
            } else {
                joke.content += "\n" + text
            }
            scheduleAutoSave()
        }
        speechManager.transcribedText = ""
        withAnimation { isRecording = false }
        haptic(.medium)
    }

    // MARK: - Auto-Save

    private func scheduleAutoSave() {
        autoSave.scheduleSave { [self] in
            // The debounced closure can fire ~1.5s late — after the joke was
            // trashed/removed and detached from its context. Bail rather than
            // mutate a deleted model.
            guard joke.modelContext != nil else { return }
            joke.dateModified = Date()
            joke.updateWordCount()
            do {
                try modelContext.save()
            } catch {
                print(" [JokeDetailView] Auto-save failed: \(error)")
                saveError = "Your changes couldn't be saved: \(error.localizedDescription)"
                showingSaveError = true
            }
        }
    }

    private func saveJokeNow() {
        guard joke.modelContext != nil else { return }
        if joke.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !joke.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            joke.title = KeywordTitleGenerator.title(from: joke.content)
        }
        joke.dateModified = Date()
        joke.updateWordCount()
        do {
            try modelContext.save()
        } catch {
            print(" [JokeDetailView] Save failed: \(error)")
            saveError = "Your changes couldn't be saved: \(error.localizedDescription)"
            showingSaveError = true
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if focusedField != nil {
                Button("Done") {
                    focusedField = nil
                }
                .fontWeight(.semibold)
            } else {
                Menu {
                    Button {
                        showingNotes = true
                    } label: {
                        Label(
                            joke.notes.isEmpty ? "Notes" : "Notes (\(joke.notes.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count))",
                            systemImage: "lightbulb"
                        )
                    }

                    Button {
                        showingTags = true
                    } label: {
                        Label(
                            joke.tags.isEmpty ? "Tags" : "Tags (\(joke.tags.count))",
                            systemImage: "tag"
                        )
                    }

                    Button {
                        showingSetListPicker = true
                    } label: {
                        Label("Add to Set", systemImage: "list.bullet")
                    }

                    Section {
                        Button {
                            withAnimation { joke.isHit.toggle(); joke.dateModified = Date() }
                            HapticEngine.shared.starToggle(joke.isHit)
                            do { try modelContext.save() } catch {
                                saveError = "Couldn't save: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        } label: {
                            Label(
                                joke.isHit ? "Remove Hit" : "Mark as Hit",
                                systemImage: joke.isHit
                                    ? (roastMode ? "flame.fill" : "star.fill")
                                    : (roastMode ? "flame" : "star")
                            )
                        }

                        Button {
                            withAnimation { joke.isOpenMic.toggle(); joke.dateModified = Date() }
                            haptic(.medium)
                            do { try modelContext.save() } catch {
                                saveError = "Couldn't save: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        } label: {
                            Label(
                                joke.isOpenMic ? "Remove Open Mic" : "Open Mic Ready",
                                systemImage: joke.isOpenMic ? "mic.fill" : "mic"
                            )
                        }
                    }

                    Section {
                        if joke.isTrashed {
                            Button {
                                HapticEngine.shared.success()
                                joke.restoreFromTrash()
                                do { try modelContext.save() } catch {
                                    print(" [JokeDetailView] Failed to save after restore: \(error)")
                                }
                                dismiss()
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward.circle")
                            }
                        } else {
                            Button(role: .destructive) {
                                HapticEngine.shared.warning()
                                showingDeleteAlert = true
                            } label: {
                                Label("Move to Trash", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                }
                .accessibilityLabel("Joke actions")
            }
        }

        ToolbarItem(placement: .keyboard) {
            HStack {
                // Subtle, transient save feedback — only visible while editing.
                SaveStatusIndicator(roastMode: roastMode)
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .fontWeight(.semibold)
            }
        }
    }


    // MARK: - Delete Alert

    @ViewBuilder
    private var deleteAlertButtons: some View {
        if joke.isTrashed {
            Button("Restore") {
                joke.restoreFromTrash()
                do { try modelContext.save() } catch {
                    print(" [JokeDetailView] Failed to save after restore: \(error)")
                }
                dismiss()
            }
        } else {
            Button("Move to Trash", role: .destructive) {
                joke.moveToTrash()
                do { try modelContext.save() } catch {
                    print(" [JokeDetailView] Failed to save after trash: \(error)")
                }
                dismiss()
            }
        }
        Button("Cancel", role: .cancel) { }
    }
}

// MARK: - Set List Picker (add joke to set lists)

struct SetListPickerForJoke: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    let joke: Joke
    let allSetLists: [SetList]

    private func contains(_ setList: SetList) -> Bool {
        setList.jokeIDs.contains(joke.id)
    }

    private func toggle(_ setList: SetList) {
        if contains(setList) {
            var ids = setList.jokeIDs
            ids.removeAll { $0 == joke.id }
            setList.jokeIDs = ids
        } else {
            var ids = setList.jokeIDs
            ids.append(joke.id)
            setList.jokeIDs = ids
        }
        setList.dateModified = Date()
        do { try modelContext.save() } catch {
            print(" [SetListPicker] Save failed: \(error)")
        }
        haptic(.light)
    }

    var body: some View {
        NavigationStack {
            Group {
                if allSetLists.isEmpty {
                    ContentUnavailableView(
                        "No Set Lists",
                        systemImage: "music.note.list",
                        description: Text("Create a set list first, then add jokes to it.")
                    )
                } else {
                    List(allSetLists) { setList in
                        Button { toggle(setList) } label: {
                            HStack {
                                Label(setList.name, systemImage: "music.note.list")
                                Spacer()
                                if contains(setList) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(roastMode ? FirePalette.core : .accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Folder Picker

struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFolder: JokeFolder?
    let folders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedFolder = nil
                    dismiss()
                } label: {
                    HStack {
                        Label("No Folder", systemImage: "tray")
                        Spacer()
                        if selectedFolder == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(roastMode ? FirePalette.core : .accentColor)
                        }
                    }
                }

                ForEach(folders) { folder in
                    Button {
                        selectedFolder = folder
                        dismiss()
                    } label: {
                        HStack {
                            Label(folder.name, systemImage: "folder.fill")
                            Spacer()
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(roastMode ? FirePalette.core : .accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Multi-Folder Picker

struct MultiFolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFolders: [JokeFolder]
    let allFolders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false

    private func isSelected(_ folder: JokeFolder) -> Bool {
        selectedFolders.contains(where: { $0.id == folder.id })
    }

    private func toggleFolder(_ folder: JokeFolder) {
        if isSelected(folder) {
            selectedFolders.removeAll(where: { $0.id == folder.id })
        } else {
            selectedFolders.append(folder)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if selectedFolders.isEmpty {
                        Text("No folders selected")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(selectedFolders) { folder in
                            HStack {
                                Label(folder.name, systemImage: "folder.fill")
                                Spacer()
                                Button { toggleFolder(folder) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .accessibilityLabel("Remove \(folder.name)")
                            }
                        }
                    }
                } header: {
                    Text("Selected Folders (\(selectedFolders.count))")
                }

                Section {
                    Button { selectedFolders = [] } label: {
                        Label("Clear All Folders", systemImage: "tray")
                    }
                    .disabled(selectedFolders.isEmpty)

                    ForEach(allFolders.filter { !isSelected($0) }) { folder in
                        Button { toggleFolder(folder) } label: {
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundColor(roastMode ? FirePalette.core : .accentColor)
                            }
                        }
                    }
                } header: {
                    Text("Available Folders")
                }
            }
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Notes Sheet

private struct NotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var joke: Joke
    var autoSave: () -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                if joke.notes.isEmpty {
                    Text("Alt punches, setup variants, stage notes\u{2026}")
                        .font(.body)
                        .foregroundStyle(Color(UIColor.placeholderText))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $joke.notes)
                    .font(.body)
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        autoSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .roastModeTint()
    }
}

// MARK: - Tags Sheet

private struct TagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var joke: Joke
    var autoSave: () -> Void

    @State private var newTagText = ""
    @FocusState private var isNewTagFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Existing tags
                if joke.tags.isEmpty {
                    Text("No tags yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(joke.tags, id: \.self) { tag in
                            HStack(spacing: 5) {
                                Text(tag)
                                    .font(.system(size: 14, weight: .medium))
                                Button {
                                    var current = joke.tags
                                    current.removeAll { $0 == tag }
                                    joke.tags = current
                                    joke.dateModified = Date()
                                    autoSave()
                                    haptic(.light)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                            .foregroundColor(.bitbinderAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.bitbinderAccent.opacity(0.1))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Add tag field
                HStack(spacing: 10) {
                    TextField("Add a tag\u{2026}", text: $newTagText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isNewTagFocused)
                        .onSubmit { commitTag() }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )

                    Button {
                        commitTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.bitbinderAccent)
                    }
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { isNewTagFocused = true }
        }
        .roastModeTint()
    }

    private func commitTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !joke.tags.contains(trimmed) else {
            newTagText = ""
            return
        }
        var current = joke.tags
        current.append(trimmed)
        joke.tags = current
        joke.dateModified = Date()
        autoSave()
        haptic(.light)
        newTagText = ""
    }
}

// MARK: - Flow Layout for Tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - Pulse Animation

private struct PulseEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing && !reduceMotion ? 0.3 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { if !reduceMotion { isPulsing = true } }
    }
}
