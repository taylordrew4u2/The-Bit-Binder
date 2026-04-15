//
//  HybridGagGrabber.swift
//  thebitbinder
//
//  Hybrid joke extractor: uses on-device MLX (Phi-3 Mini) as the primary
//  extraction engine, with an optional OpenAI fallback when the user provides
//  their own API key.
//
//  Architecture notes:
//  - MLX extraction always runs first.
//  - OpenAI only runs when `useOpenAI` is true AND a key is configured.
//  - If OpenAI fails (rate limit, offline, bad key), the MLX results are still
//    returned — extraction never silently fails to produce results when MLX
//    succeeds.
//  - Long text is chunked (2 000 chars, sentence-boundary aware) before being
//    sent to either extractor.
//  - Results from both sources are merged and exact-duplicate lines removed.
//
//  UI: `HybridGagGrabberSheet` — a toolbar-button-triggered sheet that lets the
//  user pick a .txt or .pdf, extract jokes, and add them one-by-one to their
//  library via the Joke SwiftData model.
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

// MARK: - HybridGagGrabber (ObservableObject)

/// Extracts jokes from raw text using MLX (local) + optional OpenAI (remote).
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

    /// Extract jokes from `rawText` using MLX and, optionally, OpenAI.
    ///
    /// - Parameters:
    ///   - rawText: The full text of the document.
    ///   - useOpenAI: When `true`, also queries OpenAI if a key is available.
    func extractJokes(from rawText: String, useOpenAI: Bool = false) async {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Document is empty — nothing to extract."
            return
        }

        isExtracting = true
        lastError = nil
        extractedJokes = []

        let chunks = HybridGagGrabberChunker.chunk(rawText, maxLength: 2000)
        print(" [HybridGagGrabber] Text length: \(rawText.count) chars → \(chunks.count) chunk(s)")

        // ------------------------------------------------------------------
        // 1. MLX (local, always attempted)
        // ------------------------------------------------------------------
        var mlxJokes: [String] = []
        do {
            mlxJokes = try await extractViaMLX(chunks: chunks)
            print(" [HybridGagGrabber] MLX returned \(mlxJokes.count) joke(s)")
        } catch {
            print(" [HybridGagGrabber] MLX extraction failed: \(error.localizedDescription)")
            // Not fatal — OpenAI may still work, or we surface error at the end.
        }

        // ------------------------------------------------------------------
        // 2. OpenAI (optional)
        // ------------------------------------------------------------------
        var openAIJokes: [String] = []
        if useOpenAI {
            let resolvedKey = openAIKey
                ?? KeychainHelper.load(forKey: Self.keychainAccount)

            if let key = resolvedKey, !key.isEmpty {
                do {
                    openAIJokes = try await extractViaOpenAI(chunks: chunks, apiKey: key)
                    print(" [HybridGagGrabber] OpenAI returned \(openAIJokes.count) joke(s)")
                } catch {
                    print(" [HybridGagGrabber] OpenAI extraction failed: \(error.localizedDescription)")
                    // Non-fatal — MLX results (if any) still used.
                }
            } else {
                print(" [HybridGagGrabber] OpenAI skipped — no API key configured")
            }
        }

        // ------------------------------------------------------------------
        // 3. Merge & deduplicate
        // ------------------------------------------------------------------
        let merged = Self.deduplicateJokes(mlxJokes + openAIJokes)

        if merged.isEmpty && mlxJokes.isEmpty && openAIJokes.isEmpty {
            lastError = "No jokes found. The document may not contain recognizable joke content."
        }

        extractedJokes = merged
        isExtracting = false
    }

    // MARK: - MLX Extraction

    /// Runs each chunk through the on-device Phi-3 Mini model and parses
    /// lines prefixed with "JOKE:" from the output.
    private func extractViaMLX(chunks: [String]) async throws -> [String] {
#if canImport(MLXLLM) && canImport(MLXLMCommon)
        var results: [String] = []

        for (index, chunk) in chunks.enumerated() {
            print(" [HybridGagGrabber/MLX] Processing chunk \(index + 1)/\(chunks.count)")

            let prompt = Self.buildMLXPrompt(for: chunk)

            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(
                    id: "mlx-community/Phi-3-mini-4k-instruct-4bit",
                    defaultPrompt: "Extract jokes from text.",
                    extraEOSTokens: ["<|end|>"]
                )
            )
            let session = ChatSession(
                container,
                instructions: """
                You are a joke extraction tool. Read the text and output every joke you find.
                Output ONLY lines starting with "JOKE:" followed by the joke text.
                Do not add commentary, numbering, or any other text.
                """
            )
            let output = try await session.respond(to: prompt)
            let parsed = Self.parseJokeLines(from: output)
            results.append(contentsOf: parsed)
        }

        return results
#else
        print(" [HybridGagGrabber] MLX unavailable on this platform")
        throw HybridGagGrabberError.mlxUnavailable
