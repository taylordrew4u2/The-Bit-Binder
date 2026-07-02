//
//  LegacyPhotoNotebookView.swift
//  thebitbinder
//
//  Read-only viewer + exporter for the old Photo Notebook. The photo notebook
//  was replaced by the text-based line notebook (see LineNotebookView), but
//  existing photo data is preserved and reachable here from Settings so users
//  can view and export the files they uploaded before deleting anything.
//

import SwiftUI
import SwiftData

struct LegacyPhotoNotebookView: View {
    @Query(filter: #Predicate<NotebookPhotoRecord> { !$0.isTrashed },
           sort: \NotebookPhotoRecord.sortOrder)
    private var photos: [NotebookPhotoRecord]

    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?
    @State private var previewPhoto: NotebookPhotoRecord?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle",
                    description: Text("Your old photo notebook is empty. Nothing to export.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(photos) { photo in
                            Button {
                                previewPhoto = photo
                            } label: {
                                LegacyPhotoThumbnail(photo: photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .readableWidth(DS.wideContentWidth)
                .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle("Photo Notebook (Legacy)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        export { PDFExportService.exportNotebookPhotosToPDF(photos) }
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        export { PDFExportService.exportNotebookPhotosZip(photos) }
                    } label: {
                        Label("Export originals (.zip)", systemImage: "photo.stack")
                    }
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(photos.isEmpty || isExporting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !photos.isEmpty {
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") — export to save them, then text or AirDrop the file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
        .sheet(item: $previewPhoto) { photo in
            LegacyPhotoPreview(photo: photo)
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    /// Runs a file-producing export off the main thread, then presents the share sheet.
    private func export(_ make: @escaping () -> URL?) {
        isExporting = true
        Task.detached(priority: .userInitiated) {
            let url = make()
            await MainActor.run {
                isExporting = false
                if let url {
                    exportURL = url
                    showShareSheet = true
                } else {
                    exportError = "Could not create the export file. Please try again."
                }
            }
        }
    }
}

// MARK: - Thumbnail

private struct LegacyPhotoThumbnail: View {
    let photo: NotebookPhotoRecord
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
        .task(id: photo.id) {
            guard image == nil, let data = photo.imageData else { return }
            let decoded = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            image = decoded
        }
    }
}

// MARK: - Full preview

private struct LegacyPhotoPreview: View {
    let photo: NotebookPhotoRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    if let data = photo.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                    let notes = photo.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.lg)
                    }
                }
                .padding(.vertical, DS.Spacing.md)
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
