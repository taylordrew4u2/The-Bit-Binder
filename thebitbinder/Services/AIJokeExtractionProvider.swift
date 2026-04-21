//
//  AIJokeExtractionProvider.swift
//  thebitbinder
//
//  Protocol + concrete providers for multi-provider joke extraction.
//  Supports OpenAI, Arcee, and OpenRouter with automatic fallback.
//

import Foundation
import UIKit

// MARK: - Provider Identity

/// Every extraction provider available for joke extraction.
enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case appleOnDevice = "AppleOnDevice"
    case openAI        = "OpenAI"
    case arceeAI       = "ArceeAI"
    case openRouter    = "OpenRouter"

    var id: String { rawValue }

    /// True for providers that run entirely on-device and need no API key,
    /// no network, and no user setup. Cloud providers return `false`.
    var isOnDevice: Bool {
        self == .appleOnDevice
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .appleOnDevice: return "On-Device (Apple)"
        case .openAI:        return "OpenAI"
        case .arceeAI:       return "Arcee"
        case .openRouter:    return "OpenRouter"
        }
    }

    /// Model used by default for each provider.
    ///   Free OpenRouter models rotate frequently. If a model 404s,
    /// update it here. `openrouter/free` auto-routes to whatever is live.
    var defaultModel: String {
        switch self {
        case .appleOnDevice: return "Apple Foundation Model"
        case .openAI:        return "gpt-4o-mini"
        case .arceeAI:       return "mistralai/mistral-small-3.1-24b-instruct:free"
        case .openRouter:    return "meta-llama/llama-4-scout:free"
        }
    }

    /// Fallback free models to try if the default 404s or is unavailable.
    /// Each slot tries its own list before the manager moves to the next provider.
    var fallbackModels: [String] {
        switch self {
        case .appleOnDevice: return []
        case .openAI:        return []
        case .arceeAI:       return ["google/gemma-3-27b-it:free", "openrouter/free"]
        case .openRouter:    return ["google/gemma-3-12b-it:free", "openrouter/free"]
        }
    }

    /// Where users can get a free API key. `nil` for providers that don't
    /// need one (the on-device model runs locally).
    var keySignupURL: URL? {
        let raw: String
        switch self {
        case .appleOnDevice: return nil
        case .openAI:        raw = "https://platform.openai.com/api-keys"
        case .arceeAI:       raw = "https://openrouter.ai/keys"
        case .openRouter:    raw = "https://openrouter.ai/keys"
        }
        guard let url = URL(string: raw) else {
            assertionFailure("keySignupURL has an invalid hardcoded URL: \(raw)")
            return URL(string: "https://openrouter.ai/keys")
        }
        return url
    }

    /// SF Symbol for the provider
    var icon: String {
        switch self {
        case .appleOnDevice: return "cpu"
        case .openAI:        return "brain.head.profile"
        case .arceeAI:       return "triangle.fill"
        case .openRouter:    return "arrow.triangle.branch"
        }
    }

    /// The plist key name for this provider's API key. Empty string for
    /// on-device providers that don't use a key.
    var plistKey: String {
        switch self {
        case .appleOnDevice: return ""
        case .openAI:        return "OPENAI_API_KEY"
        case .arceeAI:       return "ARCEEAI_API_KEY"
        case .openRouter:    return "OPENROUTER_API_KEY"
        }
    }

    /// The per-provider plist file name (without extension). Empty string
    /// for on-device providers.
    var secretsPlistName: String {
        switch self {
        case .appleOnDevice: return ""
        case .openAI:        return "OpenAI-Secrets"
        case .arceeAI:       return "ArceeAI-Secrets"
        case .openRouter:    return "OpenRouter-Secrets"
        }
    }

    /// Keychain account key for storing user-entered API keys. Empty string
    /// for on-device providers.
    var keychainKey: String {
        switch self {
        case .appleOnDevice: return ""
        case .openAI:        return "ai_key_openai"
        case .arceeAI:       return "ai_key_arceeai"
        case .openRouter:    return "ai_key_openrouter"
        }
    }

    /// Legacy UserDefaults key (for migration only).
    var userDefaultsKey: String { keychainKey }
}

// MARK: - Provider Errors

enum AIProviderError: LocalizedError {
    case keyNotConfigured(AIProviderType)
    case rateLimited(AIProviderType, retryAfterSeconds: Int?)
    case apiError(AIProviderType, String)
    case noJokesFound(AIProviderType)
    case allProvidersFailed([AIProviderType: Error])

