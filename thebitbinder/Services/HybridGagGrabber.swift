//
//  HybridGagGrabber.swift
//  thebitbinder
//
//  GagGrabber — offline joke extractor.
//  Runs the on-device providers via AIJokeExtractionManager:
//    1. Apple Foundation Model (iOS 26+) — understands the detailed per-entry
//       questions about joke text, confidence, humor mechanism, and title.
//    2. NLEmbedding sentence segmenter — fallback on older devices.
//
//  UI: `HybridGagGrabberSheet` — a toolbar-button-triggered sheet that lets
//  the user pick a .txt, .pdf, .rtf, .csv, or .html file, extract jokes, and
//  add them one-by-one to their library via the Joke SwiftData model.
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// MARK: - HybridGagGrabber (ObservableObject)

@MainActor
final class HybridGagGrabber: ObservableObject {

    // MARK: Published State

    @Published var extractedJokes: [String] = []
    @Published var isExtracting: Bool = false
    @Published var lastError: String?

    /// Structured hints the user supplies before extraction. Drives both
    /// preprocessing (stripping stage directions / timestamps / etc.) and the
    /// instructions the on-device model receives with the document.
    @Published var hints: ExtractionHints = .loadLastUsed()

    @Published var statusMessage: String = ""
    @Published var elapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?

    // MARK: - Main Extraction Entry Point

    /// Extract jokes from `rawText` on-device. If no on-device provider is
    /// available, surfaces a clear error.
    func extractJokes(from rawText: String) async {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Document is empty — nothing to extract."
            return
        }

        isExtracting = true
        lastError = nil
        extractedJokes = []
        statusMessage = "Reading your document…"
        startElapsedTimer()

        print(" [GagGrabber] Text length: \(rawText.count) chars")

        // Apply any user-selected ignore filters before the text reaches the
        // model. Safe unconditionally — a no-op when no toggles are on.
        let preprocessed = hints.preprocess(rawText)
        if preprocessed.count != rawText.count {
            print(" [GagGrabber] Preprocessing trimmed \(rawText.count - preprocessed.count) chars")
        }

        // Prepend a natural-language summary of the hints so the on-device
        // provider knows how the document is structured. No-op when hints
        // are unspecified.
        let textToSend = hints.applyingPromptPrefix(to: preprocessed)

        let manager = AIJokeExtractionManager.shared
        let token = AIExtractionToken(caller: "HybridGagGrabber")

        if manager.availableProviders.isEmpty {
            lastError = "GagGrabber isn't available on this device — on-device models couldn't start."
            isExtracting = false
            stopElapsedTimer()
            statusMessage = ""
            return
        }

        statusMessage = "GagGrabber is scanning for jokes…"

        do {
            let result = try await manager.extractJokes(from: textToSend, hints: hints, token: token)
            let jokes = result.jokes.map(\.jokeText)
            print(" [GagGrabber] \(result.provider.displayName) returned \(jokes.count) joke(s)")

            statusMessage = "Cleaning up results…"
            let deduped = Self.deduplicateJokes(jokes)
            if deduped.isEmpty {
                lastError = "GagGrabber read the whole file but couldn't spot any jokes. Try adjusting the hints above and give it another go!"
            } else {
                // Only persist after a successful run so the next sheet open
                // starts from hints that actually produced results.
                hints.saveAsLastUsed()
            }
            extractedJokes = deduped
        } catch {
            print(" [GagGrabber] Extraction failed: \(error.localizedDescription)")
            lastError = "GagGrabber couldn't read this document. Try adjusting the hints above, or try a different file."
            extractedJokes = []
        }

