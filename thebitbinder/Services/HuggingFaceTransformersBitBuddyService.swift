import Foundation

#if canImport(Models) && canImport(Tokenizers) && canImport(Generation) && canImport(CoreML)
import CoreML
import Generation
import Models
import Tokenizers
#endif

/// Optional local Core ML backend powered by Hugging Face swift-transformers.
///
/// This backend requires a compiled Core ML model path in UserDefaults:
/// `bitbuddy.hf.coremlModelPath` (supports `.mlmodelc`, `.mlmodel`, `.mlpackage`).
final class HuggingFaceTransformersBitBuddyService: BitBuddyBackend {
    static let shared = HuggingFaceTransformersBitBuddyService()

    private enum DefaultsKey {
        static let modelPath = "bitbuddy.hf.coremlModelPath"
        static let tokenizerRepo = "bitbuddy.hf.tokenizerRepo"
    }

    private init() {}

    var backendName: String {
#if canImport(Models) && canImport(Tokenizers) && canImport(Generation) && canImport(CoreML)
        "Hugging Face CoreML (Local)"
#else
        "Hugging Face CoreML (Unavailable)"
#endif
    }

    var isAvailable: Bool {
#if canImport(Models) && canImport(Tokenizers) && canImport(Generation) && canImport(CoreML)
        if #available(iOS 18.0, *) {
            return Self.configuredModelPath() != nil
        }
        return false
#else
        return false
#endif
    }

    var supportsStreaming: Bool { false }

    func preload() async {
#if canImport(Models) && canImport(Tokenizers) && canImport(Generation) && canImport(CoreML)
        if #available(iOS 18.0, *) {
            _ = try? await HFTransformersRuntime.shared.prepareModelIfNeeded()
        }
#endif
    }

    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
#if canImport(Models) && canImport(Tokenizers) && canImport(Generation) && canImport(CoreML)
        guard isAvailable else {
            throw BitBuddyBackendError.unavailable
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Give me a prompt and I can help with jokes, rewrites, brainstorming, and general chat."
        }

        let prompt = buildPrompt(message: trimmed, session: session, dataContext: dataContext)
        do {
            guard #available(iOS 18.0, *) else {
                throw BitBuddyBackendError.unavailable
            }
            let output = try await HFTransformersRuntime.shared.generate(prompt: prompt)
            let cleaned = sanitizeModelOutput(output)
            if cleaned.isEmpty {
                throw BitBuddyBackendError.generationFailed
            }
            return cleaned
        } catch {
            throw BitBuddyBackendError.generationFailed
        }
#else
        throw BitBuddyBackendError.unavailable
#endif
    }

    private func buildPrompt(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) -> String {
        let recentTurns = session.turns.suffix(4)
        let history = recentTurns.map { turn in
            let role: String
            switch turn.role {
            case .system: role = "system"
            case .user: role = "user"
            case .assistant: role = "assistant"
            }
            return "\(role): \(turn.text)"
        }.joined(separator: "\n")

        let contextPrompt = BitBuddyResources.buildLLMPrompt(message: message, dataContext: dataContext)

        return """
        \(BitBuddyResources.llmSystemInstructions)

        Conversation:
        \(history)

        \(contextPrompt)
        Assistant:
        """
    }

    private func sanitizeModelOutput(_ output: String) -> String {
        output
            .replacingOccurrences(of: "</s>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func configuredModelPath() -> String? {
        let path = UserDefaults.standard.string(forKey: DefaultsKey.modelPath)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    fileprivate static func configuredTokenizerRepo() -> String {
        let repo = UserDefaults.standard.string(forKey: DefaultsKey.tokenizerRepo)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let repo, !repo.isEmpty {
            return repo
        }
        return "microsoft/Phi-3-mini-4k-instruct"
    }
}

#if canImport(Models) && canImport(Tokenizers) && canImport(Generation) && canImport(CoreML)
@available(iOS 18.0, *)
private actor HFTransformersRuntime {
    static let shared = HFTransformersRuntime()

    private var model: LanguageModel?
    private var tokenizer: Tokenizer?

    func prepareModelIfNeeded() async throws {
        guard model == nil else { return }

        guard let configuredPath = HuggingFaceTransformersBitBuddyService.configuredModelPath() else {
            throw BitBuddyBackendError.unavailable
        }

        let modelURL = try compiledModelURL(from: configuredPath)
        let tokenizer = try await AutoTokenizer.from(
            pretrained: HuggingFaceTransformersBitBuddyService.configuredTokenizerRepo()
        )

        let loaded = try LanguageModel.loadCompiled(
            url: modelURL,
            computeUnits: .cpuAndGPU,
            tokenizer: tokenizer
        )

        self.model = loaded
        self.tokenizer = tokenizer
    }

    func generate(prompt: String) async throws -> String {
        try await prepareModelIfNeeded()
        guard let model else {
            throw BitBuddyBackendError.generationFailed
        }

        var config = model.defaultGenerationConfig
        config.maxNewTokens = 160
        config.doSample = true
        config.temperature = 0.7
        config.topP = 0.9

        return try await model.generate(config: config, prompt: prompt)
    }

    private func compiledModelURL(from path: String) throws -> URL {
        let sourceURL = URL(fileURLWithPath: path)
        let lower = sourceURL.pathExtension.lowercased()

        if lower == "mlmodelc" {
            return sourceURL
        }

        if lower == "mlmodel" || lower == "mlpackage" {
            return try MLModel.compileModel(at: sourceURL)
        }

        throw BitBuddyBackendError.unavailable
    }
}
#endif
