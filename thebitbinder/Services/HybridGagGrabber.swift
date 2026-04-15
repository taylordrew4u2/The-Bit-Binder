//
//  GagGrabber.swift  (was HybridGagGrabber.swift)
//  thebitbinder
//
//  Joke extractor: uses OpenAI (gpt-3.5-turbo, free-tier friendly) with a
//  heuristic fallback when no API key is configured or the request fails.
//
//  Architecture:
//  - OpenAI runs when `useOpenAI` is true AND a key is configured.
//  - If OpenAI fails (rate limit, offline, bad key) or is disabled, a fast
//    heuristic extractor runs instead — extraction never silently fails.
//  - Long text is chunked (2 000 chars, sentence-boundary aware) before being
//    sent to the API.
//  - Results are deduplicated by exact match.
//
//  UI: `HybridGagGrabberSheet` — a toolbar-button-triggered sheet that lets the
//  user pick a .txt or .pdf, extract jokes, and add them one-by-one to their
//  library via the Joke SwiftData model.
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// MARK: - HybridGagGrabber (ObservableObject)

/// Extracts jokes from raw text using OpenAI (remote) with a heuristic fallback.
/// Published state drives the companion `HybridGagGrabberSheet` view.
@MainActor
final class HybridGagGrabber: ObservableObject {

    // MARK: Published State

    /// Jokes extracted from the most recent `extractJokes` call, deduplicated.
    @Published var extractedJokes: [String] = []

    /// Whether an extraction is currently running.
    @Published var isExtracting: Bool = false

    /// Human-readable description of the last error, or nil.
    @Published var lastError: String?

    // MARK: Private State

    /// User-supplied OpenAI key (stored in memory only — the canonical store is
    /// Keychain via `KeychainHelper`). Call `setOpenAIKey(_:)` to persist.
    private var openAIKey: String?

    /// Keychain account key — mirrors the pattern used by the existing
    /// `AIKeyLoader` / `AIProviderType.openAI.keychainKey` so the two systems
    /// share the same key transparently.
    static let keychainAccount = "ai_key_openai"

    // MARK: - Configuration

