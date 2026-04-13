//
//  JokeDetailView.swift
//  thebitbinder
//
//  Refactored for cleaner, writer-focused experience
//  Progressive disclosure, distraction-free editing, clear hierarchy
//   Now with auto-save and effortless interactions
//

import SwiftUI
import SwiftData

struct JokeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @Bindable var joke: Joke
    @State private var isEditing = false
    @State private var showingFolderPicker = false
    @State private var showingDeleteAlert = false
    @State private var showingMetadata = false
    // Folders loaded lazily — only when the picker sheet opens
    @State private var folders: [JokeFolder] = []
    
    // Auto-save state
    @StateObject private var autoSave = AutoSaveManager.shared
    @State private var saveError: String?
    @State private var showingSaveError = false
    
    // Focus for immediate writing
    @FocusState private var contentFocused: Bool
    @FocusState private var titleFocused: Bool
    
    private var accentTint: Color { roastMode ? .orange : .accentColor }
    
    private var displayTitle: String {
        joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                
                // MARK: - Status Badges (compact, top)
                statusBadges
                
                // MARK: - Title Area
                titleSection
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                
                // MARK: - Word Count (subtle)
                if !joke.content.isEmpty {
                    Text("\(joke.content.split(separator: " ").count) words")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                }
                
                // Soft divider
                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                
                // MARK: - Content Area (the workspace)
                contentSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // MARK: - Tags (floating pills)
                if !joke.tags.isEmpty && !isEditing {
                    tagsSection
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
                
                // MARK: - Folder Badges
                if !isEditing {
                    folderBadges
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
                
                // MARK: - Metadata (collapsible, tucked away)
                if !isEditing {
                    metadataSection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
                
                Spacer(minLength: 60)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(UIColor.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .tint(accentTint)
        .alert(joke.isDeleted ? "Restore Joke" : "Move to Trash", isPresented: $showingDeleteAlert) {
            deleteAlertButtons
        } message: {
            Text(joke.isDeleted
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
                var descriptor = FetchDescriptor<JokeFolder>(predicate: #Predicate { !$0.isDeleted })
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
        .onDisappear {
            saveJokeNow()
            folders = []
        }
    }
    
    // MARK: - Status Badges
    
    @ViewBuilder
    private var statusBadges: some View {
        let hasBadges = joke.isHit || joke.isOpenMic
        if hasBadges && !isEditing {
            HStack(spacing: 8) {
                if joke.isHit {
                    HStack(spacing: 4) {
                        Image(systemName: roastMode ? "flame.fill" : "star.fill")
                            .font(.caption2.weight(.semibold))
                        Text(roastMode ? "Fire" : "Hit")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(roastMode ? Color.orange : accentTint, in: Capsule())
                }
                if joke.isOpenMic {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.caption2.weight(.semibold))
                        Text("Open Mic")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }
    
    // MARK: - Title Section
    
    @ViewBuilder
    private var titleSection: some View {
        if isEditing {
            TextField("Give it a name...", text: $joke.title, axis: .vertical)
                .font(.title2.weight(.bold))
                .lineLimit(1...4)
                .focused($titleFocused)
        } else {
            Text(displayTitle)
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { enterEditing() }
        }
    }
    
    // MARK: - Content Section (the writing canvas)
    
    @ViewBuilder
    private var contentSection: some View {
        if isEditing {
            TextEditor(text: $joke.content)
                .font(.body.leading(.loose))
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .focused($contentFocused)
                .frame(minHeight: 320)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
        } else {
            Group {
                if joke.content.isEmpty {
                    Text("Tap to start writing...")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.5))
                        .italic()
                } else {
                    Text(joke.content)
                        .font(.body.leading(.loose))
                        .lineSpacing(6)
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { enterEditing(focusContent: true) }
        }
    }
    
    // MARK: - Tags Section
    
    @ViewBuilder
    private var tagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(joke.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .foregroundColor(accentTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accentTint.opacity(0.1), in: Capsule())
                }
            }
        }
    }
    
    // MARK: - Folder Badges
    
    @ViewBuilder
    private var folderBadges: some View {
        let jokeF = joke.folders ?? []
        if !jokeF.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(jokeF) { folder in
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                            Text(folder.name)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                    }
                    
                    // Quick add folder button
                    Button {
                        HapticEngine.shared.tap()
                        showingFolderPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color(UIColor.tertiarySystemFill), in: Circle())
                    }
                }
            }
        } else {
            Button {
                HapticEngine.shared.tap()
                showingFolderPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                    Text("Add to Folder")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(UIColor.tertiarySystemFill), in: Capsule())
            }
        }
    }
    
    // MARK: - Metadata Section
    
    @ViewBuilder
    private var metadataSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showingMetadata.toggle() }
            } label: {
                HStack {
                    Text("Details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(showingMetadata ? 90 : 0))
                }
                .padding(.vertical, 8)
            }
            
            if showingMetadata {
                VStack(spacing: 10) {
                    metadataRow("Created", value: joke.dateCreated.formatted(date: .abbreviated, time: .shortened))
                    metadataRow("Modified", value: joke.dateModified.formatted(date: .abbreviated, time: .shortened))
                    if let source = joke.importSource, !source.isEmpty {
                        metadataRow("Imported from", value: source)
                    }
                    if let confidence = joke.importConfidence, !confidence.isEmpty {
                        metadataRow("Confidence", value: confidence.capitalized, valueColor: accentTint)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    @ViewBuilder
    private func metadataRow(_ label: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(valueColor)
        }
    }
    
    // MARK: - Editing Helpers
    
    private func enterEditing(focusContent: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
        HapticEngine.shared.tap()
        // Slight delay so the TextEditor is mounted before focusing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if focusContent {
                contentFocused = true
            } else {
                titleFocused = true
            }
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
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                if isEditing {
                    Button {
                        saveJokeNow()
                        HapticEngine.shared.success()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing = false
                            contentFocused = false
                            titleFocused = false
                        }
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                    }
                } else {
                    // Actions menu — keeps the writing space clean
                    Menu {
                        // Hit toggle
                        Button {
                            withAnimation {
                                joke.isHit.toggle()
                                joke.dateModified = Date()
                            }
                            HapticEngine.shared.starToggle(joke.isHit)
                            do { try modelContext.save() } catch {
                                saveError = "Couldn't save hit status: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        } label: {
                            Label(
                                joke.isHit ? "Remove from Hits" : "Add to Hits",
                                systemImage: roastMode
                                    ? (joke.isHit ? "flame.fill" : "flame")
                                    : (joke.isHit ? "star.fill" : "star")
                            )
                        }
                        
                        // Open Mic toggle
                        Button {
                            withAnimation {
                                joke.isOpenMic.toggle()
                                joke.dateModified = Date()
                            }
                            HapticEngine.shared.tap()
                            do { try modelContext.save() } catch {
                                saveError = "Couldn't save open mic status: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        } label: {
                            Label(
                                joke.isOpenMic ? "Remove from Open Mic" : "Add to Open Mic",
                                systemImage: joke.isOpenMic ? "mic.slash" : "mic.fill"
                            )
                        }
                        
                        Divider()
                        
                        // Folders
                        Button {
                            HapticEngine.shared.tap()
                            showingFolderPicker = true
                        } label: {
                            let folderCount = (joke.folders ?? []).count
                            Label(
                                folderCount == 0 ? "Add to Folder" : "Manage Folders (\(folderCount))",
                                systemImage: "folder"
                            )
                        }
                        
                        Divider()
                        
                        // Delete / Restore
                        if joke.isDeleted {
                            Button {
                                HapticEngine.shared.success()
                                joke.restoreFromTrash()
                                dismiss()
                            } label: {
                                Label("Restore from Trash", systemImage: "arrow.uturn.backward")
                            }
                        } else {
                            Button(role: .destructive) {
                                HapticEngine.shared.warning()
                                showingDeleteAlert = true
                            } label: {
                                Label("Move to Trash", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                            .foregroundColor(accentTint)
                    }
                }
            }
        }
    }
    
    // MARK: - Delete Alert Buttons
    
    @ViewBuilder
    private var deleteAlertButtons: some View {
        if joke.isDeleted {
            Button("Restore") {
                joke.restoreFromTrash()
                dismiss()
            }
        } else {
            Button("Move to Trash", role: .destructive) {
                joke.moveToTrash()
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
                                .foregroundColor(roastMode ? .orange : .accentColor)
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
                                    .foregroundColor(roastMode ? .orange : .accentColor)
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
                                        .foregroundColor(.accentColor.opacity(0.7))
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
                                    .foregroundColor(roastMode ? .orange : .accentColor)
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
