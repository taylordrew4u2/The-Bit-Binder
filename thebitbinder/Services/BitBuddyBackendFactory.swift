import Foundation

/// BitBuddy backend factory.
///
/// Prefers on-device LLM backends in this order:
/// 1) MLX Phi-3
/// 2) Hugging Face CoreML (swift-transformers)
/// 3) Local rule-based fallback
enum BitBuddyBackendFactory {
    static func makeBackend() -> BitBuddyBackend {
        if MLXBitBuddyService.shared.isAvailable {
            return MLXBitBuddyService.shared
        }

        if HuggingFaceTransformersBitBuddyService.shared.isAvailable {
            return HuggingFaceTransformersBitBuddyService.shared
        }

        return LocalFallbackBitBuddyService.shared
    }
}
