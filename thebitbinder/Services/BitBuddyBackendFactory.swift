import Foundation

/// BitBuddy backend factory.
///
final class NoBitBuddyBackend: BitBuddyBackend {
    static let shared = NoBitBuddyBackend()
    private init() {}
    var backendName: String { "None" }
    var isAvailable: Bool { true }
    var supportsStreaming: Bool { false }
    func send(message: String, session: BitBuddySessionSnapshot, dataContext: BitBuddyDataContext) async throws -> String {
        return "No writing partner is available right now. On-device models aren't ready on this device, and no OpenAI fallback key is set in Settings."
    }
}

/// Prefers operational backends in this order:
/// 1) Apple Intelligence (FoundationModels, iOS 26+) — smartest, no download
/// 2) MLX Qwen 2.5 3B
/// 3) Hugging Face CoreML (swift-transformers)
/// 4) OpenAI (user-provided API key)
/// 5) Local fallback intent-driven chat engine
enum BitBuddyBackendFactory {
    static func makeOperationalBackend() -> BitBuddyBackend {
        if AppleIntelligenceBitBuddyService.shared.isAvailable {
            return AppleIntelligenceBitBuddyService.shared
        }

        if MLXBitBuddyService.shared.isAvailable {
            return MLXBitBuddyService.shared
        }

        if HuggingFaceTransformersBitBuddyService.shared.isAvailable {
            return HuggingFaceTransformersBitBuddyService.shared
        }

        if OpenAIBitBuddyService.shared.isAvailable {
            return OpenAIBitBuddyService.shared
        }

        if LocalFallbackBitBuddyService.shared.isAvailable {
            return LocalFallbackBitBuddyService.shared
        }

        return NoBitBuddyBackend.shared
    }
}
