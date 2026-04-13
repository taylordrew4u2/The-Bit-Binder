//
//  JokesViewModifiers.swift
//  thebitbinder
//
//  Extracted sheet & alert modifiers from JokesView to reduce
//  body complexity and avoid compiler type-check timeouts.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Consolidated Sheet Enum

/// All sheets presented from JokesView, consolidated into a single enum
/// to avoid the SwiftUI multi-.sheet(isPresented:) presentation bug.
enum JokesSheet: String, Identifiable {
    case addJoke
    case scanner
    case createFolder
    case organizeOptions
    case autoOrganize
    case audioImport
    case talkToText
    case filePicker
    case addRoastTarget
    case moveJokes
    case reviewSheet
    case importHistory
    var id: String { rawValue }
}

// MARK: - Sheets Modifier

struct JokesSheetsModifier: ViewModifier {
    @Binding var activeSheet: JokesSheet?

    let selectedFolder: JokeFolder?
    let folders: [JokeFolder]
    @Binding var folderPendingDeletion: JokeFolder?
    let reviewCandidates: [JokeImportCandidate]
    let possibleDuplicates: [String]
    let unresolvedFragments: [UnresolvedImportFragment]
    let processScannedImages: ([UIImage]) -> Void
    let processDocuments: ([URL]) -> Void
    let moveJokes: (JokeFolder, JokeFolder?) -> Void
    let deleteFolder: (JokeFolder) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addJoke:
                    AddJokeView(selectedFolder: selectedFolder)
                case .scanner:
                    DocumentScannerView { images in
                        processScannedImages(images)
                    }
                case .createFolder:
                    CreateFolderView()
                case .organizeOptions:
                    OrganizeOptionsView()
                case .audioImport:
                    AudioImportView(selectedFolder: selectedFolder)
                case .talkToText:
                    TalkToTextView(selectedFolder: selectedFolder)
                case .filePicker:
                    DocumentPickerView { urls in
                        processDocuments(urls)
                    }
                case .addRoastTarget:
                    AddRoastTargetView()
                case .moveJokes:
                    MoveJokesSheet(
                        folders: folders,
                        folderPendingDeletion: $folderPendingDeletion,
                        moveJokes: moveJokes,
                        deleteFolder: deleteFolder
                    )
                case .reviewSheet:
                    ReviewImportsSheet(
                        reviewCandidates: reviewCandidates,
                        possibleDuplicates: possibleDuplicates,
                        unresolvedFragments: unresolvedFragments,
                        selectedFolder: selectedFolder
                    )
                case .importHistory:
                    ImportBatchHistoryView()
                }
            }
    }
}

// MARK: - Alerts Modifier

struct OrganizeOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showAutoOrganize = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showAutoOrganize = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-Organize Jokes")
                                    .font(.headline)
                                Text("AI-powered categorization and folder management")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Smart Organization")
                } footer: {
                    Text("Let BitBuddy analyze your jokes and automatically organize them into categories.")
                }
                
                // You can add more organization options here in the future
                // For example:
                // - Manual organization
                // - Folder management
                // - Tag management
                // etc.
            }
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAutoOrganize) {
                AutoOrganizeView()
            }
        }
    }
}

// MARK: - Alerts Modifier

struct JokesAlertsModifier: ViewModifier {
    @Binding var showingExportAlert: Bool
    @Binding var showingImportSummary: Bool
    @Binding var showingDeleteFolderAlert: Bool
    @Binding var showingDeleteRoastAlert: Bool
    @Binding var activeSheet: JokesSheet?

