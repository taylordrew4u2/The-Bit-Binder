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
        return "No writing partner is available right now. On-device models aren't ready on this device yet."
    }
}

/// Chooses the deterministic command backend for app actions.
/// Freeform writing and factual responses can still use optional LLMs through
/// SocraticGuideBackend, but routed app commands should never depend on a
/// model download, API key, or Apple Intelligence availability.
enum BitBuddyBackendFactory {
    static func makeOperationalBackend() -> BitBuddyBackend {
        if LocalFallbackBitBuddyService.shared.isAvailable {
            return LocalFallbackBitBuddyService.shared
        }

        return NoBitBuddyBackend.shared
    }
}
