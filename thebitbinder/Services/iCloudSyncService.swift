//
//  iCloudSyncService.swift
//  thebitbinder
//
//  Created on 3/7/26.
//

import SwiftUI
import SwiftData
import CloudKit
import UIKit
import CoreData

extension NSNotification.Name {
    static let iCloudDataDidChange = NSNotification.Name("iCloudDataDidChange")
}

@MainActor
final class iCloudSyncService: NSObject, ObservableObject {
    @Published var isSyncEnabled = false
    @Published var isHapticFeedbackEnabled = true
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var errorMessage: String?
    
    /// Task-based debounce — replaces Timer to stay within structured
    /// concurrency and avoid `unsafeForcedSync` from non-@MainActor Timer callbacks.
    private var debouncedSyncTask: Task<Void, Never>?
    private var isProcessingRemoteChange = false
    private var lastSyncCompletionDate: Date = .distantPast
    private let syncCooldown: TimeInterval = 3.0 // 3 seconds (reduced from 5 for faster sync)

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)
    }
    
    static let shared = iCloudSyncService()
    private let kvStore = iCloudKeyValueStore.shared
    
    // Set this from the app so remote change notifications can trigger a context refresh
    weak var modelContext: ModelContext?
    
    // CloudKit container — must match the container used in ModelContainer CloudKit config
    private lazy var container: CKContainer = {
        return CKContainer(identifier: "iCloud.The-BitBinder.thebitbinder")
    }()
    
    override init() {
        super.init()
        
        // Check if sync setting has been explicitly set
        let hasSetSyncPreference = UserDefaults.standard.object(forKey: SyncedKeys.iCloudSyncEnabled) != nil
        
        if hasSetSyncPreference {
            isSyncEnabled = UserDefaults.standard.bool(forKey: SyncedKeys.iCloudSyncEnabled)
        } else {
            // Default to local-only storage for new installs until the user opts in.
            isSyncEnabled = false
            UserDefaults.standard.set(false, forKey: SyncedKeys.iCloudSyncEnabled)
            print(" [iCloud] First launch - sync disabled until user opts in")
        }
        
        if let lastSyncTimestamp = UserDefaults.standard.object(forKey: SyncedKeys.lastSyncDate) as? Double {
            lastSyncDate = Date(timeIntervalSince1970: lastSyncTimestamp)
        }
        setupRemoteChangeObserver()
    }
    
    // MARK: - Remote Change Notifications
    // This is the key piece that makes sync "just work" across devices.
    // When SwiftData pushes a change to CloudKit from another device, CloudKit
    // sends a silent push to this device. We observe that notification and
    // tell SwiftData's context to refresh, pulling the new data immediately.
    
    private func setupRemoteChangeObserver() {
        // SwiftData + CloudKit fires this when remote changes arrive
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )
        
        // Also observe CloudKit account changes (user signs in/out of iCloud)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountChange),
            name: .CKAccountChanged,
            object: nil
        )
    }

    /// Debounced entry point for silent CloudKit pushes delivered through
    /// UIApplicationDelegate. This avoids spoofing Core Data's internal
    /// remote-change notification, which can cause duplicate merge work.
    func handleSilentPushNotification() {
        scheduleRemoteChangeProcessing(trigger: "silent push")
    }
    
    @objc nonisolated private func handleRemoteChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.scheduleRemoteChangeProcessing(trigger: "persistent store remote change")
        }
    }

    private func scheduleRemoteChangeProcessing(trigger: String) {
        debouncedSyncTask?.cancel()
        debouncedSyncTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.processRemoteChangeAsync(trigger: trigger)
        }
    }

    private func processRemoteChangeAsync(trigger: String) async {
        guard !UserDefaults.standard.bool(forKey: "DataProtection_PendingRestoreRestart") else {
            print(" [iCloud] Sync suppressed — pending restore restart")
            return
        }
        guard !isProcessingRemoteChange else {
            print(" [iCloud] Remote change from \(trigger) ignored — merge already in progress")
            return
        }
        guard Date().timeIntervalSince(lastSyncCompletionDate) >= syncCooldown else {
            print(" [iCloud] Remote change from \(trigger) ignored due to cooldown.")
            return
        }

        isProcessingRemoteChange = true
        defer { isProcessingRemoteChange = false }
        syncStatus = .syncing
        
        // Refresh the SwiftData context so it merges remote CloudKit changes
        // into the in-memory objects. Without this, the context holds stale data
        // and the UI won't reflect changes from other devices.
        if let ctx = modelContext {
            do {
                // Step 1: Save any pending local changes first to avoid conflicts
                if ctx.hasChanges {
                    try ctx.save()
                    print(" [iCloud] Saved pending local changes before merge")
                }
                
                // Step 2: Fetch current count to verify sync is working
                let jokeCount = try ctx.fetchCount(FetchDescriptor<Joke>())
                
                // Step 3: Post notification so SwiftUI views using @Query will refresh
                // @Query automatically observes the model context and should update,
                // but posting this notification allows custom observers to react too.
                NotificationCenter.default.post(name: .iCloudDataDidChange, object: nil)

                print(" [iCloud] Remote changes merged successfully - \(jokeCount) jokes in store")
            } catch {
                print(" [iCloud] Context operation during remote merge failed: \(error.localizedDescription)")
                syncStatus = .error("Failed to merge remote changes: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                lastSyncCompletionDate = Date()
                return
            }
        } else {
            print(" [iCloud] Remote changes received but modelContext is nil — cannot refresh")
            syncStatus = .error("Context unavailable for remote changes")
            errorMessage = "Context unavailable for remote changes"
            lastSyncCompletionDate = Date()
            return
        }
        
        lastSyncDate = Date()
        syncStatus = .success
        lastSyncCompletionDate = Date()
        errorMessage = nil
        
        // Save the sync date to persistence
        if let syncDate = lastSyncDate {
            UserDefaults.standard.set(syncDate.timeIntervalSince1970, forKey: SyncedKeys.lastSyncDate)
        }
        
        // Haptic feedback to let user know sync completed
        hapticFeedback()
    }
    
    @objc nonisolated private func handleAccountChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Guard against rapid re-entry (e.g. multiple CKAccountChanged in quick
            // succession during device unlock).
            guard Date().timeIntervalSince(self.lastSyncCompletionDate) >= self.syncCooldown else {
                print(" [iCloud] Account change ignored — cooldown active")
                return
            }
            print(" [iCloud] Account change detected")
            self.syncStatus = .syncing
            
            let available = await self.checkiCloudAvailability()
            if available {
                if self.isSyncEnabled {
                    await self.performFullSync()
                    print(" [iCloud] Account changed — re-synced successfully")
                } else {
                    print(" [iCloud] Account available but sync disabled")
                    self.syncStatus = .idle
                }
            } else {
                print(" [iCloud] Account changed but not available")
                self.syncStatus = .error("iCloud account not available")
                // Don't disable sync - just wait for account to become available
            }
        }
    }
    
    // MARK: - Enable/Disable iCloud Sync
    
    func enableiCloudSync() async {
        do {
            // Check iCloud availability
            let status = try await container.accountStatus()
            guard status == .available else {
                syncStatus = .error("iCloud not available")
                errorMessage = "Please sign into iCloud in Settings"
                return
            }
            
            isSyncEnabled = true
            kvStore.set(true, forKey: SyncedKeys.iCloudSyncEnabled)
            
            // Perform initial sync
            await performFullSync()
        } catch {
            syncStatus = .error(error.localizedDescription)
            errorMessage = "Failed to enable iCloud sync: \(error.localizedDescription)"
        }
    }
    
    func disableiCloudSync() {
        isSyncEnabled = false
        kvStore.set(false, forKey: SyncedKeys.iCloudSyncEnabled)
        syncStatus = .idle
        errorMessage = nil
    }
    
    // MARK: - Full Sync
    
    func performFullSync() async {
        guard isSyncEnabled else {
            print(" [iCloud] Sync requested but disabled")
            return
        }
        guard !UserDefaults.standard.bool(forKey: "DataProtection_PendingRestoreRestart") else {
            print(" [iCloud] Full sync suppressed — pending restore restart")
            return
        }
        
        print(" [iCloud] Starting full sync...")
        syncStatus = .syncing
        errorMessage = nil

        do {
            // 1. Verify iCloud availability first
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                let message = "iCloud account not available: \(accountStatus)"
                print(" [iCloud] \(message)")
                syncStatus = .error(message)
                errorMessage = message
                return
            }
            
            // 2. Save any pending local changes first
            if let ctx = modelContext, ctx.hasChanges {
                try ctx.save()
                print(" [iCloud] Saved pending local changes")
            }
            
            // 3. Push user settings to iCloud KV store
            print(" [iCloud] Syncing user preferences...")
            iCloudKeyValueStore.shared.pushToCloud()

            // 4. Final context save to persist any pending local changes.
            // Do NOT post .NSPersistentStoreRemoteChange here — that triggers
            // handleRemoteChange which cascades into another full sync.
            if let ctx = modelContext {
                do {
                    if ctx.hasChanges {
                        try ctx.save()
                    }
                    
                    // Verify sync by checking counts
                    let jokeCount = try ctx.fetchCount(FetchDescriptor<Joke>())
                    print(" [iCloud] Full sync checkpoint - \(jokeCount) jokes in store")
                } catch {
                    print(" [iCloud] Warning: Final context save failed: \(error.localizedDescription)")
                }
            }
            
            // Notify UI to refresh
            NotificationCenter.default.post(name: .iCloudDataDidChange, object: nil)
            
            let now = Date()
            lastSyncDate = now
            lastSyncCompletionDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: SyncedKeys.lastSyncDate)
            syncStatus = .success
            errorMessage = nil
            print(" [iCloud] Full sync completed successfully")
            hapticFeedback()
            
        } catch {
            let message = "Sync failed: \(error.localizedDescription)"
            print(" [iCloud] \(message)")
            DataOperationLogger.shared.logError(error, operation: "performFullSync", context: "Full iCloud sync failed")
            lastSyncCompletionDate = Date()
            syncStatus = .error(message)
            errorMessage = message
        }
    }
    
    // MARK: - Sync Thoughts (Notepad)
    
    func syncThoughts(_ content: String) async {
        guard isSyncEnabled else { return }
        
        // Save to iCloud KV store for sync
        kvStore.set(content, forKey: SyncedKeys.notepadText)
        
        // Also save to CloudKit for true cloud backup.
        // Use a fixed recordName so we UPSERT the same record every time
        // instead of creating a new CKRecord on every call.
        do {
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            let recordID = CKRecord.ID(recordName: "UserThoughts", zoneID: zoneID)
            
            // Fetch existing record, or create a new one if it doesn't exist yet
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                record = CKRecord(recordType: "Thoughts", recordID: recordID)
            }
            
            record["content"] = content
            record["timestamp"] = Date()
            
            _ = try await database.save(record)
            print(" Thoughts synced to iCloud")
        } catch {
            print(" Failed to sync thoughts: \(error)")
            DataOperationLogger.shared.logError(error, operation: "syncThoughts", context: "Failed to save thoughts record to CloudKit")
        }
    }
    
    func fetchThoughtsFromCloud() async -> String? {
        guard isSyncEnabled else { return nil }

        // Mirror syncThoughts: fetch the single stable "UserThoughts" record
        // directly rather than running a sort-by-timestamp query. This avoids
        // surfacing any lingering duplicate records from before the upsert
        // fix, and is a round-trip cheaper than CKQuery.
        do {
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            let recordID = CKRecord.ID(recordName: "UserThoughts", zoneID: zoneID)
            let record = try await database.record(for: recordID)
            return record["content"] as? String
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // No thoughts record yet — normal for a fresh install.
            return nil
        } catch {
            print(" Failed to fetch thoughts: \(error)")
            DataOperationLogger.shared.logError(error, operation: "fetchThoughtsFromCloud", context: "Failed to fetch thoughts record from CloudKit")
            return nil
        }
    }
    
    // MARK: - Manual Sync Trigger
    
    func syncNow() async {
        guard !UserDefaults.standard.bool(forKey: "DataProtection_PendingRestoreRestart") else {
            print(" [iCloud] syncNow() suppressed — pending restore restart")
            return
        }
        // Guard against cascading calls — if a sync just completed, skip.
        guard Date().timeIntervalSince(lastSyncCompletionDate) >= syncCooldown else {
            print(" [iCloud] syncNow() skipped — cooldown active")
            return
        }
        await performFullSync()
    }
    
    /// Force refresh all data from CloudKit - use when sync seems stuck
    /// This is more aggressive than syncNow() and will re-fetch counts to verify
    func forceRefreshAllData() async {
        print(" [iCloud] Force refresh initiated...")
        syncStatus = .syncing
        errorMessage = nil
        
        guard let ctx = modelContext else {
            syncStatus = .error("No model context available")
            errorMessage = "No model context available"
            return
        }
        
        do {
            // 1. Verify iCloud is available
            let available = await checkiCloudAvailability()
            guard available else {
                syncStatus = .error("iCloud not available")
                return
            }
            
            // 3. Save any pending changes — SwiftData + CloudKit will
            // automatically process pending remote changes via persistent
            // history tracking. Do NOT post .NSPersistentStoreRemoteChange
            // here — that cascades into handleRemoteChange and triggers a
            // redundant sync cycle on top of this force refresh.
            if ctx.hasChanges {
                try ctx.save()
                print(" [iCloud] Saved pending changes before force refresh")
            }
            
            // 4. Wait a moment for CloudKit to process
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // 5. Verify by fetching counts
            let jokeCount = try ctx.fetchCount(FetchDescriptor<Joke>())
            let setListCount = try ctx.fetchCount(FetchDescriptor<SetList>())
            let recordingCount = try ctx.fetchCount(FetchDescriptor<Recording>())
            
            print(" [iCloud] Force refresh complete - Jokes: \(jokeCount), SetLists: \(setListCount), Recordings: \(recordingCount)")
            
            lastSyncDate = Date()
            syncStatus = .success
            lastSyncCompletionDate = Date()
            errorMessage = nil
            
            if let syncDate = lastSyncDate {
                UserDefaults.standard.set(syncDate.timeIntervalSince1970, forKey: SyncedKeys.lastSyncDate)
            }
            
            // Notify UI to refresh
            NotificationCenter.default.post(name: .iCloudDataDidChange, object: nil)
            
            hapticFeedback()
            
        } catch {
            print(" [iCloud] Force refresh failed: \(error.localizedDescription)")
            syncStatus = .error("Force refresh failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Haptic Feedback
    
    private func hapticFeedback() {
        guard isHapticFeedbackEnabled else { return }
#if !targetEnvironment(macCatalyst)
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
#endif
    }
    
    // MARK: - Check Sync Status
    
    func checkiCloudAvailability() async -> Bool {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                print(" [iCloud] Account available")
                errorMessage = nil
                return true
            case .noAccount:
                print(" [iCloud] No account — user not signed into iCloud")
                errorMessage = "Sign in to iCloud in Settings  [Your Name]  iCloud"
            case .restricted:
                print(" [iCloud] Account restricted (parental controls or MDM)")
                errorMessage = "iCloud is restricted on this device"
            case .couldNotDetermine:
                print(" [iCloud] Could not determine account status")
                errorMessage = "Could not check iCloud status — try again later"
            case .temporarilyUnavailable:
                print(" [iCloud] Temporarily unavailable")
                errorMessage = "iCloud is temporarily unavailable — try again later"
            @unknown default:
                print(" [iCloud] Unknown account status: \(status)")
                errorMessage = "Unknown iCloud status"
            }
            return false
        } catch {
            print(" [iCloud] Account check error: \(error)")
            errorMessage = "iCloud check failed: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Detailed diagnostic info — call from Settings to surface issues
    func runDiagnostics() async -> [String] {
        var results: [String] = []
        
        // 1. iCloud account
        do {
            let status = try await container.accountStatus()
            results.append("iCloud Account: \(status == .available ? " Available" : " \(status)")")
        } catch {
            results.append("iCloud Account:  Error — \(error.localizedDescription)")
        }
        
        // 2. Container ID
        results.append("Container: iCloud.The-BitBinder.thebitbinder")
        
        // 3. Sync enabled
        results.append("Sync Enabled: \(isSyncEnabled ? " Yes" : " No")")
        
        // 4. Last sync
        if let lastSync = lastSyncDate {
            results.append("Last Sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
        } else {
            results.append("Last Sync: Never")
        }
        
        // 5. Try a test fetch to verify CloudKit connectivity
        // Note: CD_* record types are managed by CoreData's CloudKit mirroring
        // and cannot be queried directly via CKQuery. Instead, verify connectivity
        // by fetching the CoreData CloudKit zone itself.
        do {
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            let zone = try await database.recordZone(for: zoneID)
            results.append("CloudKit Fetch Test:  Connected (zone: \(zone.zoneID.zoneName))")
        } catch {
            results.append("CloudKit Fetch Test:  \(error.localizedDescription)")
        }
        
        return results
    }
}