    var errorDescription: String? {
        switch self {
        case .keyNotConfigured(let provider):
            return "\(provider.displayName) is not configured. Add your API key in Settings  API Keys."
        case .rateLimited(_, let retry):
            let retryStr = retry.map { " Try again in \($0 / 60) minutes." } ?? " Try again in a bit."
            return "GagGrabber needs a breather.\(retryStr)"
        case .apiError(let provider, let msg):
            return "\(provider.displayName) error: \(msg)"
        case .noJokesFound(let provider):
            return "\(provider.displayName) found no jokes in the provided content."
        case .allProvidersFailed(_):
            return "GagGrabber couldn't reach any of its sources. Check your network and API keys in Settings."
        }
    }
}

// MARK: - Provider Protocol

/// Any AI service that can extract jokes from text.
protocol AIJokeExtractionProvider {
    var providerType: AIProviderType { get }

    /// Whether this provider needs network access to run. Cloud providers are
    /// `true`; on-device providers (Apple Foundation Models) are `false`.
    /// Default: `true` so existing cloud providers don't need to override.
    var requiresNetwork: Bool { get }

    /// Check if this provider is configured (has a valid API key, or the
    /// on-device model is available on this device).
    func isConfigured() -> Bool

    /// Extract jokes from raw text. Throws `AIProviderError` on failure.
    func extractJokes(from text: String) async throws -> [AIExtractedJoke]
}

extension AIJokeExtractionProvider {
    var requiresNetwork: Bool { true }
}

// MARK: - Shared Prompt

enum JokeExtractionPrompt {
    static func textPrompt(for text: String) -> String {
        // NO truncation — the entire file content is sent verbatim.
        // Every word must be accounted for in the response.
        return """
        You are a comedy-writing assistant reviewing a stand-up comedian's file.
        Your job is to return EVERY piece of text from the file — not just the obvious jokes.

        ABSOLUTE RULES:
        1. DO NOT drop, skip, summarise, or omit any text. Every sentence, phrase, or
           fragment from the file must appear as its own entry in your response.
        2. Give each entry a confidence score:
           - 0.8–1.0  clearly a joke / bit / punchline
           - 0.5–0.79  possibly a joke, premise, tag, or crowd-work line
           - 0.0–0.49  not a joke (title, note, header, metadata, random word, etc.)
             but STILL include it — the user will decide.
        3. Never combine unrelated material into one entry.
        4. Split on blank lines, "---", "***", "===", "//", "NEXT JOKE", "NEW BIT",
           numbered items (1., 2., #1, Joke 1:), and bullet points.
        5. When in doubt, SPLIT into smaller entries rather than merging.
        6. Preserve the original wording exactly — do not paraphrase or clean up.
        7. If the text begins with [USER FORMAT HINT: ...], use that hint to understand
           how the document is structured (e.g. "one joke per line", "numbered 1-50",
           "separated by blank lines"). This is the user telling you how they wrote it.
           Do NOT include the hint itself as a joke entry.

        Return ONLY a valid JSON array with NO markdown fences and NO extra text:
        [{"jokeText":"<exact text>","humorMechanism":"<type or null>","confidence":<0.0-1.0>,"explanation":"<why this score, or null>","title":"<detected title or null>","tags":["tag1"]}]

        If the file is completely empty: []

        --- FILE CONTENT (process every word) ---
        \(text)
        """
    }