#endif
    }

    /// Builds the MLX prompt for a single text chunk.
    private static func buildMLXPrompt(for chunk: String) -> String {
        """
        [INST] <<SYS>>
        Extract every joke, bit, or comedic premise from the text below.
        Output one joke per line, each starting with "JOKE:".
        Do not paraphrase — preserve the original wording.
        If no jokes are found, output nothing.
        <</SYS>>

        --- TEXT ---
        \(chunk)
        [/INST]
        """
    }

    // MARK: - OpenAI Extraction

    /// Sends each chunk to the OpenAI Chat Completions API and parses "JOKE:"
    /// lines from the response.
    private func extractViaOpenAI(chunks: [String], apiKey: String) async throws -> [String] {
        var results: [String] = []

        for (index, chunk) in chunks.enumerated() {
            print(" [HybridGagGrabber/OpenAI] Processing chunk \(index + 1)/\(chunks.count)")

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
                    throw HybridGagGrabberError.openAIRateLimited
                }
                guard (200...299).contains(http.statusCode) else {
                    let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw HybridGagGrabberError.openAIError("HTTP \(http.statusCode): \(detail)")
                }
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw HybridGagGrabberError.openAIError("Unexpected response format")
            }

            let parsed = Self.parseJokeLines(from: content)
            results.append(contentsOf: parsed)
        }

        return results
    }

    // MARK: - Parsing Helpers

    /// Parses output lines starting with "JOKE:" into an array of joke strings.
    /// Leading/trailing whitespace and the "JOKE:" prefix are stripped.
    static func parseJokeLines(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // Case-insensitive check for the "JOKE:" prefix
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
/// preferring to break at sentence boundaries so the LLM receives
/// coherent context.
enum HybridGagGrabberChunker {

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

            // Look for the last sentence-ending punctuation within the window.
            let window = remaining.prefix(maxLength)
            var splitIndex = window.endIndex

            // Search backwards for ". " or "! " or "? " or newline
            for candidate in [". ", "! ", "? ", "\n"] {
                if let range = window.range(of: candidate, options: .backwards) {
                    // Include the punctuation character, break after the space/newline
                    splitIndex = range.upperBound
                    break
                }
            }

            // If no sentence boundary found, hard-split at maxLength
            if splitIndex == window.endIndex {
                splitIndex = window.endIndex
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

enum HybridGagGrabberError: LocalizedError {
    case mlxUnavailable
    case openAIRateLimited
    case openAIError(String)
    case pdfExtractionFailed

    var errorDescription: String? {
        switch self {
        case .mlxUnavailable:
            return "On-device MLX model is not available on this platform."
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

/// Lightweight PDF-to-text helper using PDFKit. The existing
/// `PDFTextExtractor` in the codebase is more sophisticated (layout-aware,
/// repeating-header detection). This helper is intentionally simpler — it
/// just needs the raw string for the joke extractor.
private enum HybridPDFReader {

    static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw HybridGagGrabberError.pdfExtractionFailed
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                pages.append(text)
            }
        }

        let combined = pages.joined(separator: "\n\n")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HybridGagGrabberError.pdfExtractionFailed
        }
        return combined
    }
}

// MARK: - SwiftUI: Toolbar Button + Extraction Sheet

/// A toolbar button that presents the `HybridGagGrabberSheet`.
/// Drop this into any SwiftUI view's `.toolbar { }` block.
///
/// Example:
/// ```swift
/// .toolbar {
///     HybridGagGrabberToolbarButton()
/// }
/// ```
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
    @State private var savedJokeIDs: Set<Int> = []   // track which rows were saved

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
                    Toggle("Also use OpenAI", isOn: $useOpenAI)

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
                    Text("MLX (on-device) always runs. OpenAI is optional — if it fails, MLX results are still used.")
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
            .navigationTitle("HybridGagGrabber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                HybridDocumentPicker { urls in
                    guard let url = urls.first else { return }
                    Task {
                        await handlePickedDocument(url)
                    }
                }
            }
            .onAppear {
                // Pre-fill key field from Keychain if one already exists
                if let existing = KeychainHelper.load(forKey: HybridGagGrabber.keychainAccount),
                   !existing.isEmpty {
                    openAIKeyInput = existing
                }
            }
        }
    }

    // MARK: - Document Handling

    private func handlePickedDocument(_ url: URL) async {
        let ext = url.pathExtension.lowercased()

        do {
            let text: String
            if ext == "pdf" {
                text = try HybridPDFReader.extractText(from: url)
            } else {
                // .txt, .md, .rtf, or anything text-based
                text = try String(contentsOf: url, encoding: .utf8)
            }

            await grabber.extractJokes(from: text, useOpenAI: useOpenAI)
        } catch {
            grabber.lastError = "Failed to read document: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    /// Creates a new `Joke` from the extracted text and inserts it into
    /// SwiftData. Follows the existing `Joke.init(content:title:folder:)`
    /// pattern.
    private func addJokeToLibrary(_ jokeText: String, index: Int) {
        let joke = Joke(content: jokeText)
        joke.importSource = "HybridGagGrabber"
        joke.importTimestamp = Date()
        modelContext.insert(joke)

        do {
            try modelContext.save()
            savedJokeIDs.insert(index)
            print(" [HybridGagGrabber] Saved joke #\(index + 1) to library")
        } catch {
            grabber.lastError = "Failed to save joke: \(error.localizedDescription)"
            print(" [HybridGagGrabber] Save failed: \(error)")
        }
    }
}

// MARK: - Minimal Document Picker (reuses the project's UTType set)

/// A lightweight UIDocumentPickerViewController wrapper scoped to .txt and .pdf.
private struct HybridDocumentPicker: UIViewControllerRepresentable {
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
