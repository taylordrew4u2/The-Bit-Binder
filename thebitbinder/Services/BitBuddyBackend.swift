import Foundation
import SwiftData

struct BitBuddyTurn: Sendable, Codable {
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }
    
    let role: Role
    let text: String
}

struct BitBuddySessionSnapshot: Sendable {
    let conversationId: String
    let turns: [BitBuddyTurn]
}

struct BitBuddyJokeSummary: Sendable, Codable {
    let id: UUID
    let title: String
    let content: String
    let tags: [String]
    let dateCreated: Date
}

struct BitBuddyDataContext: Sendable {
    var userName: String = "Comedian"
    var recentJokes: [BitBuddyJokeSummary] = []
    var focusedJoke: BitBuddyJokeSummary?

    // Intent routing context (populated by BitBuddyIntentRouter)
    var routedIntent: BitBuddyRouteResult?
    /// Section the assistant should treat as "active" for this turn. This is
    /// either the section the user's intent routed to, or — if no intent
    /// matched — the page they're currently viewing.
    var activeSection: BitBuddySection?
    /// The literal page the user is on right now. Set independently of intent
    /// routing so backends can answer "where am I?" / "help me here" correctly.
    var currentPage: BitBuddySection?
    var isRoastMode: Bool = false
}

// MARK: - Structured Action Response

/// An action BitBuddy wants the app to perform.
struct BitBuddyAction: Sendable, Codable {
    let type: String              // matches a BitBuddyIntent.id
    let parameters: [String: String]

    init(type: String, parameters: [String: String] = [:]) {
        self.type = type
        self.parameters = parameters
    }
}

/// The full structured response from any backend.
struct BitBuddyStructuredResponse: Sendable {
    let text: String
    let actions: [BitBuddyAction]
    let routedSection: BitBuddySection?

    init(text: String, actions: [BitBuddyAction] = [], routedSection: BitBuddySection? = nil) {
        self.text = text
        self.actions = actions
        self.routedSection = routedSection
    }
}

protocol BitBuddyBackend: Sendable {
    var backendName: String { get }
    var isAvailable: Bool { get }
    var supportsStreaming: Bool { get }
    
    func preload() async
    
    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String
}

extension BitBuddyBackend {
    func preload() async {}
}

enum BitBuddyBackendError: LocalizedError {
    case unavailable
    case generationFailed
    case invalidStructuredResponse
    
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "BitBuddy isn't available on this device right now."
        case .generationFailed:
            return "BitBuddy couldn't generate a response."
        case .invalidStructuredResponse:
            return "BitBuddy returned an invalid structured response."
        }
    }
}