    let exportedPDFURL: URL?
    let importSummary: (added: Int, skipped: Int)
    @Binding var folderPendingDeletion: JokeFolder?
    @Binding var roastTargetToDelete: RoastTarget?
    let jokes: [Joke]
    let shareFile: (URL) -> Void
    let removeJokesFromFolderAndDelete: (JokeFolder) -> Void
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .alert("PDF Exported", isPresented: $showingExportAlert) {
                if let url = exportedPDFURL {
                    Button("Share") { shareFile(url) }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your jokes have been exported to a PDF file.")
            }
            .alert(
                importSummary.added > 0 ? "Import Complete! " : "No Jokes Found",
                isPresented: $showingImportSummary
            ) {
                Button("OK") {}
            } message: {
                if importSummary.added > 0 {
                    Text("Imported \(importSummary.added) joke\(importSummary.added == 1 ? "" : "s")\(importSummary.skipped > 0 ? " and skipped \(importSummary.skipped) duplicate\(importSummary.skipped == 1 ? "" : "s")" : ""). Check them out in your collection!")
                } else {
                    Text("GagGrabber couldn't find any jokes in this file. Try a PDF with selectable text, or make sure jokes are separated by line breaks.")
                }
            }
            .alert("Delete Folder?", isPresented: $showingDeleteFolderAlert) {
                Button("Move Jokes…") {
                    activeSheet = .moveJokes
                }
                Button("Remove From Folder", role: .destructive) {
                    if let folder = folderPendingDeletion {
                        removeJokesFromFolderAndDelete(folder)
                    }
                }
                Button("Cancel", role: .cancel) {
                    folderPendingDeletion = nil
                }
            } message: {
                let count = folderPendingDeletion.map { f in jokes.filter { $0.folder?.id == f.id }.count } ?? 0
                Text("This will delete the folder '\(folderPendingDeletion?.name ?? "")'. You can move its \(count) jokes to another folder, or remove them from any folder.")
            }
            .alert("Delete Roast Target?", isPresented: $showingDeleteRoastAlert) {
                Button("Delete", role: .destructive) {
                    if let target = roastTargetToDelete {
                        modelContext.delete(target)
                        do {
                            try modelContext.save()
                        } catch {
                            print(" [JokesViewModifiers] Failed to delete roast target: \(error)")
                        }
                        roastTargetToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    roastTargetToDelete = nil
                }
            } message: {
                Text("This will delete \(roastTargetToDelete?.name ?? "") and all their roast jokes permanently.")
            }
    }
}

// MARK: - Move Jokes Sheet (extracted)

struct MoveJokesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let folders: [JokeFolder]
    @Binding var folderPendingDeletion: JokeFolder?
    let moveJokes: (JokeFolder, JokeFolder?) -> Void
    let deleteFolder: (JokeFolder) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button(action: {
                    if let folder = folderPendingDeletion {
                        moveJokes(folder, nil)
                        deleteFolder(folder)
                    }
                    dismiss()
                    folderPendingDeletion = nil
                }) {
                    Label("Move to No Folder", systemImage: "tray")
                }
                ForEach(folders) { dest in
                    if dest.id != folderPendingDeletion?.id {
                        Button(action: {
                            if let source = folderPendingDeletion {
                                moveJokes(source, dest)
                                deleteFolder(source)
                            }
                            dismiss()
                            folderPendingDeletion = nil
                        }) {
                            Label(dest.name, systemImage: "folder")
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// NOTE: ImportProgressCard has been moved to JokeComponents.swift

// MARK: - Review Imports Sheet (extracted)

struct ReviewImportsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let reviewCandidates: [JokeImportCandidate]
    let possibleDuplicates: [String]
    let unresolvedFragments: [UnresolvedImportFragment]
    let selectedFolder: JokeFolder?
    
    private var openFragments: [UnresolvedImportFragment] {
        unresolvedFragments.filter { !$0.isResolved }
    }
    
    private var hasContent: Bool {
        !possibleDuplicates.isEmpty || !openFragments.isEmpty || !reviewCandidates.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasContent {
                    List {
                        // Summary header
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "tray.full.fill")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(openFragments.count + reviewCandidates.count) item\(openFragments.count + reviewCandidates.count == 1 ? "" : "s") to review")
                                        .font(.headline)
                                    if !possibleDuplicates.isEmpty {
                                        Text("\(possibleDuplicates.count) possible duplicate\(possibleDuplicates.count == 1 ? "" : "s") detected")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                Spacer()
                            }
                        }
                        
                        if !possibleDuplicates.isEmpty {
                            Section {
                                ForEach(possibleDuplicates, id: \.self) { dup in
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.subheadline)
                                            .foregroundColor(.accentColor)
                                        Text(dup)
                                            .font(.subheadline)
                                    }
                                }
                            } header: {
                                Label("Possible Duplicates", systemImage: "doc.on.doc")
                            }
                        }
                        if !openFragments.isEmpty {
                            Section {
                                ForEach(openFragments) { fragment in
                                    UnresolvedFragmentRow(
                                        fragment: fragment,
                                        selectedFolder: selectedFolder,
                                        onSaveAsJoke: { saveFragmentAsJoke($0) },
                                        onMarkResolved: { markResolved($0) }
                                    )
                                }
                            } header: {
                                Label("Unresolved Fragments", systemImage: "puzzle.piece")
                            } footer: {
                                Text("These text fragments were extracted but need your review. Save them as jokes or mark them resolved to dismiss.")
                                    .font(.caption)
                            }
                        }
                        if !reviewCandidates.isEmpty {
                            Section {
                                ForEach(Array(reviewCandidates.enumerated()), id: \.element.id) { _, cand in
                                    VStack(alignment: .leading, spacing: 8) {
                                        TextField("Title", text: .constant(cand.suggestedTitle))
                                            .textFieldStyle(.roundedBorder)
                                        Text(cand.content)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } header: {
                                Label("Needs Review", systemImage: "eye")
                            }
                        }
                    }
                } else {
                    // Empty state
                    ContentUnavailableView {
                        Label("All Caught Up!", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text("No unresolved fragments or items needing review. Everything from your imports has been handled.")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func saveFragmentAsJoke(_ fragment: UnresolvedImportFragment) {
        let title: String
        if let candidate = fragment.titleCandidate?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            title = candidate
        } else {
            title = String(fragment.text.prefix(40))
        }
        let joke = Joke(content: fragment.text, title: title, folder: selectedFolder)
        joke.tags = fragment.tags
        modelContext.insert(joke)
        fragment.isResolved = true
        do {
            try modelContext.save()
        } catch {
            print(" [JokesViewModifiers] Failed to save fragment as joke: \(error)")
        }
    }
    
    private func markResolved(_ fragment: UnresolvedImportFragment) {
        fragment.isResolved = true
        do {
            try modelContext.save()
        } catch {
            print(" [JokesViewModifiers] Failed to save resolved state: \(error)")
        }
    }
}

struct UnresolvedFragmentRow: View {
    let fragment: UnresolvedImportFragment
    let selectedFolder: JokeFolder?
    let onSaveAsJoke: (UnresolvedImportFragment) -> Void
    let onMarkResolved: (UnresolvedImportFragment) -> Void
    
    private var confidenceColor: Color {
        switch fragment.confidence.lowercased() {
        case "high": return .accentColor
        case "medium": return .accentColor
        default: return .accentColor
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: title + confidence
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fragment.titleCandidate ?? "Recovered Fragment")
                        .font(.headline)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Label(fragment.kind.capitalized, systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let page = fragment.sourcePage {
                            Label("Page \(page)", systemImage: "doc.text")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Confidence pill
                Text(fragment.confidence.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(confidenceColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(confidenceColor.opacity(0.12))
                    )
            }
            
            // Fragment text
            Text(fragment.text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemBackground))
                )
            
            // Source info
            Text(fragment.sourceFilename)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            
            // Action buttons
            HStack(spacing: 10) {
                Button {
                    onSaveAsJoke(fragment)
                } label: {
                    Label("Save as Joke", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button {
                    onMarkResolved(fragment)
                } label: {
                    Label("Dismiss", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}
