//
//  MLXSharedRuntime.swift
//  thebitbinder
//
//  Shared on-device MLX model runtime used by both BitBuddy chat
//  and AutoOrganize categorization. Loads the model once into a
//  single ModelContainer so it isn't duplicated in memory.
//

import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon

actor MLXSharedRuntime {
    static let shared = MLXSharedRuntime()

    private static let modelConfig = ModelConfiguration(
        id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
        defaultPrompt: "Help me improve this joke.",
        extraEOSTokens: ["<|im_end|>"]
    )

    private var container: ModelContainer?
    private var chatSession: ChatSession?
    private var activeConversationId: String?

    private(set) var isModelLoaded: Bool = false

    /// Tracks whether the model failed to load (e.g. network timeout downloading
    /// from HuggingFace). Once set, all subsequent load attempts are skipped for
    /// the rest of the app session to avoid repeated timeout delays.
    private var loadFailed: Bool = false

    // MARK: - Model Loading

    /// How long to wait for the model to load before giving up.
    /// A locally-cached model loads in ~2-3s; if it takes longer the model
    /// files aren't on disk and we'd be waiting for a HuggingFace download.
    private static let loadTimeout: TimeInterval = 8

    /// Maximum number of load attempts before permanently disabling MLX for
    /// this session. The first attempt uses `loadTimeout`; retries double it.
    private static let maxLoadAttempts = 2

    @discardableResult
    func prepareModelIfNeeded() async throws -> ModelContainer {
        if let container { return container }
        if loadFailed { throw MLXRuntimeError.modelLoadPreviouslyFailed }

        var lastError: Error?
        for attempt in 1...Self.maxLoadAttempts {
            let timeout = Self.loadTimeout * Double(attempt) // 8s, then 16s
            do {
                let loaded = try await withThrowingTimeout(seconds: timeout) {
                    try await LLMModelFactory.shared.loadContainer(
                        configuration: Self.modelConfig
                    )
                }
                container = loaded
                isModelLoaded = true
                return loaded
            } catch {
                lastError = error
                #if DEBUG
                print("[MLXSharedRuntime] Load attempt \(attempt)/\(Self.maxLoadAttempts) failed (timeout \(Int(timeout))s): \(error.localizedDescription)")
                #endif
            }
        }

        // All attempts exhausted — mark permanently failed for this session
        loadFailed = true
        #if DEBUG
        print("[MLXSharedRuntime] Model load failed after \(Self.maxLoadAttempts) attempts — disabling MLX for this session")
        #endif
        throw lastError ?? MLXRuntimeError.modelLoadTimedOut
    }

    /// Runs `operation` with a wall-clock deadline. If the operation doesn't
    /// finish in time the task is cancelled and an error is thrown.
    private func withThrowingTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MLXRuntimeError.modelLoadTimedOut
            }
            // First result wins — the other task is cancelled.
            guard let result = try await group.next() else {
                throw MLXRuntimeError.modelLoadTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Chat (multi-turn, used by BitBuddy)

    func generateChatResponse(
        _ prompt: String,
        conversationId: String,
        instructions: String
    ) async throws -> String {
        let c = try await prepareModelIfNeeded()

        if chatSession == nil || activeConversationId != conversationId {
            chatSession = ChatSession(c, instructions: instructions)
            activeConversationId = conversationId
        }

        guard let chatSession else {
            throw BitBuddyBackendError.generationFailed
        }
        return try await chatSession.respond(to: prompt)
    }

    func resetChat() {
        chatSession?.clear()
        activeConversationId = nil
    }

    // MARK: - Single-shot (used by AutoOrganize)

    func generateSingleShot(
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        let c = try await prepareModelIfNeeded()
        let session = ChatSession(c, instructions: systemPrompt)
        return try await session.respond(to: userPrompt)
    }
}

enum MLXRuntimeError: Error, LocalizedError {
    case modelLoadPreviouslyFailed
    case modelLoadTimedOut

    var errorDescription: String? {
        switch self {
        case .modelLoadPreviouslyFailed:
            return "Model failed to load earlier in this session. Restart the app to retry."
        case .modelLoadTimedOut:
            return "Model not available locally — download it first via BitBuddy chat."
        }
    }
}
#endif
