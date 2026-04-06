import SwiftUI
import PhotosUI
import SwiftData
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<NotebookPhotoRecord> { !$0.isDeleted }) private var photos: [NotebookPhotoRecord]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var showingDetail: NotebookPhotoRecord?
    @State private var showingImagePicker = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var showingTrash = false
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    @State private var showingPDFPicker = false
    @State private var isImportingPDF = false
    @State private var pdfImportProgress: String = ""
    
    private func delete(_ photo: NotebookPhotoRecord) {
        // Soft-delete: imageData kept until permanently purged from NotebookTrashView
        photo.moveToTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookView] Failed to save after photo soft-delete: \(error)")
            persistenceError = "Could not delete photo: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
    
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]
    
    var body: some View {
        Group {
            if photos.isEmpty {
                BitBinderEmptyState(
                    icon: "book.fill",
                    title: roastMode ? "No Fire Notebook Pages" : "No Pages Saved Yet",
                    subtitle: "Take photos of your physical notebook pages or import PDFs to back them up",
                    roastMode: roastMode,
                    iconGradient: LinearGradient(
                        colors: [AppTheme.Colors.notebookAccent, AppTheme.Colors.notebookAccent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(photos, id: \.id) { photo in
                            NotebookThumbnailCell(photo: photo) {
                                showingDetail = photo
                            } onDelete: {
                                delete(photo)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .overlay {
            if isImportingPDF {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text(pdfImportProgress)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    Button { showingTrash = true } label: {
                        Label("Trash", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.notebookAccent)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingPDFPicker = true } label: {
                        Label("Import PDF", systemImage: "doc.fill")
                    }
                } label: {
                    Label("Import PDF", systemImage: "doc.badge.plus")
                }
                
                PhotosPicker(selection: $pickedPhotoItem,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Label("Add Photo", systemImage: "photo.on.rectangle")
                }
                Button {
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            NotebookTrashView()
        }
        .onChange(of: pickedPhotoItem) { oldValue, newValue in
                Task {
                    if let item = newValue {
                        await importPhoto(from: item)
                        pickedPhotoItem = nil
                    }
                }
            }
        .sheet(isPresented: $showingCamera, onDismiss: {
            if let cameraImage {
                Task {
                    await saveCameraImage(cameraImage)
                }
                self.cameraImage = nil
            }
        }) {
            CameraView(image: $cameraImage)
        }
        .sheet(item: $showingDetail) { photo in
            NotebookDetailView(photo: photo)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $showingPDFPicker) {
            NotebookPDFPickerView { urls in
                if let url = urls.first {
                    Task {
                        await importPDF(from: url)
                    }
                }
            }
        }
        .onDisappear {
            // Memory cleanup handled by MemoryManager
        }
        .alert("Error", isPresented: $showingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }
    
    private func importPhoto(from item: PhotosPickerItem) async {
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self) else { return }

            // Downscale to max 1500 px long edge then compress.
            // rawData + UIImage + full-res jpegData can be 10–30 MB simultaneously;
            // the autoreleasepool frees them before we hit MainActor.
            guard let jpegData: Data = autoreleasepool(invoking: {
                guard let uiImage = UIImage(data: rawData) else { return nil }
                let scaled = NotebookView.downscaleForStorage(uiImage, maxLongEdge: 1500)
                return scaled.jpegData(compressionQuality: 0.8)
            }) else { return }

            let newPhoto = NotebookPhotoRecord(notes: "", imageData: jpegData)
            await MainActor.run {
                modelContext.insert(newPhoto)
                do {
                    try modelContext.save()
                } catch {
                    print(" [NotebookView] Failed to save imported photo: \(error)")
                    persistenceError = "Could not save photo: \(error.localizedDescription)"
                    showingPersistenceError = true
                }
            }
        } catch {
            print(" [NotebookView] importPhoto error: \(error)")
        }
    }
    
    private func saveCameraImage(_ image: UIImage) async {
        // Downscale then compress; releases intermediate buffers before saving.
        guard let jpegData: Data = autoreleasepool(invoking: {
            let scaled = NotebookView.downscaleForStorage(image, maxLongEdge: 1500)
            return scaled.jpegData(compressionQuality: 0.8)
        }) else { return }

        let newPhoto = NotebookPhotoRecord(notes: "", imageData: jpegData)
        await MainActor.run {
            modelContext.insert(newPhoto)
            do {
                try modelContext.save()
            } catch {
                print(" [NotebookView] Failed to save camera photo: \(error)")
                persistenceError = "Could not save photo: \(error.localizedDescription)"
                showingPersistenceError = true
            }
        }
    }

    /// Scales `image` so its longest edge is at most `maxLongEdge` pixels.
    /// Returns the original image unchanged if it is already small enough.
    static func downscaleForStorage(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - PDF Import
    
    private func importPDF(from url: URL) async {
        await MainActor.run {
            isImportingPDF = true
            pdfImportProgress = "Loading PDF..."
        }
        
        do {
            // Access security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            
            guard let document = PDFDocument(url: url) else {
                await MainActor.run {
                    isImportingPDF = false
                    persistenceError = "Could not open PDF file"
                    showingPersistenceError = true
                }
                return
            }
            
            let pageCount = document.pageCount
            let pdfName = url.deletingPathExtension().lastPathComponent
            
            for pageIndex in 0..<pageCount {
                await MainActor.run {
                    pdfImportProgress = "Importing page \(pageIndex + 1) of \(pageCount)..."
                }
                
                guard let page = document.page(at: pageIndex) else { continue }
                
                // Render PDF page to image
                guard let jpegData = await renderPDFPageToJPEG(page: page) else { continue }
                
                // Create NotebookPhotoRecord for this page
                let notes = pageCount > 1 
                    ? "\(pdfName) (Page \(pageIndex + 1) of \(pageCount))"
                    : pdfName
                
                let newPhoto = NotebookPhotoRecord(notes: notes, imageData: jpegData)
                
                await MainActor.run {
                    modelContext.insert(newPhoto)
                }
            }
            
            // Save all pages
            await MainActor.run {
                pdfImportProgress = "Saving..."
                do {
                    try modelContext.save()
                } catch {
                    print(" [NotebookView] Failed to save PDF pages: \(error)")
                    persistenceError = "Could not save PDF pages: \(error.localizedDescription)"
                    showingPersistenceError = true
                }
                isImportingPDF = false
            }
            
        } catch {
            await MainActor.run {
                isImportingPDF = false
                persistenceError = "PDF import failed: \(error.localizedDescription)"
                showingPersistenceError = true
            }
        }
    }
    
    private func renderPDFPageToJPEG(page: PDFPage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                let mediaBox = page.bounds(for: .mediaBox)
                
                // Calculate scale to fit within 1500px max dimension
                let maxDimension: CGFloat = 1500
                let scale = min(maxDimension / mediaBox.width, maxDimension / mediaBox.height, 2.0)
                let scaledSize = CGSize(width: mediaBox.width * scale, height: mediaBox.height * scale)
                
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                
                let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
                let image = renderer.image { ctx in
                    // Fill white background
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: scaledSize))
                    
                    // Apply scale transform
                    ctx.cgContext.scaleBy(x: scale, y: scale)
                    
                    // Draw PDF page
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                
                return image.jpegData(compressionQuality: 0.85)
            }
        }.value
    }
}

// MARK: - PDF Picker for Notebook

struct NotebookPDFPickerView: UIViewControllerRepresentable {
    let completion: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        
        init(completion: @escaping ([URL]) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion([])
        }
    }
}

struct NotebookDetailView: View {
    @Bindable var photo: NotebookPhotoRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    private func deleteCurrent() {
        // Soft-delete: imageData kept until permanently purged from NotebookTrashView
        photo.moveToTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [NotebookDetailView] Failed to save after photo soft-delete: \(error)")
        }
        dismiss()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Load image from stored imageData
                if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .padding()
                } else {
                    Color.gray
                        .frame(height: 200)
                        .cornerRadius(12)
                        .overlay(Text("Image not found").foregroundColor(.white))
                        .padding()
                }
                TextField("Notes", text: $photo.notes)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        deleteCurrent()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - CameraView (UIKit wrapped)

#if !targetEnvironment(macCatalyst)
struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView
        init(parent: CameraView) { self.parent = parent }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage { parent.image = uiImage }
            parent.dismiss()
        }
    }
}
#else
struct CameraView: View {
    @Binding var image: UIImage?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Camera is not available on Mac.\nUse the photo picker instead.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}
