//
//  AuthService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/20/26.
//

import Foundation
import Combine

/// Manages user preferences and basic app state (no external authentication required)
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var isAuthenticated = true
    
    private let kvStore = iCloudKeyValueStore.shared
    
    private init() {}
    
    // MARK: - Auth Stubs (no external auth needed)
    
    /// Always succeeds — no external auth provider required
    func ensureAuthenticated() async throws {
        isAuthenticated = true
    }
    
    // MARK: - User ID (for local data separation)
    
    var userId: String {
        if let storedId = kvStore.string(forKey: SyncedKeys.userId) {
            return storedId
        } else {
            let newId = UUID().uuidString
            kvStore.set(newId, forKey: SyncedKeys.userId)
            return newId
        }
    }
}
