//
//  BrainstormDetailView.swift
//  thebitbinder
//
//  Craft your brainstorm thought into a joke.
//  Familiar writer-focused experience with auto-save.
//

import SwiftUI
import SwiftData

struct BrainstormDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    @Query(filter: #Predicate<JokeFolder> { !$0.isDeleted }, sort: \JokeFolder.name) private var folders: [JokeFolder]

    @Bindable var idea: BrainstormIdea
    @State private var isEditing = false
    @State private var showingDeleteAlert = false
    @State private var showingMetadata = false
    @State private var showPromoteOptions = false

    // Auto-save
    @StateObject private var autoSave = AutoSaveManager.shared
    @State private var showSavedToast = false
    @State private var saveError: String?
    @State private var showingSaveError = false

    // Promoted toast
    @State private var showPromotedToast = false

    private var accentColor: Color {
        roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brainstormAccent
    }

    private var wordCount: Int {
        idea.content.split(separator: " ").count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Title Section
                titleSection

                // MARK: - Content Workspace
                contentSection

                // MARK: - Promote to Joke
                promoteSection

                // MARK: - Actions Bar
                actionsBar

                // MARK: - Metadata (collapsible)
                if showingMetadata {
                    metadataSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
        .navigationBarTitleDisplayMode(.inline)
        .bitBinderToolbar(roastMode: roastMode)
        .toolbar { toolbarContent }
        .tint(accentColor)
        .successToast(message: "Changes saved", icon: "checkmark.circle.fill", isPresented: $showSavedToast, roastMode: roastMode)
        .successToast(message: "Promoted to Jokes", icon: "arrow.up.doc.fill", isPresented: $showPromotedToast, roastMode: roastMode)
        .alert(showingDeleteAlert ? "Move to Trash" : "", isPresented: $showingDeleteAlert) {
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

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(KeywordTitleGenerator.displayTitle(from: idea.content))
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)

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
                        .font(.system(size: 12))
                        .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                }

                Spacer()

                if isEditing {
                    SaveStatusIndicator(roastMode: roastMode)
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                TextEditor(text: $idea.content)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17, design: .serif))
                    .foregroundColor(roastMode ? .white.opacity(0.92) : AppTheme.Colors.inkBlack)
                    .lineSpacing(6)
                    .frame(minHeight: 250)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
            } else {
                Text(idea.content)
                    .font(.system(size: 17, design: .serif))
                    .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.textPrimary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(roastMode ? AppTheme.Colors.roastCard.opacity(0.5) : AppTheme.Colors.surfaceElevated.opacity(0.5))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(EffortlessAnimation.snappy) {
                            isEditing = true
                        }
                        HapticEngine.shared.tap()
                    }
                    .transition(.opacity)
            }
        }
        .animation(EffortlessAnimation.smooth, value: isEditing)
        .padding(.bottom, 16)
    }

    // MARK: - Promote Section

    private var promoteSection: some View {
        Button {
            HapticEngine.shared.press()
            showPromoteOptions = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Promote to Joke")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(roastMode ? AppTheme.Colors.roastEmberGradient : AppTheme.Colors.brandGradient)
            )
        }
        .buttonStyle(SmoothScaleButtonStyle(scale: 0.97))
        .disabled(idea.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .padding(.bottom, 16)
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
                    .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    .symbolEffect(.bounce, value: showingMetadata)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.bottom, 8)

            Text("Details")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
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
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 13))
                .foregroundColor(roastMode ? .white.opacity(0.6) : AppTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(roastMode ? .white : AppTheme.Colors.textPrimary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveIdeaNow()
                        HapticEngine.shared.success()
                        showSavedToast = true
                    } else {
                        HapticEngine.shared.tap()
                    }
                    withAnimation(EffortlessAnimation.snappy) {
                        isEditing.toggle()
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
                .foregroundColor(accentColor)

                Button {
                    HapticEngine.shared.warning()
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(AppTheme.Colors.error)
                }
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
