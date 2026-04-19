//
//  BrainstormDetailView.swift
//  thebitbinder
//
//  Craft your brainstorm thought into a joke.
//  Always-editable canvas — just tap and start writing.
//  Includes a Notes scratchpad for related ideas.
//  Auto-save keeps your work safe.
//

import SwiftUI
import SwiftData

struct BrainstormDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    @Query(filter: #Predicate<JokeFolder> { !$0.isTrashed }, sort: \JokeFolder.name) private var folders: [JokeFolder]

    @Bindable var idea: BrainstormIdea
    @State private var showingDeleteAlert = false
    @State private var showingMetadata = false
    @State private var showingNotes = true
    @State private var showPromoteOptions = false

    // Auto-save
    @StateObject private var autoSave = AutoSaveManager.shared
    @State private var saveError: String?
    @State private var showingSaveError = false

    // Promoted toast
    @State private var showPromotedToast = false
    @State private var showColorPicker = false
    
    // BitBuddy floating chat
    @State private var showBitBuddyChat = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case content, notes
    }

    private var accentColor: Color {
        Color.accentColor
    }

    private var wordCount: Int {
        idea.content.split(separator: " ").count
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Header (title + badges)
                headerSection

                // MARK: - Content Workspace (always editable)
                contentSection

                // MARK: - Notes (scratchpad)
                notesSection
                    .padding(.top, 12)

                // MARK: - Color Picker
                colorPickerSection
                    .padding(.top, 12)

                // MARK: - Promote to Joke
                promoteSection
                    .padding(.top, 16)

                // MARK: - Metadata (collapsible)
                actionsBar
                    .padding(.top, 8)

                if showingMetadata {
                    metadataSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(UIColor.systemBackground))
        
            // Floating BitBuddy button — bottom-right corner
            Button {
                haptic(.light)
                showBitBuddyChat = true
            } label: {
                BitBuddyAvatar(roastMode: roastMode, size: 44, symbolSize: 18)
                    .background(
                        Circle()
                            .fill(Color(UIColor.systemBackground))
                            .frame(width: 50, height: 50)
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    )
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .bitBinderToolbar(roastMode: roastMode)
        .toolbar { toolbarContent }
        .tint(accentColor)
        .successToast(message: "Promoted to Jokes", icon: "arrow.up.doc.fill", isPresented: $showPromotedToast, roastMode: roastMode)
        .alert("Move to Trash", isPresented: $showingDeleteAlert) {
            Button("Move to Trash", role: .destructive) {
                idea.moveToTrash()
                do {
                    try modelContext.save()
                } catch {
                    print(" [BrainstormDetailView] Failed to trash idea: \(error)")
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure? You can restore it from Trash later.")
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your changes might not be saved. Try editing again.")
        }
        .sheet(isPresented: $showBitBuddyChat) {
            NavigationStack {
                BitBuddyChatView()
            }
        }
        .confirmationDialog("Add to Folder", isPresented: $showPromoteOptions, titleVisibility: .visible) {
            ForEach(folders) { folder in
                Button(folder.name) {
                    promoteToJoke(folder: folder)
                }
            }
            Button("No Folder") {
                promoteToJoke(folder: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a folder for this joke, or add it without one.")
        }
        .onChange(of: idea.content) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: idea.notes) { _, _ in
            scheduleAutoSave()
        }
        .onAppear {
            // Auto-focus so you can start typing right away
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if idea.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    focusedField = .content
                }
            }
        }
        .onDisappear {
            saveIdeaNow()
        }
    }

    // MARK: - Auto-Save

    private func scheduleAutoSave() {
        autoSave.scheduleSave { [self] in
            do {
                try modelContext.save()
            } catch {
                print(" [BrainstormDetailView] Auto-save failed: \(error)")
                saveError = "Your changes couldn't be saved: \(error.localizedDescription)"
                showingSaveError = true
            }
        }
    }

    private func saveIdeaNow() {
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormDetailView] Save failed: \(error)")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(KeywordTitleGenerator.displayTitle(from: idea.content))
                    .font(.title2.bold())
                    .foregroundColor(.primary)

                Spacer()

                // Voice badge
                if idea.isVoiceNote {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text("Voice")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(accentColor.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.12))
                    )
                }
            }

            // Word count + auto-save status
            HStack(spacing: 12) {
                if wordCount > 0 {
                    Text("\(wordCount) words")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                SaveStatusIndicator(roastMode: roastMode)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Content Section (always editable)

    private var contentSection: some View {
        ZStack(alignment: .topLeading) {
            if idea.content.isEmpty {
                Text("Start writing your thought…")
                    .font(.body)
                    .foregroundColor(Color(UIColor.placeholderText))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $idea.content)
                .scrollContentBackground(.hidden)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(6)
                .frame(minHeight: 260)
                .focused($focusedField, equals: .content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    // MARK: - Notes Section (collapsible scratchpad)

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(EffortlessAnimation.smooth) {
                    showingNotes.toggle()
                }
                HapticEngine.shared.tap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundColor(accentColor)

                    Text("Notes")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    if !idea.notes.isEmpty && !showingNotes {
                        Circle()
                            .fill(accentColor)
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
                    if idea.notes.isEmpty {
                        Text("Related ideas, angles, connections…")
                            .font(.subheadline)
                            .foregroundColor(Color(UIColor.placeholderText))
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $idea.notes)
                        .font(.subheadline)
                        .lineSpacing(5)
                        .frame(minHeight: 80)
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

    // MARK: - Color Picker

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(EffortlessAnimation.smooth) {
                    showColorPicker.toggle()
                }
                HapticEngine.shared.tap()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: idea.colorHex) ?? .gray)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )

                    Text("Note Color")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: showColorPicker ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showColorPicker {
                HStack(spacing: 10) {
                    ForEach(BrainstormIdea.noteColors, id: \.self) { colorHex in
                        Button {
                            idea.colorHex = colorHex
                            scheduleAutoSave()
                            haptic(.light)
                        } label: {
                            Circle()
                                .fill(Color(hex: colorHex) ?? .gray)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(idea.colorHex == colorHex ? Color.bitbinderAccent : Color.clear, lineWidth: 2)
                                )
                        }
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Promote Section

    private var promoteSection: some View {
        Button {
            HapticEngine.shared.press()
            showPromoteOptions = true
        } label: {
            Label("Promote to Joke", systemImage: "arrow.up.doc.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.bitbinderAccent)
        .controlSize(.large)
        .disabled(idea.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Actions Bar

    private var actionsBar: some View {
        HStack(spacing: 12) {
            Spacer()

            // Show/hide metadata
            Button {
                withAnimation(EffortlessAnimation.smooth) {
                    showingMetadata.toggle()
                }
                HapticEngine.shared.tap()
            } label: {
                Image(systemName: showingMetadata ? "chevron.up.circle.fill" : "info.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .symbolEffect(.bounce, value: showingMetadata)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.bottom, 8)

            Text("Details")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 12) {
                metadataRow(icon: "calendar", label: "Created", value: idea.dateCreated.formatted(date: .abbreviated, time: .shortened))

                if idea.isVoiceNote {
                    metadataRow(icon: "mic.fill", label: "Source", value: "Voice Note")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                HapticEngine.shared.warning()
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }

        ToolbarItem(placement: .keyboard) {
            HStack {
                // Jump between fields
                Button {
                    switch focusedField {
                    case .content:
                        focusedField = .notes
                        if !showingNotes {
                            withAnimation(EffortlessAnimation.smooth) {
                                showingNotes = true
                            }
                        }
                    case .notes:
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

    // MARK: - Promote to Joke

    private func promoteToJoke(folder: JokeFolder?) {
        let trimmed = idea.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let title = String(trimmed.prefix(60))
        let joke = Joke(content: trimmed, title: title, folder: folder)
        joke.importSource = "Brainstorm"
        // Carry over notes if the brainstorm had any
        if !idea.notes.isEmpty {
            joke.notes = idea.notes
        }

        modelContext.insert(joke)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(joke)
            print(" [BrainstormDetailView] Failed to save promoted joke: \(error)")
            saveError = "Could not promote to joke: \(error.localizedDescription)"
            showingSaveError = true
            return
        }

        // Trash the brainstorm idea now that the joke is saved
        idea.moveToTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormDetailView] Joke saved but failed to trash idea: \(error)")
        }

        HapticEngine.shared.success()
        showPromotedToast = true

        // Dismiss after a brief moment so the user sees the toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: BrainstormIdea.self, Joke.self, JokeFolder.self, configurations: config)
    } catch {
        fatalError("Preview ModelContainer failed: \(error)")
    }
    let idea = BrainstormIdea(content: "What if airlines charged by weight? Like, your carry-on is free but YOU cost extra. \"Sir, that's a 200-pound surcharge.\"", colorHex: "FFF9C4")
    return NavigationStack {
        BrainstormDetailView(idea: idea)
    }
    .modelContainer(container)
}