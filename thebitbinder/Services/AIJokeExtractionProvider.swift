//
//  AIJokeExtractionProvider.swift
//  thebitbinder
//
//  Protocol + shared types for on-device joke extraction.
//  GagGrabber runs entirely offline — no cloud providers, no API keys,
//  no network calls. The concrete providers are:
//    • AppleOnDeviceJokeExtractionProvider — Apple Foundation Models (iOS 26+)
//    • EmbeddingSegmenterProvider           — NLEmbedding sentence segmenter
//

import Foundation

// MARK: - Provider Identity

/// On-device extraction providers GagGrabber can use.
enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case appleOnDevice  = "AppleOnDevice"
    case embeddingLocal = "EmbeddingLocal"

    var id: String { rawValue }

    /// All providers here run entirely on-device.
    var isOnDevice: Bool { true }

    var displayName: String {
        switch self {
        case .appleOnDevice:  return "On-Device (Apple)"
        case .embeddingLocal: return "On-Device (Offline Segmenter)"
        }
    }

    var icon: String {
        switch self {
        case .appleOnDevice:  return "cpu"
        case .embeddingLocal: return "waveform.path.ecg"
        }
    }
}

// MARK: - Provider Errors

enum AIProviderError: LocalizedError {
    case notAvailable(AIProviderType)
    case runFailed(AIProviderType, String)
    case noJokesFound(AIProviderType)
    case allProvidersFailed([AIProviderType: Error])

    var errorDescription: String? {
        switch self {
        case .notAvailable(let provider):
            return "\(provider.displayName) isn't available on this device."
        case .runFailed(let provider, let msg):
            return "\(provider.displayName) error: \(msg)"
        case .noJokesFound(let provider):
            return "\(provider.displayName) found no jokes in the provided content."
        case .allProvidersFailed:
            return "GagGrabber couldn't read this document on-device. Try a different file."
        }
    }
}

// MARK: - Provider Protocol

/// Any on-device service that can extract jokes from text.
protocol AIJokeExtractionProvider {
    var providerType: AIProviderType { get }

    /// True when the underlying model/framework is available on this device.
    func isConfigured() -> Bool

    /// Extract jokes from raw text.
    func extractJokes(from text: String) async throws -> [AIExtractedJoke]

    /// Extract jokes with user-supplied hints that configure preprocessing,
    /// split thresholds, and AI instructions.
    func extractJokes(from text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke]
}

extension AIJokeExtractionProvider {
    /// Hints-aware entry point the manager calls. Providers that benefit from
    /// structured hints (e.g. the embedding segmenter tuning its split
    /// threshold, or the Apple on-device model putting hints in its
    /// instructions slot) override this directly.
    func extractJokes(from text: String, hints: ExtractionHints) async throws -> [AIExtractedJoke] {
        try await extractJokes(from: text)
    }
}

// MARK: - AI Extracted Joke Model

/// A joke fragment returned by an on-device extractor.
struct AIExtractedJoke: Codable, Identifiable, Equatable {
    let id: UUID
    let jokeText: String
    let humorMechanism: String?
    let confidence: Float
    let explanation: String?
    let title: String?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case jokeText
        case humorMechanism
        case confidence
        case explanation
        case title
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.jokeText = try container.decode(String.self, forKey: .jokeText)
        self.humorMechanism = try container.decodeIfPresent(String.self, forKey: .humorMechanism)
        self.confidence = try container.decode(Float.self, forKey: .confidence)
        self.explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jokeText, forKey: .jokeText)
        try container.encodeIfPresent(humorMechanism, forKey: .humorMechanism)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(explanation, forKey: .explanation)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(tags, forKey: .tags)
    }

    init(jokeText: String, humorMechanism: String? = nil, confidence: Float = 0.5, explanation: String? = nil, title: String? = nil, tags: [String] = []) {
        self.id = UUID()
        self.jokeText = jokeText
        self.humorMechanism = humorMechanism
        self.confidence = confidence
        self.explanation = explanation
        self.title = title
        self.tags = tags
    }

    static func == (lhs: AIExtractedJoke, rhs: AIExtractedJoke) -> Bool {
        lhs.jokeText == rhs.jokeText &&
        lhs.humorMechanism == rhs.humorMechanism &&
        abs(lhs.confidence - rhs.confidence) < 0.01 &&
        lhs.explanation == rhs.explanation &&
        lhs.title == rhs.title &&
        lhs.tags == rhs.tags
    }

    /// Convert this extracted joke to an ImportedJoke for the pipeline.
    func toImportedJoke(
        sourceFile: String,
        pageNumber: Int,
        orderInFile: Int,
        importTimestamp: Date
    ) -> ImportedJoke {
        let importConfidence: ImportConfidence = {
            if confidence >= 0.8 { return .high }
            else if confidence >= 0.6 { return .medium }
            else { return .low }
        }()

        let factors = ConfidenceFactors(
            extractionQuality:     confidence,
            structuralCleanliness: 0.7,
            titleDetection:        (title != nil) ? 0.8 : 0.3,
            boundaryClarity:       0.75,
            ocrConfidence:         1.0
        )

        let metadata = ImportSourceMetadata(
            fileName:        sourceFile,
            pageNumber:      pageNumber,
            orderInPage:     orderInFile,
            orderInFile:     orderInFile,
            boundingBox:     nil,
            importTimestamp: importTimestamp
        )

        let validationResult: ValidationResult = {
            if confidence >= 0.6 {
                return .singleJoke
            } else {
                let reason = explanation ?? "GagGrabber confidence \(String(format: "%.0f%%", confidence * 100)) — please verify"
                return .requiresReview(reasons: [reason])
            }
        }()

        // Strip leading numbered-list markers (e.g. "1.", "2)") that the
        // model may carry over from the source document.
        let cleanedText = HybridGagGrabber.stripLeadingNumber(jokeText)

        return ImportedJoke(
            title:            title,
            body:             cleanedText,
            rawSourceText:    jokeText,
            tags:             tags,
            confidence:       importConfidence,
            confidenceFactors: factors,
            sourceMetadata:   metadata,
            validationResult: validationResult,
            extractionMethod: .documentText
        )
    }
}
