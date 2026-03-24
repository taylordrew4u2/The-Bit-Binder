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
    @AppStorage("expandAllJokes") private var expandAllJokes = false
    @Bindable var target: RoastTarget

    @State private var showingAddRoast = false
    @State private var editingJoke: RoastJoke?
    @State private var showingEditTarget = false
    @State private var showingTalkToText = false
    @State private var showingRecordingSheet = false
    @State private var showingDeleteTargetAlert = false
    @State private var searchText = ""

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
                // Avatar — async background decode, no main-thread stall
                AsyncAvatarView(
                    photoData: target.photoData,
                    size: 80,
                    fallbackInitial: String(target.name.prefix(1).uppercased()),
                    accentColor: accentColor
                )
                .overlay(Circle().stroke(accentColor, lineWidth: target.photoData != nil ? 3 : 0))

                Text(target.name)
                    .font(.title2.bold())

                if !target.notes.isEmpty {
                    Text(target.notes)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
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
        .navigationTitle(target.name)
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
                    Button(action: { expandAllJokes.toggle() }) {
                        Label(expandAllJokes ? "Collapse Roasts" : "Expand Roasts", systemImage: expandAllJokes ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
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
                    NavigationLink(destination: RoastJokeTrashView(target: target)) {
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
                modelContext.delete(target)
                do {
                    try modelContext.save()
                } catch {
                    #if DEBUG
                    print("❌ [RoastTargetDetailView] Failed to persist delete: \(error)")
                    #endif
                }
                dismiss()
            }
        } message: {
            Text("This will permanently delete \(target.name) and all \(target.jokeCount) roast\(target.jokeCount == 1 ? "" : "s"). This cannot be undone.")
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
            #if DEBUG
            print("❌ [RoastTargetDetailView] Failed to persist roast soft-delete: \(error)")
            #endif
        }
    }
}

// MARK: - Roast Joke Row

struct RoastJokeRow: View {
    let joke: RoastJoke
    @AppStorage("expandAllJokes") private var expandAllJokes = false
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
                Text(joke.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineLimit(expandAllJokes ? nil : 3)
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
            .navigationTitle("Edit Roast")
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
                            print("❌ [EditRoastJokeView] Failed to save: \(error)")
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
            }
            .navigationTitle("Edit \(target.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // target.photoData is already written in the onChange handler
                        // (downscaled + compressed). Re-encoding the display UIImage
                        // here would double-compress and waste memory; skip it.
                        target.dateModified = Date()
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            #if DEBUG
                            print("❌ [EditRoastTargetView] Failed to save: \(error)")
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
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    guard let rawData = try? await newValue?.loadTransferable(type: Data.self) else { return }
                    // Downscale to 1500 px max long edge and compress before storing.
                    // Raw Photos library data can be 5–15 MB; we must not store or
                    // decode it at full resolution.
                    let (storedData, displayImage): (Data?, UIImage?) = await Task.detached(priority: .utility) {
                        autoreleasepool {
                            guard let full    = UIImage(data: rawData) else { return (nil, nil) }
                            let scaled        = RoastTargetPhotoHelper.downscale(full, maxLongEdge: 1500)
                            let jpeg          = scaled.jpegData(compressionQuality: 0.8)
                            // Decode a small display thumbnail (400 px) for the edit view
                            let thumb         = RoastTargetPhotoHelper.downscale(full, maxLongEdge: 400)
                            return (jpeg, thumb)
                        }
                    }.value
                    await MainActor.run {
                        if let storedData { target.photoData = storedData }
                        photoImage = displayImage
                    }
                }
            }
            .task {
                // Decode display thumbnail asynchronously so we never block the main thread
                guard photoImage == nil, let stored = target.photoData else { return }
                let thumb: UIImage? = await Task.detached(priority: .utility) {
                    autoreleasepool {
                        guard let full = UIImage(data: stored) else { return nil }
                        return RoastTargetPhotoHelper.downscale(full, maxLongEdge: 400)
                    }
                }.value
                photoImage = thumb
            }
        }
    }
}