    /// Provide (or update) the OpenAI API key.
    /// The key is saved to the Keychain so it persists across launches and is
    /// available to the existing `AIJokeExtractionManager` providers too.
    func setOpenAIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            openAIKey = nil
            KeychainHelper.delete(forKey: Self.keychainAccount)
        } else {
            openAIKey = trimmed
            KeychainHelper.save(trimmed, forKey: Self.keychainAccount)
        }
    }

    // MARK: - Main Extraction Entry Point

    /// Extract jokes from `rawText` using OpenAI (if enabled) with a heuristic
    /// fallback that always guarantees results.
    ///
    /// - Parameters:
    ///   - rawText: The full text of the document.
    ///   - useOpenAI: When `true`, queries OpenAI if a key is available.
    func extractJokes(from rawText: String, useOpenAI: Bool = false) async {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Document is empty — nothing to extract."
            return
        }

        isExtracting = true
        lastError = nil
        extractedJokes = []

        let chunks = GagGrabberChunker.chunk(rawText, maxLength: 2000)
        print(" [GagGrabber] Text length: \(rawText.count) chars → \(chunks.count) chunk(s)")

        // ------------------------------------------------------------------
        // 1. OpenAI (optional)
        // ------------------------------------------------------------------
        var openAIJokes: [String] = []
        if useOpenAI {
            let resolvedKey = openAIKey
                ?? KeychainHelper.load(forKey: Self.keychainAccount)

            if let key = resolvedKey, !key.isEmpty {
                do {
                    openAIJokes = try await extractViaOpenAI(chunks: chunks, apiKey: key)
                    print(" [GagGrabber] OpenAI returned \(openAIJokes.count) joke(s)")
                } catch {
                    print(" [GagGrabber] OpenAI extraction failed: \(error.localizedDescription)")
                    // Non-fatal — heuristic results will be used instead.
                }
            } else {
                print(" [GagGrabber] OpenAI skipped — no API key configured")
            }
        }

        // ------------------------------------------------------------------
        // 2. Heuristic fallback (when OpenAI is off or produced nothing)
        // ------------------------------------------------------------------
        var heuristicJokes: [String] = []
        if openAIJokes.isEmpty {
            print(" [GagGrabber] Running heuristic fallback")
            heuristicJokes = Self.extractViaHeuristic(from: rawText)
            print(" [GagGrabber] Heuristic returned \(heuristicJokes.count) joke(s)")
        }

        // ------------------------------------------------------------------
        // 3. Merge & deduplicate
        // ------------------------------------------------------------------
        let merged = Self.deduplicateJokes(openAIJokes + heuristicJokes)

        if merged.isEmpty {
            lastError = "No jokes found. The document may not contain recognizable joke content."
        }

        extractedJokes = merged
        isExtracting = false
    }

    // MARK: - OpenAI Extraction

    /// Sends each chunk to the OpenAI Chat Completions API and parses "JOKE:"
    /// lines from the response. Includes basic rate-limit handling.
    private func extractViaOpenAI(chunks: [String], apiKey: String) async throws -> [String] {
        var results: [String] = []

        for (index, chunk) in chunks.enumerated() {
            print(" [GagGrabber/OpenAI] Processing chunk \(index + 1)/\(chunks.count)")

            let body: [String: Any] = [
                "model": "gpt-3.5-turbo",
                "temperature": 0.2,
                "max_tokens": 500,
                "messages": [
                    [
                        "role": "system",
                        "content": """
                        You are a joke extraction tool. Read the user's text and output every joke you find.
                        Output ONLY lines starting with "JOKE:" followed by the joke text.
                        Do not add commentary, numbering, or any other text.
                        """
                    ],
                    [
                        "role": "user",
                        "content": "Extract jokes from the following text:\n\n\(chunk)"
                    ]
                ]
            ]

            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    throw GagGrabberError.openAIRateLimited
                }
                guard (200...299).contains(http.statusCode) else {
                    let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw GagGrabberError.openAIError("HTTP \(http.statusCode): \(detail)")
                }
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw GagGrabberError.openAIError("Unexpected response format")
            }

            let parsed = Self.parseJokeLines(from: content)
            results.append(contentsOf: parsed)
        }

        return results
    }

    // MARK: - Heuristic Extraction (always available)

    /// Structural heuristic that splits text by blank lines, bullet points,
    /// and numbered lists — mirrors `BitBuddyService.extractJokes(from:)`.
    /// This guarantees the user always gets results even when OpenAI is
    /// unavailable or disabled.
    private static func extractViaHeuristic(from text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let rawParts = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var jokes: [String] = []
        var currentBlock: [String] = []

        for line in rawParts {
            if line.isEmpty {
                if !currentBlock.isEmpty {
                    jokes.append(currentBlock.joined(separator: "\n"))
                    currentBlock.removeAll()
                }
                continue
            }

            let isBullet = line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("*")
            let isNumbered = line.range(of: #"^\d+[\.)]\s"#, options: .regularExpression) != nil

            if (isBullet || isNumbered), !currentBlock.isEmpty {
                jokes.append(currentBlock.joined(separator: "\n"))
                currentBlock = [stripListMarker(from: line)]
            } else {
                currentBlock.append(isBullet || isNumbered ? stripListMarker(from: line) : line)
            }
        }

        if !currentBlock.isEmpty {
            jokes.append(currentBlock.joined(separator: "\n"))
        }

        let filtered = jokes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if filtered.isEmpty, !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [normalized.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        return filtered
    }

    private static func stripListMarker(from line: String) -> String {
        line
            .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+[\.)]\s*"#, with: "", options: .regularExpression)
    }

    // MARK: - Parsing Helpers

    /// Parses output lines starting with "JOKE:" into an array of joke strings.
    /// Leading/trailing whitespace and the "JOKE:" prefix are stripped.
    nonisolated static func parseJokeLines(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.uppercased().hasPrefix("JOKE:") else { return nil }
                let jokeText = String(trimmed.dropFirst(5))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return jokeText.isEmpty ? nil : jokeText
            }
    }

    /// Removes exact-duplicate jokes (case-sensitive) while preserving order.
    static func deduplicateJokes(_ jokes: [String]) -> [String] {
        var seen = Set<String>()
        return jokes.filter { joke in
            guard !seen.contains(joke) else { return false }
            seen.insert(joke)
            return true
        }
    }
}

// MARK: - Text Chunker

/// Splits a long string into chunks of at most `maxLength` characters,
/// preferring to break at sentence boundaries so the API receives
/// coherent context.
enum GagGrabberChunker {

