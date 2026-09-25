import Combine
import Foundation

/// Foreground intents can arrive before SwiftUI has attached its first scene.
/// Queue them until the scene is ready; a later command never replaces open work.
@MainActor
final class SiriNavigationRouter: ObservableObject {
    enum Destination: Equatable, Sendable {
        case findJokes(query: String)
        case sets
    }

    struct Request: Identifiable, Equatable {
        let id = UUID()
        let destination: Destination
    }

    static let shared = SiriNavigationRouter()
    @Published private(set) var requests: [Request] = []

    func open(_ destination: Destination) {
        requests.append(Request(destination: destination))
    }

    func finish(_ requestID: UUID) {
        requests.removeAll { $0.id == requestID }
    }
}