        isExtracting = false
        stopElapsedTimer()
        statusMessage = ""
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                elapsedSeconds += 1
                if elapsedSeconds == 5 {
                    statusMessage = "Still working — reading through your material…"
                } else if elapsedSeconds == 12 {
                    statusMessage = "Almost there — pulling out the jokes…"
                } else if elapsedSeconds == 25 {
                    statusMessage = "Big file! GagGrabber's still on it…"
                } else if elapsedSeconds == 45 {
                    statusMessage = "Hang tight — this one's a page-turner"
                }
            }
        }
    }

    private func stopElapsedTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Dedup Helper

    static func deduplicateJokes(_ jokes: [String]) -> [String] {
        var seen = Set<String>()
        return jokes.filter { joke in
            guard !seen.contains(joke) else { return false }
            seen.insert(joke)
            return true
        }
    }
}

// MARK: - Errors

enum GagGrabberError: LocalizedError {
    case pdfExtractionFailed

    var errorDescription: String? {
        switch self {
        case .pdfExtractionFailed:
            return "Could not extract text from this PDF."
        }
    }
}

// MARK: - PDF Text Extraction Helper

private enum GagGrabberPDFReader {

    static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw GagGrabberError.pdfExtractionFailed
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                pages.append(text)
            }
        }

        let combined = pages.joined(separator: "\n\n")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GagGrabberError.pdfExtractionFailed
        }
        return combined
    }
}

// MARK: - SwiftUI: Toolbar Button + Extraction Sheet

struct HybridGagGrabberToolbarButton: View {
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("Extract Jokes", systemImage: "doc.text.magnifyingglass")
        }
        .sheet(isPresented: $showSheet) {
            HybridGagGrabberSheet()
        }
    }
}

