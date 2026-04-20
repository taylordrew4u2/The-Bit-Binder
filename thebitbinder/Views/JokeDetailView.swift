//
//  JokeDetailView.swift
//  thebitbinder
//
//  A comfortable, writer-first space for creating and editing jokes.
//  Always-editable canvas — no mode-switching, just start writing.
//  Includes a Notes & Ideas scratchpad for brainstorming.
//  Auto-save keeps your work safe while you focus on the funny.
//

import SwiftUI
import SwiftData

struct JokeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @Bindable var joke: Joke
    @State private var showingFolderPicker = false
    @State private var showingDeleteAlert = false
    @State private var showingMetadata = false
    @State private var showingNotes = false
    @State private var folders: [JokeFolder] = []

    // Auto-save state
    @StateObject private var autoSave = AutoSaveManager.shared
    @State private var saveError: String?
    @State private var showingSaveError = false
    
    @FocusState private var focusedField: Field?
    
    // Inline tag editing
    @State private var newTagText = ""
    @State private var isAddingTag = false
    
    private enum Field: Hashable {
        case title, content, notes, newTag
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: - Title Area (always editable)
                TextField("Give it a name…", text: $joke.title, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .lineLimit(3)
                    .focused($focusedField, equals: .title)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: - Tappable status pills + word count
                //
                // Hit / Fire and Open Mic used to live both here as read-only
                // badges AND as toggle rows further down the page — one pill
                // per state is enough. Tap to toggle.
                statusPillsRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: - Content Area (always editable, the main canvas)
                ZStack(alignment: .topLeading) {
                    if joke.content.isEmpty {
                        Text("Start writing your joke…")
                            .font(.body)
                            .foregroundColor(Color(UIColor.placeholderText))
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $joke.content)
                        .font(.body)
                        .lineSpacing(6)
                        .frame(minHeight: 300)
                        .focused($focusedField, equals: .content)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // MARK: - Tags (inline editing)
                tagsSection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // MARK: - Notes & Ideas (scratchpad — collapsed by default)
                notesSection
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                // MARK: - Folders
                foldersRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: - Metadata (collapsible)
                metadataSection
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(UIColor.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .tint(roastMode ? FirePalette.core : .accentColor)
        .alert(joke.isTrashed ? "Restore Joke" : "Move to Trash", isPresented: $showingDeleteAlert) {
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
        .sheet(isPresented: $showingFolderPicker) {
            MultiFolderPickerView(
                selectedFolders: Binding(
                    get: { joke.folders ?? [] },
                    set: { joke.folders = $0 }
                ),
                allFolders: folders
            )
        }
        .onChange(of: showingFolderPicker) { _, isOpen in
            if isOpen {
                var descriptor = FetchDescriptor<JokeFolder>(predicate: #Predicate { !$0.isTrashed })
                descriptor.sortBy = [SortDescriptor(\JokeFolder.name)]
                folders = (try? modelContext.fetch(descriptor)) ?? []
            }
        }
        .onChange(of: joke.content) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: joke.title) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: joke.notes) { _, _ in
            scheduleAutoSave()
        }
        .onAppear {
            // Auto-focus content for new/empty jokes so you can write immediately
            if joke.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    focusedField = .content
                }
            }
        }
        .onDisappear {
            saveJokeNow()
            folders = []
        }
    }
    
    // MARK: - Tags
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(joke.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption)
                            Button {
                                var current = joke.tags
                                current.removeAll { $0 == tag }
                                joke.tags = current
                                joke.dateModified = Date()
                                scheduleAutoSave()
                                haptic(.light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    
                    if isAddingTag {
                        HStack(spacing: 4) {
                            TextField("tag", text: $newTagText)
                                .font(.caption)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .newTag)
                                .frame(minWidth: 50, maxWidth: 120)
                                .onSubmit {
                                    commitNewTag()
                                }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.08), in: Capsule())
                    } else {
                        Button {
                            isAddingTag = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedField = .newTag
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .medium))
                                Text("Add")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                        }
                    }
                }
            }
        }
    }
    
    private func commitNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty && !joke.tags.contains(trimmed) {
            var current = joke.tags
            current.append(trimmed)
            joke.tags = current
            joke.dateModified = Date()
            scheduleAutoSave()
            haptic(.light)
        }
        newTagText = ""
        isAddingTag = false
    }
    
    // MARK: - Formatting Helpers
    
    /// Wraps the last word (or appends) bold markers **text**
    private func insertBold() {
        if joke.content.hasSuffix("\n") || joke.content.isEmpty {
            joke.content += "**bold**"
        } else {
            joke.content += " **bold**"
        }
        scheduleAutoSave()
    }
    
    /// Inserts a bullet point on a new line for marking beats
    private func insertBullet() {
        if joke.content.isEmpty {
            joke.content = "• "
        } else if joke.content.hasSuffix("\n") {
            joke.content += "• "
        } else {
            joke.content += "\n• "
        }
        scheduleAutoSave()
    }
    
    // MARK: - Notes & Ideas
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(EffortlessAnimation.smooth) {
                    showingNotes.toggle()
                }
                HapticEngine.shared.tap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    
                    Text("Notes & Ideas")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    if !joke.notes.isEmpty && !showingNotes {
                        Circle()
                            .fill(Color.bitbinderAccent)
                            .frame(width: 6, height: 6)
                    }
                    
                    Spacer()
                    
                    Image(systemName: showingNotes ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if showingNotes {
                ZStack(alignment: .topLeading) {
                    if joke.notes.isEmpty {
                        Text("Jot down setups, tags, alternate punchlines…")
                            .font(.subheadline)
                            .foregroundColor(Color(UIColor.placeholderText))
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $joke.notes)
                        .font(.subheadline)
                        .lineSpacing(5)
                        .frame(minHeight: 100)
                        .focused($focusedField, equals: .notes)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Status pills (tappable toggles + word count)

    private var statusPillsRow: some View {
        HStack(spacing: 8) {
            statusPill(
                isOn: joke.isHit,
                onSymbol: roastMode ? "flame.fill" : "star.fill",
                offSymbol: roastMode ? "flame" : "star",
                label: roastMode ? "Fire" : "Hit",
                tint: roastMode ? FirePalette.core : .yellow
            ) {
                withAnimation {
                    joke.isHit.toggle()
                    joke.dateModified = Date()
                }
                HapticEngine.shared.starToggle(joke.isHit)
                do { try modelContext.save() } catch {
                    saveError = "Couldn't save hit status: \(error.localizedDescription)"
                    showingSaveError = true
                }
            }

            statusPill(
                isOn: joke.isOpenMic,
                onSymbol: "mic.fill",
                offSymbol: "mic",
                label: "Open Mic",
                tint: .purple
            ) {
                withAnimation {
                    joke.isOpenMic.toggle()
                    joke.dateModified = Date()
                }
                haptic(.medium)
                do { try modelContext.save() } catch {
                    saveError = "Couldn't save open mic status: \(error.localizedDescription)"
                    showingSaveError = true
                }
            }

            Spacer()

            if !joke.content.isEmpty {
                Text("\(joke.content.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
    }

    private func statusPill(
        isOn: Bool,
        onSymbol: String,
        offSymbol: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? onSymbol : offSymbol)
                    .font(.caption2)
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundColor(isOn ? tint : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((isOn ? tint : Color(UIColor.tertiaryLabel)).opacity(isOn ? 0.14 : 0.10))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Folders row

    private var foldersRow: some View {
        Button {
            HapticEngine.shared.tap()
            showingFolderPicker = true
        } label: {
            HStack {
                Label("Folders", systemImage: "folder")
                Spacer()
                let folderCount = (joke.folders ?? []).count
                if folderCount == 0 {
                    Text("None")
                        .foregroundColor(.secondary)
                } else if folderCount == 1 {
                    Text((joke.folders ?? []).first?.name ?? "")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(folderCount)")
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 11)
        }
    }
    
    // MARK: - Metadata
    
    private var metadataSection: some View {
        DisclosureGroup("Details", isExpanded: $showingMetadata) {
            VStack(spacing: 8) {
                metadataRow(label: "Created", value: joke.dateCreated.formatted(date: .abbreviated, time: .shortened))
                metadataRow(label: "Modified", value: joke.dateModified.formatted(date: .abbreviated, time: .shortened))
                if let source = joke.importSource, !source.isEmpty {
                    metadataRow(label: "Imported from", value: source)
                }
                if let confidence = joke.importConfidence, !confidence.isEmpty {
                    HStack {
                        Text("Confidence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(confidence.capitalized)
                            .font(.caption)
                            .foregroundColor(confidence == "high" ? .green : (confidence == "medium" ? Color.accentColor : .orange))
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
    }
    
    // MARK: - Auto-Save
    
    private func scheduleAutoSave() {
        autoSave.scheduleSave { [self] in
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
        ToolbarItem(placement: .principal) {
            SaveStatusIndicator(autoSave: autoSave, roastMode: roastMode)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                if joke.isTrashed {
                    Button {
                        HapticEngine.shared.success()
                        joke.restoreFromTrash()
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(.green)
                    }
                } else {
                    Button {
                        HapticEngine.shared.warning()
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        
        ToolbarItem(placement: .keyboard) {
            HStack(spacing: 14) {
                // Bold + Beat formatting shortcuts — only the content editor
                // benefits from these, so we keep them on the keyboard bar
                // instead of a persistent row on the page.
                if focusedField == .content {
                    Button {
                        insertBold()
                        haptic(.light)
                    } label: {
                        Text("B")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Button {
                        insertBullet()
                        haptic(.light)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 13))
                            Text("Beat")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Jump between fields
                Button {
                    switch focusedField {
                    case .title:
                        focusedField = .content
                    case .content:
                        focusedField = .notes
                        if !showingNotes {
                            withAnimation(EffortlessAnimation.smooth) {
                                showingNotes = true
                            }
                        }
                    case .notes:
                        focusedField = .title
                    case .newTag:
                        commitNewTag()
                        focusedField = .content
                    case .none:
                        focusedField = .content
                    }
                } label: {
                    Image(systemName: "arrow.right.arrow.left")
                        .font(.subheadline)
                }

                Spacer()

                Button("Done") {
                    focusedField = nil
                }
                .fontWeight(.medium)
            }
        }
    }
    
    // MARK: - Delete Alert Buttons
    
    @ViewBuilder
    private var deleteAlertButtons: some View {
        if joke.isTrashed {
            Button("Restore") {
                joke.restoreFromTrash()
                do {
                    try modelContext.save()
                } catch {
                    print(" [JokeDetailView] Failed to save after restore: \(error)")
                }
                dismiss()
            }
        } else {
            Button("Move to Trash", role: .destructive) {
                joke.moveToTrash()
                do {
                    try modelContext.save()
                } catch {
                    print(" [JokeDetailView] Failed to save after trash: \(error)")
                }
                dismiss()
            }
        }
        Button("Cancel", role: .cancel) { }
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Multi-Folder Picker (for many-to-many)

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
                                Button {
                                    toggleFolder(folder)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Selected Folders (\(selectedFolders.count))")
                }
                
                Section {
                    Button {
                        selectedFolders = []
                    } label: {
                        Label("Clear All Folders", systemImage: "tray")
                    }
                    .disabled(selectedFolders.isEmpty)
                    
                    ForEach(allFolders.filter { !isSelected($0) }) { folder in
                        Button {
                            toggleFolder(folder)
                        } label: {
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
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
