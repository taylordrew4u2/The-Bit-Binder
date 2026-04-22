import Foundation

/// BitBuddy backend factory.
///
/// Prefers on-device LLM backends in this order:
/// 1) Apple Intelligence (FoundationModels, iOS 26+) — smartest, no download
/// 2) MLX Qwen 2.5 3B
/// 3) Hugging Face CoreML (swift-transformers)
/// 4) Local rule-based fallback
enum BitBuddyBackendFactory {
    static func makeBackend() -> BitBuddyBackend {
        if AppleIntelligenceBitBuddyService.shared.isAvailable {
            return AppleIntelligenceBitBuddyService.shared
        }

        if MLXBitBuddyService.shared.isAvailable {
            return MLXBitBuddyService.shared
        }

        if HuggingFaceTransformersBitBuddyService.shared.isAvailable {
            return HuggingFaceTransformersBitBuddyService.shared
        }

        return LocalFallbackBitBuddyService.shared
    }
}
