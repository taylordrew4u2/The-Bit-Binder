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
}

protocol BitBuddyBackend: Sendable {
    var backendName: String { get }
    var isAvailable: Bool { get }
    var supportsStreaming: Bool { get }
    
    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String
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
