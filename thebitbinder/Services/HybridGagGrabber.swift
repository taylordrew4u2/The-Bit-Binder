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

        let preprocessed = hints.preprocess(rawText)
        if preprocessed.count != rawText.count {
            print(" [GagGrabber] Preprocessing trimmed \(rawText.count - preprocessed.count) chars")
        }

        // Step 1: If the user told us the format, use it directly. No AI.
        statusMessage = "Scanning your document…"
        let hintSplit = Self.splitUsingHints(preprocessed, hints: hints)

        if hintSplit.count >= 2 {
            print(" [GagGrabber] Hint-based split found \(hintSplit.count) joke(s)")
            let cleaned = hintSplit.map { Self.cleanJokeText($0) }.filter { !$0.isEmpty }
            let deduped = Self.deduplicateJokes(cleaned)
            if !deduped.isEmpty {
                hints.saveAsLastUsed()
                extractedJokes = deduped
                isExtracting = false
                stopElapsedTimer()
                statusMessage = ""
                return
            }
        }

        // Step 2: Auto-detect structure (numbered, bullets, blank lines).
        let smartSplit = SmartTextSplitter.split(preprocessed)

        if smartSplit.count >= 2 {
            print(" [GagGrabber] SmartTextSplitter found \(smartSplit.count) joke(s)")
            let cleaned = smartSplit.map { Self.cleanJokeText($0) }.filter { !$0.isEmpty }
            let deduped = Self.deduplicateJokes(cleaned)
            if !deduped.isEmpty {
                hints.saveAsLastUsed()
                extractedJokes = deduped
                isExtracting = false
                stopElapsedTimer()
                statusMessage = ""
                return
            }
        }

        // Step 3: Structural splits didn't work — try AI providers.
        let textToSend = hints.applyingPromptPrefix(to: preprocessed)
        let manager = AIJokeExtractionManager.shared
        let token = AIExtractionToken(caller: "HybridGagGrabber")

        if manager.availableProviders.isEmpty {
            lastError = "GagGrabber needs either Apple Intelligence (iOS 26+) or an OpenAI API key in Settings."
            isExtracting = false
            stopElapsedTimer()
            statusMessage = ""
            return
        }

        statusMessage = "GagGrabber is scanning for jokes…"

        do {
            let result = try await manager.extractJokes(from: textToSend, hints: hints, token: token)
            let jokes = result.jokes.map { Self.stripLeadingNumber($0.jokeText) }
            print(" [GagGrabber] \(result.provider.displayName) returned \(jokes.count) joke(s)")

            statusMessage = "Cleaning up results…"
            let deduped = Self.deduplicateJokes(jokes)
            if deduped.isEmpty {
                if !smartSplit.isEmpty {
                    extractedJokes = smartSplit.map { Self.cleanJokeText($0) }.filter { !$0.isEmpty }
                } else {
                    lastError = "GagGrabber read the whole file but couldn't spot any jokes. Try adjusting the hints above and give it another go!"
                }
            } else {
                hints.saveAsLastUsed()
                extractedJokes = deduped
            }
        } catch {
            print(" [GagGrabber] AI extraction failed: \(error.localizedDescription)")
            if !smartSplit.isEmpty {
                print(" [GagGrabber] Using SmartTextSplitter results as fallback (\(smartSplit.count) chunks)")
                extractedJokes = smartSplit.map { Self.cleanJokeText($0) }.filter { !$0.isEmpty }
            } else {
                lastError = error.localizedDescription
                extractedJokes = []
            }
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

    // MARK: - Hint-Based Splitting

    /// When the user tells us the format, split on that format directly.
    /// No AI, no heuristics — just split where the user said to split.
    nonisolated static func splitUsingHints(_ text: String, hints: ExtractionHints) -> [String] {
        let lines = text.components(separatedBy: "\n")

        switch hints.separator {
        case .numbered:
            return splitOnNumberedLines(lines)
        case .bullets:
            return splitOnBulletLines(lines)
        case .blankLine:
            return splitOnBlankLines(text)
        case .headers, .noneOrFlowing, .mixed:
            return []
        }
    }

    /// Split where lines start with a number: 1. / 1) / 1: / 1- / #1 / Joke 1: etc.
    private nonisolated static func splitOnNumberedLines(_ lines: [String]) -> [String] {
        let pattern = #"^\s*(?:(?:joke|bit|gag|#)\s*)?#?\s*\d+\s*[.)\-:–—]\s*"#
        var chunks: [String] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isNumbered = trimmed.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil

            if isNumbered && !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = [trimmed]
            } else if !trimmed.isEmpty || !current.isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        return chunks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Split where lines start with a bullet: - / • / * / –
    private nonisolated static func splitOnBulletLines(_ lines: [String]) -> [String] {
        var chunks: [String] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isBullet = trimmed.range(
                of: #"^\s*[•\-\*–—]\s+"#,
                options: .regularExpression
            ) != nil

            if isBullet && !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = [trimmed]
            } else if !trimmed.isEmpty || !current.isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        return chunks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Split on blank lines (one or more empty lines between jokes).
    private nonisolated static func splitOnBlankLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Cleaning Helpers

    /// Strips all formatting artifacts so jokes land clean in the binder.
    /// Handles numbered lists, bullets, dashes, separators, quotes, labels.
    nonisolated static func cleanJokeText(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading labels like "Joke 1:", "Bit #3:", "#1.", "Joke:", etc.
        // Requires either a label word OR at least one digit before the separator
        // so bare punctuation like "..." or "- text" isn't incorrectly eaten.
        t = t.replacingOccurrences(
            of: #"^\s*(?:(?:joke|bit|gag|premise|tag|closer)\s*#?\s*\d*\s*[.)\-:–—]\s*|#?\s*\d+\s*[.)\-:–—]\s*)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip leading bullets: •, -, *, –, —, >
        t = t.replacingOccurrences(
            of: #"^\s*[•\-\*–—>]\s+"#,
            with: "",
            options: .regularExpression
        )

        // Strip trailing separator lines: ---, ***, ===, etc.
        t = t.replacingOccurrences(
            of: #"\s*[-–—=\*]{3,}\s*$"#,
            with: "",
            options: .regularExpression
        )

        // Strip wrapping quotes if they surround the whole text
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) ||
           (t.hasPrefix("\u{201C}") && t.hasSuffix("\u{201D}")) {
            t = String(t.dropFirst().dropLast())
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Backwards-compatible alias used by `AIExtractedJoke.toImportedJoke`.
    nonisolated static func stripLeadingNumber(_ text: String) -> String {
        cleanJokeText(text)
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
            Label {
                Text("Extract Jokes")
            } icon: {
                Image("GagGrabberGlyph")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
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
    @State private var showGoogleDocsInput = false
    @State private var googleDocsURL = ""

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
                        GagGrabberFace(mood: faceMood, size: 56)
                            .padding(.top, 8)

                        Text("GagGrabber")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)

                        Text("Drop in a file with your jokes and GagGrabber will read through it and pull out each one individually — so you can add them to your library one by one.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            ForEach(["TXT", "PDF", "RTF", "Google Docs"], id: \.self) { fmt in
                                Text(fmt)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(Color.accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
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
                        Label("Pick a File (.txt, .pdf, .rtf, …)", systemImage: "doc.badge.plus")
                    }
                    .disabled(grabber.isExtracting)

                    Button {
                        withAnimation { showGoogleDocsInput.toggle() }
                    } label: {
                        Label("Import from Google Docs", systemImage: "link")
                    }
                    .disabled(grabber.isExtracting)

                    if showGoogleDocsInput {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Paste Google Docs link", text: $googleDocsURL)
                                .font(.footnote)
                                .textContentType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)

                            Button {
                                Task { await handleGoogleDocsImport() }
                            } label: {
                                Label("Fetch Document", systemImage: "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(googleDocsURL.trimmingCharacters(in: .whitespaces).isEmpty || grabber.isExtracting)

                            Text("The doc must be shared with \"Anyone with the link.\"")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
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

    // MARK: - Google Docs Import

    private func handleGoogleDocsImport() async {
        let raw = googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        guard let docID = Self.extractGoogleDocID(from: raw) else {
            grabber.lastError = "Couldn't read that link. Paste the full Google Docs URL (starts with docs.google.com)."
            return
        }

        grabber.isExtracting = true
        grabber.lastError = nil
        grabber.extractedJokes = []
        grabber.statusMessage = "Fetching from Google Docs…"

        let exportURLString = "https://docs.google.com/document/d/\(docID)/export?format=txt"
        guard let exportURL = URL(string: exportURLString) else {
            grabber.lastError = "Invalid document link."
            grabber.isExtracting = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: exportURL)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if http.statusCode == 404 {
                    grabber.lastError = "Document not found. Check the link and make sure it's shared."
                } else if http.statusCode == 403 {
                    grabber.lastError = "Access denied. Make sure the doc is shared with \"Anyone with the link.\""
                } else {
                    grabber.lastError = "Google returned an error (status \(http.statusCode)). Make sure the doc is shared."
                }
                grabber.isExtracting = false
                return
            }

            guard let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                grabber.lastError = "The document appears to be empty."
                grabber.isExtracting = false
                return
            }

            await grabber.extractJokes(from: text)
        } catch {
            grabber.lastError = "Failed to fetch document: \(error.localizedDescription)"
            grabber.isExtracting = false
        }
    }

    /// Extracts the document ID from various Google Docs URL formats.
    private static func extractGoogleDocID(from urlString: String) -> String? {
        // Formats:
        //   https://docs.google.com/document/d/DOCID/edit
        //   https://docs.google.com/document/d/DOCID/edit?usp=sharing
        //   https://docs.google.com/document/d/DOCID
        //   docs.google.com/document/d/DOCID/...
        guard let regex = try? NSRegularExpression(
            pattern: #"docs\.google\.com/document/d/([a-zA-Z0-9_\-]+)"#
        ) else { return nil }

        let range = NSRange(urlString.startIndex..., in: urlString)
        guard let match = regex.firstMatch(in: urlString, range: range),
              let idRange = Range(match.range(at: 1), in: urlString) else { return nil }

        return String(urlString[idRange])
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
            grabber.isExtracting = false
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
