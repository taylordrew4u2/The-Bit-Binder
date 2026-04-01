//
//  RoastTargetDetailView.swift
//  thebitbinder
//
//  Shows a roast target's profile and all roast jokes for them.
//  Users can add, edit, and delete roast jokes here.
//

import SwiftUI
import SwiftData
import PhotosUI

struct RoastTargetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showFullContent") private var showFullContent = true
    @Bindable var target: RoastTarget

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

    private let accentColor = AppTheme.Colors.roastAccent

    var filteredJokes: [RoastJoke] {
        let sorted = target.sortedJokes
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return sorted }
        return sorted.filter {
            $0.content.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Target Header Card
            VStack(spacing: 12) {
                // Avatar — async background decode
                AsyncAvatarView(
                    photoData: target.photoData,
                    size: 80,
                    fallbackInitial: String(target.name.prefix(1).uppercased()),
                    accentColor: accentColor
                )
                .overlay(Circle().stroke(accentColor, lineWidth: 3))

                Text(target.name)
                    .font(.title2.bold())

                if !target.notes.isEmpty {
                    Text(target.notes)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !target.traits.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(target.traits, id: \.self) { trait in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(accentColor)
                                Text(trait)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }

                Text("\(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(accentColor)
                    .clipShape(Capsule())
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [accentColor.opacity(0.08), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Divider()

            // Roast Jokes List
            if filteredJokes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "flame")
                        .font(.system(size: 44))
                        .foregroundColor(accentColor.opacity(0.4))
                    Text("No roasts yet")
                        .font(.headline)
                    Text("Tap + to write your first roast for \(target.name)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredJokes) { joke in
                        Button {
                            editingJoke = joke
                        } label: {
                            RoastJokeRow(joke: joke)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteRoasts)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search roasts")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingEditTarget = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showFullContent.toggle() }) {
                        Label(showFullContent ? "Show Titles Only" : "Show Full Content", systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                    }
                    Divider()
                    Button(action: { showingAddRoast = true }) {
                        Label("Add Manually", systemImage: "square.and.pencil")
                    }
                    Button(action: { showingTalkToText = true }) {
                        Label("Talk-to-Text", systemImage: "mic.badge.plus")
                    }
                    Divider()
                    Button(action: { showingRecordingSheet = true }) {
                        Label("Record Set", systemImage: "record.circle")
                    }
                    Divider()
                    Button { showingRoastTrash = true } label: {
                        Label("Roast Trash", systemImage: "trash")
                    }
                    Divider()
                    Button(role: .destructive, action: { showingDeleteTargetAlert = true }) {
                        Label("Delete Target", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Delete \(target.name)?", isPresented: $showingDeleteTargetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                target.moveToTrash()
                do {
                    try modelContext.save()
                    dismiss()
                } catch {
                    print(" [RoastTargetDetailView] Failed to persist delete: \(error)")
                    persistenceError = "Could not delete \(target.name): \(error.localizedDescription)"
                    showingPersistenceError = true
                }
            }
        } message: {
            Text("This will permanently delete \(target.name) and all \(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s"). This cannot be undone.")
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
        .navigationDestination(isPresented: $showingRoastTrash) {
            RoastJokeTrashView(target: target)
        }
    }

    private func deleteRoasts(at offsets: IndexSet) {
        let jokes = filteredJokes
        for index in offsets {
            guard index < jokes.count else { continue }
            jokes[index].moveToTrash()
        }
        do {
            try modelContext.save()
        } catch {
            print(" [RoastTargetDetailView] Failed to persist roast soft-delete: \(error)")
            persistenceError = "Could not move roast to trash: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
}

// MARK: - Roast Joke Row

struct RoastJokeRow: View {
    let joke: RoastJoke
    @AppStorage("showFullContent") private var showFullContent = true
    private let accentColor = AppTheme.Colors.roastAccent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                if showFullContent {
                    Text(joke.content)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                } else {
                    Text(joke.content.components(separatedBy: .newlines).first ?? joke.content)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text(joke.dateCreated, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Edit Roast Joke Sheet

struct EditRoastJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var joke: RoastJoke
    
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Roast") {
                    TextEditor(text: $joke.content)
                        .frame(minHeight: 150)
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
                        joke.dateModified = Date()
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            #if DEBUG
                            print(" [EditRoastJokeView] Failed to save: \(error)")
                            #endif
                            saveErrorMessage = "Could not save changes: \(error.localizedDescription)"
                            showSaveError = true
                        }
                    }
                    .disabled(joke.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
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

    private let accentColor = AppTheme.Colors.roastAccent

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(accentColor, lineWidth: 3))
                            } else if let photoData = target.photoData,
                                      let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(accentColor, lineWidth: 3))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(accentColor.opacity(0.12))
                                        .frame(width: 100, height: 100)
                                    VStack(spacing: 4) {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                            .font(.system(size: 32))
                                            .foregroundColor(accentColor)
                                        Text("Add Photo")
                                            .font(.caption2)
                                            .foregroundColor(accentColor)
                                    }
                                }
                            }
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
                    ForEach(target.traits.indices, id: \.self) { index in
                        HStack {
                            TextField("e.g. works in finance, always late...", text: $target.traits[index])
                            if target.traits.count > 1 {
                                Button {
                                    target.traits.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
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