    /// Parse the raw string response into `[AIExtractedJoke]`.
    ///
    /// Handles the most common model output shapes in order:
    ///  1. Markdown code fences (```json … ```)
    ///  2. JSON object wrapper — `{"jokes": [...]}` (the canonical shape from
    ///     OpenAI's `json_schema` structured outputs, which require a root object)
    ///  3. Leading/trailing prose around the array (free-text models that ignore
    ///     system prompts)
    ///  4. Truncated arrays caused by `finish_reason=length` — heals the last
    ///     incomplete object and closes the array so we keep all complete entries
    ///
    /// - Parameters:
    ///   - raw: The raw string content from the model's message.
    ///   - provider: Used only to construct error messages.
    static func parseResponse(_ raw: String, provider: AIProviderType = .openAI) throws -> [AIExtractedJoke] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        //  1. Strip markdown code fences 
        // Handles ```json\n...\n``` and ```\n...\n```
        if s.hasPrefix("```") {
            var lines = s.components(separatedBy: .newlines)
            // Drop opening fence line
            lines.removeFirst()
            // Drop trailing ``` line (if present)
            if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
                lines.removeLast()
            }
            s = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        //  2. Unwrap JSON object wrapper 
        // OpenAI's json_schema structured-outputs mode requires a root JSON object.
        // Our schema enforces { "jokes": [...] }.  Arcee/OpenRouter free-text models
        // may also wrap spontaneously with keys like "jokes", "data", "results", etc.
        // Extract the first array value from the object when the top level is an object.
        if s.hasPrefix("{") {
            if let data = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Prefer "jokes" key first (our canonical schema key), then any array value.
                let jokeArray: [[String: Any]]? = (obj["jokes"] as? [[String: Any]])
                    ?? obj.values.compactMap { $0 as? [[String: Any]] }.first
                if let arr = jokeArray,
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let arrString = String(data: arrData, encoding: .utf8) {
                    s = arrString
                }
            }
        }

        //  3. Extract array bounds (strip leading/trailing prose) 
        if let start = s.firstIndex(of: "["),
           let end   = s.lastIndex(of: "]"),
           start <= end {
            s = String(s[start...end])
        }

        //  4. First parse attempt — clean JSON 
        if let data = s.data(using: .utf8),
           let jokes = try? JSONDecoder().decode([AIExtractedJoke].self, from: data) {
            return jokes
        }

        //  5. Truncation repair 
        // When finish_reason=length the array is cut off mid-object, e.g.:
        //   [..., {"jokeText":"text", "confidence":0.
        // Strategy: find the last complete object (ends with }) inside the array,
        // close the array after it, and decode whatever we recovered.
        let repaired = repairTruncatedArray(s)
        if let data = repaired.data(using: .utf8),
           let jokes = try? JSONDecoder().decode([AIExtractedJoke].self, from: data) {
            print(" [\(provider.displayName)] Recovered \(jokes.count) joke(s) from truncated response")
            return jokes
        }

        //  6. Hard failure — nothing worked 
        let preview = String(raw.prefix(200))
        throw AIProviderError.apiError(
            provider,
            "Could not parse JSON response. Preview: \(preview)"
        )
    }

    /// Attempt to recover a valid JSON array from a string that was cut off
    /// mid-element. Finds the last `}` that closes a complete top-level object
    /// inside the array and wraps everything up to that point as `[...]`.
    private static func repairTruncatedArray(_ s: String) -> String {
        // Find the outermost array start
        guard let arrayStart = s.firstIndex(of: "[") else { return "[]" }
        let inner = String(s[arrayStart...])

        // Walk backwards from the end to find the last complete object boundary
        var depth = 0
        var lastCompleteObjectEnd: String.Index? = nil
        var inString = false
        var escape = false

        for idx in inner.indices {
            let ch = inner[idx]
            if escape { escape = false; continue }
            if ch == "\\" && inString { escape = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { lastCompleteObjectEnd = idx }
            }
        }

        guard let end = lastCompleteObjectEnd else { return "[]" }
        let recovered = "[" + String(inner[inner.index(after: inner.startIndex)...end]) + "]"
        return recovered
    }
}

// MARK: - API Key Loader (multi-provider)