    static func chunk(_ text: String, maxLength: Int = 2000) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else {
            return cleaned.isEmpty ? [] : [cleaned]
        }

        var chunks: [String] = []
        var remaining = cleaned[cleaned.startIndex...]

        while !remaining.isEmpty {
            if remaining.count <= maxLength {
                chunks.append(String(remaining))
                break
            }

            let window = remaining.prefix(maxLength)
            var splitIndex = window.endIndex

            for candidate in [". ", "! ", "? ", "\n"] {
                if let range = window.range(of: candidate, options: .backwards) {
                    splitIndex = range.upperBound
                    break
                }
            }

            let chunk = String(remaining[remaining.startIndex..<splitIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            remaining = remaining[splitIndex...]
        }

        return chunks
    }
}

// MARK: - Errors

enum GagGrabberError: LocalizedError {
    case openAIRateLimited
    case openAIError(String)
    case pdfExtractionFailed

    var errorDescription: String? {
        switch self {
        case .openAIRateLimited:
            return "OpenAI rate limit hit — try again in a minute."
        case .openAIError(let detail):
            return "OpenAI error: \(detail)"
        case .pdfExtractionFailed:
            return "Could not extract text from this PDF."
        }
    }
}

// MARK: - PDF Text Extraction Helper

/// Lightweight PDF-to-text helper using PDFKit.
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

/// A toolbar button that presents the `HybridGagGrabberSheet`.
/// Drop this into any SwiftUI view's `.toolbar { }` block.
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

/// Full-screen sheet: pick a document (.txt / .pdf), extract jokes, and add
/// them one-by-one to the user's Joke library.
struct HybridGagGrabberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var grabber = HybridGagGrabber()

    @State private var showPicker = false
    @State private var useOpenAI = false
    @State private var openAIKeyInput = ""
    @State private var savedJokeIDs: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                // MARK: Source
                Section("Document") {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Pick a Document (.txt, .pdf)", systemImage: "doc.badge.plus")
                    }
                    .disabled(grabber.isExtracting)
                }

                // MARK: OpenAI Toggle
                Section {
                    Toggle("Use OpenAI", isOn: $useOpenAI)

                    if useOpenAI {
                        SecureField("OpenAI API Key (optional)", text: $openAIKeyInput)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                grabber.setOpenAIKey(openAIKeyInput)
                            }
                            .onChange(of: openAIKeyInput) { _, newValue in
                                grabber.setOpenAIKey(newValue)
                            }

                        Text("Key is stored securely in your device Keychain.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI Sources")
                } footer: {
                    Text("OpenAI is optional. Without it, a heuristic extractor splits the document by structure (blank lines, bullets, numbered lists).")
                }

                // MARK: Status
                if grabber.isExtracting {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Extracting jokes…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = grabber.lastError {
                    Section("Error") {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                // MARK: Results
                if !grabber.extractedJokes.isEmpty {
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
                }
            }
            .sheet(isPresented: $showPicker) {
                GagGrabberDocumentPicker { urls in
                    guard let url = urls.first else { return }
                    Task {
                        await handlePickedDocument(url)
                    }
                }
            }
            .onAppear {
                if let existing = KeychainHelper.load(forKey: HybridGagGrabber.keychainAccount),
                   !existing.isEmpty {
                    openAIKeyInput = existing
                }
            }
        }
    }

    // MARK: - Document Handling

    private func handlePickedDocument(_ url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()

        do {
            let text: String
            if ext == "pdf" {
                text = try GagGrabberPDFReader.extractText(from: url)
            } else {
                if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                    text = utf8
                } else {
                    text = try String(contentsOf: url)
                }
            }

            await grabber.extractJokes(from: text, useOpenAI: useOpenAI)
        } catch {
            grabber.lastError = "Failed to read document: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    /// Creates a new `Joke` from the extracted text and inserts it into
    /// SwiftData. Follows the existing `Joke.init(content:title:folder:)` pattern.
    private func addJokeToLibrary(_ jokeText: String, index: Int) {
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
}

// MARK: - Document Picker

/// A lightweight UIDocumentPickerViewController wrapper scoped to .txt and .pdf.
private struct GagGrabberDocumentPicker: UIViewControllerRepresentable {
    let completion: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.plainText, .pdf, .utf8PlainText, .text]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
    }
}

// MARK: - Preview

#Preview {
    HybridGagGrabberSheet()
        .modelContainer(for: Joke.self, inMemory: true)
}