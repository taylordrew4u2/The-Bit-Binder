//
//  NotebookTrashView.swift
//  thebitbinder
//
//  Trash bin for soft-deleted notebook photos.
//  Restore puts the photo back in the active grid.
//  "Delete Forever" permanently removes the imageData from the store.
//

import SwiftUI
import SwiftData

struct NotebookTrashView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Query(
        filter: #Predicate<NotebookPhotoRecord> { $0.isTrashed == true },
        sort: \NotebookPhotoRecord.deletedDate,
        order: .reverse
    ) private var trashedPhotos: [NotebookPhotoRecord]

    @State private var showingEmptyTrashAlert = false
    @State private var photoToDelete: NotebookPhotoRecord?
    @State private var showingDeleteOneAlert = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false

    var body: some View {
        Group {
            if trashedPhotos.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Photo Trash is Empty",
                    subtitle: "Deleted notebook photos appear here for 30 days before being permanently removed.",
                    roastMode: roastMode
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(trashedPhotos, id: \.id) { photo in
                            ZStack(alignment: .bottomTrailing) {
                                AsyncThumbnailView(imageData: photo.imageData, size: 100, opacity: 0.65)
                                    .cornerRadius(8)
                            }
                            .contextMenu {
                                Button {
                                    restorePhoto(photo)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }

                                Button(role: .destructive) {
                                    photoToDelete = photo
                                    showingDeleteOneAlert = true
                                } label: {
                                    Label("Delete Forever", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !trashedPhotos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingEmptyTrashAlert = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                }
            }
        }
        .alert("Delete Forever?", isPresented: $showingDeleteOneAlert) {
            Button("Cancel", role: .cancel) { photoToDelete = nil }
            Button("Delete", role: .destructive) {
                if let photo = photoToDelete {
                    permanentlyDelete(photo)
                    photoToDelete = nil
                }
            }
        } message: {
            Text("This photo will be permanently deleted. This cannot be undone.")
        }
        .alert("Empty Photo Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This permanently deletes all \(trashedPhotos.count) photo\(trashedPhotos.count == 1 ? "" : "s") and their image data. This cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }

    // MARK: - Actions

    private func restorePhoto(_ photo: NotebookPhotoRecord) {
        photo.restoreFromTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookTrashView] Failed to restore: \(error)")
            persistenceError = "Could not restore photo: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func permanentlyDelete(_ photo: NotebookPhotoRecord) {
        modelContext.delete(photo)
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookTrashView] Failed to delete: \(error)")
            persistenceError = "Could not delete photo: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func emptyTrash() {
        for photo in trashedPhotos {
            modelContext.delete(photo)
        }
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookTrashView] Failed to empty trash: \(error)")
            persistenceError = "Could not empty trash: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        NotebookTrashView()
    }
    .modelContainer(for: NotebookPhotoRecord.self, inMemory: true)
}