/// Full-screen sheet: pick a document, extract jokes, and add them one-by-one
/// to the user's Joke library.
struct HybridGagGrabberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var grabber = HybridGagGrabber()

    @State private var showPicker = false
    @State private var savedJokeIDs: Set<Int> = []

    private var faceMood: GagGrabberFace.Mood {
        if grabber.isExtracting { return .working }
        if grabber.lastError != nil { return .confused }
        if !grabber.extractedJokes.isEmpty { return .happy }
        return .idle
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Welcome Hero
                Section {
                    VStack(spacing: 16) {
                        GagGrabberFace(mood: faceMood, size: 110)
                            .padding(.top, 8)

                        Text("GagGrabber")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)

                        Text("Drop in a file with your jokes and GagGrabber will read through it and pull out each one individually — so you can add them to your library one by one.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            ForEach(["TXT", "PDF", "RTF", "CSV"], id: \.self) { fmt in
                                Text(fmt)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(Color.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }

                        Label("Runs entirely on your device", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }

                // MARK: Document Format Hints
                Section {
                    ExtractionHintsForm(hints: $grabber.hints, compact: true)
                        .padding(.vertical, 4)
                } header: {
                    Label("Tell GagGrabber about your document (optional)", systemImage: "text.magnifyingglass")
                } footer: {
                    Text("Skip this and tap Extract — GagGrabber will try to figure it out on its own.")
                        .font(.caption)
                }

                // MARK: Source
                Section("Document") {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Pick a Document (.txt, .pdf, .rtf, …)", systemImage: "doc.badge.plus")
                    }
                    .disabled(grabber.isExtracting)
                }

                // MARK: Status
                if grabber.isExtracting {
                    Section {
                        VStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text(grabber.statusMessage.isEmpty ? "GagGrabber is extracting jokes…" : grabber.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut(duration: 0.3), value: grabber.statusMessage)
                            if grabber.elapsedSeconds > 0 {
                                Text("\(grabber.elapsedSeconds)s")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            Text("Please stay on this page until it's done!")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                if let error = grabber.lastError {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.accentColor.opacity(0.6))

                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                // MARK: Results
                if !grabber.extractedJokes.isEmpty {
                    let allSaved = grabber.extractedJokes.indices.allSatisfy { savedJokeIDs.contains($0) }

                    Section {
                        if !allSaved {
                            Button {
                                addAllJokesToLibrary()
                            } label: {
                                Label("Add All \(grabber.extractedJokes.count) Jokes", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.vertical, 4)
                        } else {
                            Label("All \(grabber.extractedJokes.count) jokes added!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }

                    Section("Extracted Jokes (\(grabber.extractedJokes.count))") {
                        ForEach(Array(grabber.extractedJokes.enumerated()), id: \.offset) { index, joke in
                            HStack(alignment: .top) {
                                Text(joke)
                                    .font(.body)

                                Spacer()

                                if savedJokeIDs.contains(index) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button {
                                        addJokeToLibrary(joke, index: index)
                                    } label: {
                                        Text("Add")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("GagGrabber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(grabber.isExtracting)
                }
            }
            .interactiveDismissDisabled(grabber.isExtracting)
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [.text, .plainText, .utf8PlainText, .pdf, .rtf, .html, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await handlePickedDocument(url) }
                case .failure(let error):
                    grabber.lastError = "Could not open file: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Document Handling

    private func handlePickedDocument(_ url: URL) async {
        grabber.statusMessage = "Opening your file…"
        grabber.isExtracting = true
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()

        do {
            let text: String
            if ext == "pdf" {
                text = try GagGrabberPDFReader.extractText(from: url)
            } else if ext == "rtf" || ext == "rtfd" {
                let data = try Data(contentsOf: url)
                let attributed = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                text = attributed.string
            } else if ext == "html" || ext == "htm" {
                let data = try Data(contentsOf: url)
                let attributed = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )
                text = attributed.string
            } else {
                if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                    text = utf8
                } else {
                    text = try String(contentsOf: url)
                }
            }

            await grabber.extractJokes(from: text)
        } catch {
            grabber.lastError = "Failed to read document: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private func addJokeToLibrary(_ jokeText: String, index: Int) {
        if let match = DuplicateDetectionService.findDuplicate(content: jokeText, title: nil, in: modelContext),
           match.similarity >= 0.90 {
            grabber.lastError = "This joke looks like a duplicate of \"\(match.existingTitle)\" (\(Int(match.similarity * 100))% match). Skipped."
            savedJokeIDs.insert(index)
            return
        }

        let joke = Joke(content: jokeText)
        joke.importSource = "GagGrabber"
        joke.importTimestamp = Date()
        modelContext.insert(joke)

        do {
            try modelContext.save()
            savedJokeIDs.insert(index)
            print(" [GagGrabber] Saved joke #\(index + 1) to library")
        } catch {
            grabber.lastError = "Failed to save joke: \(error.localizedDescription)"
            print(" [GagGrabber] Save failed: \(error)")
        }
    }

    private func addAllJokesToLibrary() {
        var count = 0
        var duplicateCount = 0
        for (index, jokeText) in grabber.extractedJokes.enumerated() {
            guard !savedJokeIDs.contains(index) else { continue }
            if DuplicateDetectionService.findDuplicate(content: jokeText, title: nil, in: modelContext, threshold: 0.90) != nil {
                savedJokeIDs.insert(index)
                duplicateCount += 1
                continue
            }
            let joke = Joke(content: jokeText)
            joke.importSource = "GagGrabber"
            joke.importTimestamp = Date()
            modelContext.insert(joke)
            savedJokeIDs.insert(index)
            count += 1
        }
        do {
            try modelContext.save()
            var msg = "Saved \(count) joke(s) to library"
            if duplicateCount > 0 { msg += " (\(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s") skipped)" }
            print(" [GagGrabber] \(msg)")
            if duplicateCount > 0 {
                grabber.lastError = "\(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s") skipped — already in your library."
            }
        } catch {
            grabber.lastError = "Failed to save jokes: \(error.localizedDescription)"
            print(" [GagGrabber] Batch save failed: \(error)")
        }
    }
}


// MARK: - Preview

#Preview {
    HybridGagGrabberSheet()
        .modelContainer(for: Joke.self, inMemory: true)
}
