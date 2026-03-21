//
//  iCloudKeyValueStore.swift
//  thebitbinder
//
//  Bridges NSUbiquitousKeyValueStore (iCloud KV) with UserDefaults so
//  @AppStorage and manual UserDefaults reads stay in sync across devices.
//

import Foundation
import Combine

/// Keys that should be synced to iCloud across devices
enum SyncedKeys {
    // User preferences
    static let notepadText       = "notepadText"
    static let roastModeEnabled  = "roastModeEnabled"
    static let roastViewMode     = "roastViewMode"
    static let tabOrder          = "tabOrder"
    static let jokesViewMode     = "jokesViewMode"
    static let jokesGridScale    = "jokesGridScale"
    static let roastGridScale    = "roastGridScale"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let expandAllJokes    = "expandAllJokes"
    static let autoOrganizeEnabled = "autoOrganizeEnabled"
    
    // Notification settings
    static let dailyNotificationsEnabled = "dailyNotificationsEnabled"
    static let dailyNotifStartMinute = "dailyNotifStartMinute"
    static let dailyNotifEndMinute = "dailyNotifEndMinute"
    
    // Auth
    static let termsAccepted = "hasAcceptedTerms"
    static let userId = "userId"
    static let lastSyncDate = "lastSyncDate"
    
    /// All keys that should be mirrored between UserDefaults and iCloud KV store
    static let all: [String] = [
        notepadText,
        roastModeEnabled,
        roastViewMode,
        tabOrder,
        jokesViewMode,
        jokesGridScale,
        roastGridScale,
        iCloudSyncEnabled,
        expandAllJokes,
        autoOrganizeEnabled,
        dailyNotificationsEnabled,
        dailyNotifStartMinute,
        dailyNotifEndMinute,
        termsAccepted,
        userId,
        lastSyncDate,
    ]
}

/// Singleton that keeps UserDefaults and NSUbiquitousKeyValueStore in sync.
/// On launch it pulls from iCloud → local. On local writes it pushes to iCloud.
/// Also observes UserDefaults so @AppStorage changes are pushed automatically.
final class iCloudKeyValueStore {
    static let shared = iCloudKeyValueStore()
    
    private let cloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    /// Prevents feedback loops when pulling from cloud triggers local observation
    private var isSyncing = false
    
    /// Performance: Debounce sync operations
    private var syncDebounceWorkItem: DispatchWorkItem?
    
    private init() {
        // Listen for remote changes pushed from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )
        
        // Watch for UserDefaults.standard changes and auto-push synced keys to iCloud
        // This catches @AppStorage writes which bypass our set() methods.
        // NOTE: Must pass `object: local` (not nil) — passing nil observes ALL
        // UserDefaults domains including app group suites, which triggers:
        // "Using kCFPreferencesAnyUser with a container is only allowed for System Containers"
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: local
        )
        
        // Trigger initial sync from iCloud
        cloud.synchronize()
        pullFromCloud()
    }
    
    // MARK: - Write (local → iCloud)
    
    /// Set a string value and push to iCloud
    func set(_ value: String?, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }
    
    /// Set a bool value and push to iCloud
    func set(_ value: Bool, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }
    
    /// Set a Data value and push to iCloud
    func set(_ value: Data, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }
    
    /// Set an integer value and push to iCloud
    func set(_ value: Int, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value as NSNumber, forKey: key)
        cloud.synchronize()
    }
    
    /// Set a double value and push to iCloud
    func set(_ value: Double, forKey key: String) {
        local.set(value, forKey: key)
        cloud.set(value as NSNumber, forKey: key)
        cloud.synchronize()
    }
    
    // MARK: - Read (offline-first: local has priority for immediate access)
    
    func string(forKey key: String) -> String? {
        // Local first for offline support, cloud syncs in background
        local.string(forKey: key) ?? cloud.string(forKey: key)
    }
    
    func bool(forKey key: String) -> Bool {
        // Local first for offline support
        local.bool(forKey: key)
    }
    
    func data(forKey key: String) -> Data? {
        local.data(forKey: key) ?? cloud.data(forKey: key)
    }
    
    func integer(forKey key: String) -> Int {
        local.integer(forKey: key)
    }
    
    func double(forKey key: String) -> Double {
        local.double(forKey: key)
    }
    
    // MARK: - Auto-push on UserDefaults change
    
    /// Called whenever ANY UserDefaults key changes (including @AppStorage)
    @objc private func defaultsDidChange() {
        guard !isSyncing else { return }  // Don't push back what we just pulled
        
        // Performance: Debounce sync operations to prevent excessive iCloud calls
        syncDebounceWorkItem?.cancel()
        syncDebounceWorkItem = DispatchWorkItem { [weak self] in
            self?.performSyncToCloud()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: syncDebounceWorkItem!)
    }
    
    /// Performs the actual sync to iCloud (debounced)
    private func performSyncToCloud() {
        guard !isSyncing else { return }
        
        var changed = false
        for key in SyncedKeys.all {
            let localValue = local.object(forKey: key)
            let cloudValue = cloud.object(forKey: key)
            
            // Compare and push if different
            if !valuesEqual(localValue, cloudValue) {
                if let val = localValue {
                    cloud.set(val, forKey: key)
                } else {
                    cloud.removeObject(forKey: key)
                }
                changed = true
            }
        }
        
        if changed {
            cloud.synchronize()
        }
    }
    
    /// Simple equality check for plist-compatible values
    private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a as String, b as String): return a == b
        case let (a as Bool, b as Bool): return a == b
        case let (a as Int, b as Int): return a == b
        case let (a as Double, b as Double): return a == b
        case let (a as Data, b as Data): return a == b
        default:
            // Fallback: compare descriptions
            return String(describing: a) == String(describing: b)
        }
    }
    
    // MARK: - Pull (iCloud → local)
    
    /// Pull all synced keys from iCloud into UserDefaults
    func pullFromCloud() {
        isSyncing = true
        defer { isSyncing = false }
        
        for key in SyncedKeys.all {
            if let cloudValue = cloud.object(forKey: key) {
                local.set(cloudValue, forKey: key)
            }
        }
        local.synchronize()
        print("☁️ [iCloudKV] Pulled \(SyncedKeys.all.count) keys from iCloud")
    }
    
    /// Push all synced keys from UserDefaults to iCloud
    func pushToCloud() {
        for key in SyncedKeys.all {
            if let localValue = local.object(forKey: key) {
                cloud.set(localValue, forKey: key)
            }
        }
        cloud.synchronize()
        print("☁️ [iCloudKV] Pushed \(SyncedKeys.all.count) keys to iCloud")
    }
    
    // MARK: - Remote Change Handler
    
    @objc private func cloudDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        // Only process server changes and initial syncs
        if reason == NSUbiquitousKeyValueStoreServerChange ||
           reason == NSUbiquitousKeyValueStoreInitialSyncChange {
            
            isSyncing = true
            defer { isSyncing = false }
            
            let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            
            for key in changedKeys where SyncedKeys.all.contains(key) {
                if let value = cloud.object(forKey: key) {
                    local.set(value, forKey: key)
                }
            }
            local.synchronize()
            
            // Post notification so views can refresh
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .iCloudKVDidChange, object: nil, userInfo: ["keys": changedKeys])
            }
            
            print("☁️ [iCloudKV] Received remote changes for keys: \(changedKeys)")
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let iCloudKVDidChange = Notification.Name("iCloudKVDidChange")
}