enum AIKeyLoader {
    /// Loads the API key for a given provider.
    /// Checks: 1) Keychain (user-entered), 2) Per-provider plist, 3) Secrets.plist, 4) environment variable.
    /// Automatically migrates legacy keys from UserDefaults to Keychain on first access.
    static func loadKey(for provider: AIProviderType) -> String? {
        // On-device providers don't have keys — short-circuit so we don't
        // read/write empty-string Keychain accounts.
        if provider.isOnDevice { return nil }

        // 1a. Migrate from UserDefaults to Keychain if needed
        if let legacyKey = UserDefaults.standard.string(forKey: provider.userDefaultsKey),
           !legacyKey.isEmpty {
            KeychainHelper.save(legacyKey, forKey: provider.keychainKey)
            UserDefaults.standard.removeObject(forKey: provider.userDefaultsKey)
            print(" [AIKeyLoader] Migrated \(provider.displayName) key from UserDefaults to Keychain")
        }
        
        // 1b. User-entered key (stored in Keychain)
        if let key = KeychainHelper.load(forKey: provider.keychainKey),
           !key.isEmpty {
            print(" [AIKeyLoader] \(provider.displayName): loaded key from Keychain")
            return key
        }

        // 2. Per-provider plist (e.g., OpenAI-Secrets.plist, ArceeAI-Secrets.plist)
        if let url = Bundle.main.url(forResource: provider.secretsPlistName, withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict[provider.plistKey] as? String,
           !key.isEmpty,
           !key.hasPrefix("YOUR_") {
            print(" [AIKeyLoader] \(provider.displayName): loaded key from \(provider.secretsPlistName).plist")
            return key
        }

        // 3. Main Secrets.plist (fallback for all providers)
        if provider.secretsPlistName != "Secrets",
           let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict[provider.plistKey] as? String,
           !key.isEmpty,
           !key.hasPrefix("YOUR_") {
            print(" [AIKeyLoader] \(provider.displayName): loaded key from Secrets.plist fallback")
            return key
        }

        // 4. Environment variable
        if let key = ProcessInfo.processInfo.environment[provider.plistKey],
           !key.isEmpty {
            print(" [AIKeyLoader] \(provider.displayName): loaded key from environment variable \(provider.plistKey)")
            return key
        }

        print(" [AIKeyLoader] \(provider.displayName): no API key found (checked Keychain, \(provider.secretsPlistName).plist, Secrets.plist, env)")
        return nil
    }

    /// Save a user-entered API key securely in the Keychain.
    static func saveKey(_ key: String, for provider: AIProviderType) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(forKey: provider.keychainKey)
        } else {
            KeychainHelper.save(trimmed, forKey: provider.keychainKey)
        }
        // Clean up any legacy UserDefaults entry
        UserDefaults.standard.removeObject(forKey: provider.userDefaultsKey)
    }

    /// Clear the user-entered API key from the Keychain.
    static func clearKey(for provider: AIProviderType) {
        KeychainHelper.delete(forKey: provider.keychainKey)
        UserDefaults.standard.removeObject(forKey: provider.userDefaultsKey)
    }

    /// Returns all providers that have a configured key.
    static func configuredProviders() -> [AIProviderType] {
        AIProviderType.allCases.filter { loadKey(for: $0) != nil }
    }
}

// MARK: - AI Extracted Joke Model

/// Represents a joke extracted by an AI provider (OpenAI, Arcee, OpenRouter, etc.)
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
    
    /// Convert this AI-extracted joke to an ImportedJoke for the pipeline
    func toImportedJoke(
        sourceFile: String,
        pageNumber: Int,
        orderInFile: Int,
        importTimestamp: Date
    ) -> ImportedJoke {
        //  Confidence mapping 
        // The AI returns a Float 0.0–1.0. We map it to three ImportConfidence
        // tiers which control whether the joke auto-saves or goes to review:
        //
        //    0.8  (.high)    validationResult: .singleJoke
        //                       needsReview = false  auto-saved
        //   0.6–0.79 (.medium)  validationResult: .singleJoke
        //                       needsReview = false  auto-saved (correct: medium
        //                       confidence is the AI saying "pretty sure it's a joke")
        //   < 0.6  (.low)     validationResult: .requiresReview
        //                       needsReview = true   goes to review queue
        //
        // Low-confidence items (headers, notes, random words — AI scores < 0.5)
        // always land in the review queue so the user sees every fragment.

        let importConfidence: ImportConfidence = {
            if confidence >= 0.8 { return .high }
            else if confidence >= 0.6 { return .medium }
            else { return .low }
        }()

        let factors = ConfidenceFactors(
            extractionQuality:       confidence,
            structuralCleanliness:   0.7,
            titleDetection:          (title != nil) ? 0.8 : 0.3,
            boundaryClarity:         0.75,
            ocrConfidence:           1.0   // AI works on text, not raw images
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
                // AI confidence < 0.6 means it's uncertain — force user review.
                let reason = explanation ?? "GagGrabber confidence \(String(format: "%.0f%%", confidence * 100)) — please verify"
                return .requiresReview(reasons: [reason])
            }
        }()

        return ImportedJoke(
            title:            title,
            body:             jokeText,
            rawSourceText:    jokeText,
            tags:             tags,
            confidence:       importConfidence,
            confidenceFactors: factors,
            sourceMetadata:   metadata,
            validationResult: validationResult,
            // AI extraction works on text extracted from the file, not raw image pixels.
            // .documentText is correct regardless of whether the source was a PDF, TXT, or DOC.
            extractionMethod: .documentText
        )
    }
}
