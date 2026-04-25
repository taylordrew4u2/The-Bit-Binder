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

struct JokeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    @Bindable var joke: Joke
    @State private var showingFolderPicker = false
    @State private var showingDeleteAlert = false
    @State private var showingNotes = false
    @State private var showingSetListPicker = false
    @State private var folders: [JokeFolder] = []
    @State private var setLists: [SetList] = []

    @StateObject private var autoSave = AutoSaveManager.shared
    @State private var saveError: String?
    @State private var showingSaveError = false

    @FocusState private var focusedField: Field?

    @State private var newTagText = ""
    @State private var isAddingTag = false

    private enum Field: Hashable {
        case title, content, notes, newTag
    }

    // MARK: - Computed Helpers

    private var folderChipLabel: String {
        let f = joke.folders ?? []
        if f.isEmpty { return "Unfiled" }
        if f.count == 1 { return f.first?.name ?? "Folder" }
        return "\(f.count) folders"
    }

    private var wordCount: Int {
        joke.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var stageTimeEstimate: String {
        let seconds = max(1, Int(round(Double(wordCount) / 1.75)))
        if seconds < 60 { return "\u{2248} \(seconds) sec on stage" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\u{2248} \(m) min on stage" : "\u{2248} \(m)m \(s)s on stage"
    }

    private var saveStatusText: String {
        if autoSave.isSaving { return "Saving\u{2026}" }
        if let last = autoSave.lastSaveTime,
           Date().timeIntervalSince(last) < 10 {
            return "Saved just now"
        }
        return "Saved"
    }

    private var notesSubtitle: String {
        if joke.notes.isEmpty { return "Tap to add" }
        let lines = joke.notes.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count == 1 { return "1 note \u{00B7} tap to open" }
        return "\(lines.count) notes \u{00B7} tap to open"
    }

    // MARK: - Body

    var body: some View {
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

                    // Meta strip
                    metaStrip
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                    // Status chips (Hit + Open Mic + Folder)
                    statusChipsRow
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // The bit — plain text, no container
                    bitContentSection
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    // Downstage tray — always-visible notes card
                    downstageTray
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                    // Tags
                    tagsSection
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    Color.clear.frame(height: 90)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            if focusedField == nil {
                actionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(EffortlessAnimation.smooth, value: focusedField == nil)
        .background(Color(UIColor.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .tint(roastMode ? FirePalette.core : .accentColor)
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
        .sheet(isPresented: $showingFolderPicker) {
            MultiFolderPickerView(
                selectedFolders: Binding(
                    get: { joke.folders ?? [] },
                    set: { joke.folders = $0 }
                ),
                allFolders: folders
            )
        }
        .sheet(isPresented: $showingSetListPicker) {
            SetListPickerForJoke(joke: joke, allSetLists: setLists)
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
        .onAppear {
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

    // MARK: - Meta Strip

    private var metaStrip: some View {
        HStack(spacing: 0) {
            if focusedField == .content || focusedField == .notes {
                Text("\(wordCount) words")
                Text(" \u{00B7} ")
                    .foregroundStyle(.tertiary)
                Text(stageTimeEstimate)
            } else {
                Text(joke.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                Text(" \u{00B7} ")
                    .foregroundStyle(.tertiary)
                Text("\(wordCount) words")
                Text(" \u{00B7} ")
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(autoSave.isSaving ? Color.yellow : Color.green)
                        .frame(width: 5, height: 5)
                    Text(saveStatusText)
                        .foregroundStyle(autoSave.isSaving ? .secondary : Color.green)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .animation(.none, value: focusedField)
    }

    // MARK: - Status Chips

    private var statusChipsRow: some View {
        HStack(spacing: 6) {
            // Hit / Fire
            Button {
                withAnimation { joke.isHit.toggle(); joke.dateModified = Date() }
                HapticEngine.shared.starToggle(joke.isHit)
                do { try modelContext.save() } catch {
                    saveError = "Couldn't save: \(error.localizedDescription)"
                    showingSaveError = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: joke.isHit
                          ? (roastMode ? "flame.fill" : "star.fill")
                          : (roastMode ? "flame" : "star"))
                        .font(.system(size: 11))
                    Text(roastMode ? "Fire" : "Hit")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(joke.isHit ? Color(red: 0.54, green: 0.40, blue: 0) : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(joke.isHit
                              ? Color(red: 1, green: 0.97, blue: 0.88)
                              : Color(UIColor.secondarySystemBackground))
                )
                .overlay {
                    if joke.isHit {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)

            // Open Mic
            Button {
                withAnimation { joke.isOpenMic.toggle(); joke.dateModified = Date() }
                haptic(.medium)
                do { try modelContext.save() } catch {
                    saveError = "Couldn't save: \(error.localizedDescription)"
                    showingSaveError = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: joke.isOpenMic ? "mic.fill" : "mic")
                        .font(.system(size: 11))
                    Text("Open Mic")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)

            // Folder
            Button {
                HapticEngine.shared.tap()
                showingFolderPicker = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(folderChipLabel)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - BIT Content

    private var bitContentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BIT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(UIColor.tertiaryLabel))
                .kerning(0.9)

            ZStack(alignment: .topLeading) {
                if joke.content.isEmpty {
                    Text("Start writing your bit\u{2026}")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(UIColor.placeholderText))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $joke.content)
                    .font(.system(size: 18, weight: .medium))
                    .lineSpacing(8)
                    .frame(minHeight: 200)
                    .focused($focusedField, equals: .content)
                    .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Downstage Tray

    private var downstageTray: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(EffortlessAnimation.smooth) {
                    showingNotes.toggle()
                }
                HapticEngine.shared.tap()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.systemBackground))
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.90, green: 0.64, blue: 0))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notes & alternate punches")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0))
                        Text(notesSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.54, green: 0.45, blue: 0.25))
                    }

                    Spacer()

                    Image(systemName: showingNotes ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Color(red: 0.54, green: 0.45, blue: 0.25))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 0.92, green: 0.89, blue: 0.84), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showingNotes {
                ZStack(alignment: .topLeading) {
                    if joke.notes.isEmpty {
                        Text("Alt punches, setup variants, stage notes\u{2026}")
                            .font(.subheadline)
                            .foregroundStyle(Color(UIColor.placeholderText))
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
                        .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 0.92, green: 0.89, blue: 0.84), lineWidth: 1)
                )
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TAGS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)

                Rectangle()
                    .fill(Color(UIColor.separator))
                    .frame(height: 0.5)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(joke.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                            Button {
                                var current = joke.tags
                                current.removeAll { $0 == tag }
                                joke.tags = current
                                joke.dateModified = Date()
                                scheduleAutoSave()
                                haptic(.light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    }

                    if isAddingTag {
                        TextField("tag", text: $newTagText)
                            .font(.caption)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .newTag)
                            .frame(minWidth: 50, maxWidth: 120)
                            .onSubmit { commitNewTag() }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                    } else {
                        Button {
                            isAddingTag = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedField = .newTag
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                                Text("tag")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                    )
                                    .foregroundColor(Color(UIColor.tertiaryLabel))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Floating Action Bar

    private var actionBar: some View {
        HStack(spacing: 4) {
            actionButton(icon: "pencil", label: "Edit") {
                focusedField = .content
                haptic(.light)
            }

            actionButton(icon: "sparkles", label: "Punch up", tint: .purple) {
                haptic(.medium)
            }

            actionButton(icon: "mic", label: "Record") {
                haptic(.light)
            }

            actionButton(icon: "list.bullet", label: "Add to set") {
                showingSetListPicker = true
                haptic(.light)
            }

            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(width: 0.5, height: 24)
                .padding(.horizontal, 2)

            Menu {
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
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .accessibilityLabel("More options")
            }
        }
        .padding(8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
    }

    private func actionButton(
        icon: String,
        label: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(tint ?? .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if let tint {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tag Commit

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

    private func insertBold() {
        if joke.content.hasSuffix("\n") || joke.content.isEmpty {
            joke.content += "**bold**"
        } else {
            joke.content += " **bold**"
        }
        scheduleAutoSave()
    }

    private func insertItalic() {
        if joke.content.hasSuffix("\n") || joke.content.isEmpty {
            joke.content += "_italic_"
        } else {
            joke.content += " _italic_"
        }
        scheduleAutoSave()
    }

    private func insertBullet() {
        if joke.content.isEmpty {
            joke.content = "\u{2022} "
        } else if joke.content.hasSuffix("\n") {
            joke.content += "\u{2022} "
        } else {
            joke.content += "\n\u{2022} "
        }
        scheduleAutoSave()
    }

    private func insertDash() {
        joke.content += "\u{2014}"
        scheduleAutoSave()
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
            if focusedField != nil {
                Button("Done") {
                    focusedField = nil
                }
                .fontWeight(.semibold)
            }
        }

        ToolbarItem(placement: .keyboard) {
            HStack(spacing: 4) {
                if focusedField == .content {
                    keyboardButton(label: "B", bold: true) {
                        insertBold(); haptic(.light)
                    }
                    keyboardButton(label: "I", isItalic: true) {
                        insertItalic(); haptic(.light)
                    }
                    keyboardButton(label: "List") {
                        insertBullet(); haptic(.light)
                    }
                    keyboardButton(label: "Dash") {
                        insertDash(); haptic(.light)
                    }

                    Divider()
                        .frame(height: 22)
                        .padding(.horizontal, 4)

                    keyboardButton(label: "BitBuddy", tint: .purple, bold: true) {
                        haptic(.medium)
                    }
                    keyboardButton(label: "Mic") {
                        haptic(.light)
                    }
                }

                Spacer()

                Button("Done") {
                    focusedField = nil
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func keyboardButton(
        label: String,
        isItalic: Bool = false,
        tint: Color? = nil,
        bold: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isItalic {
                    Text(label).italic()
                } else {
                    Text(label)
                }
            }
            .font(.system(size: 16, weight: bold ? .bold : .medium))
            .foregroundColor(tint ?? .primary)
            .frame(minWidth: 34, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(UIColor.systemBackground).opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
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