#endif

// MARK: - Notebook Thumbnail Cell
//
// Decodes the stored JPEG into a fixed 200×200 px thumbnail on a background
// thread, so the main thread and LazyVGrid are never blocked by image decode,
// and only ~120 KB per cell is held in memory (vs 3–8 MB for a full UIImage).

private struct NotebookThumbnailCell: View {
    let photo: NotebookPhotoRecord
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                    .overlay(ProgressView().tint(.secondary))
            }
        }
        .frame(minWidth: 100, minHeight: 100)
        .clipped()
        .cornerRadius(8)
        .onTapGesture { onTap() }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .task(id: photo.id) {
            await decodeThumbnail()
        }
    }

    private func decodeThumbnail() async {
        guard thumbnail == nil, let data = photo.imageData else { return }
        // Hop off the main actor — image decode is CPU-bound
        let decoded: UIImage? = await Task.detached(priority: .utility) {
            autoreleasepool {
                guard let full = UIImage(data: data) else { return nil }
                // Render at 200 px max long edge (sufficient for a grid thumbnail)
                let size = full.size
                let longEdge = max(size.width, size.height)
                guard longEdge > 200 else { return full }
                let scale = 200.0 / longEdge
                let newSize = CGSize(width: (size.width * scale).rounded(),
                                    height: (size.height * scale).rounded())
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = 1
                fmt.opaque = true
                return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
                    full.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }
        }.value
        thumbnail = decoded
    }
}