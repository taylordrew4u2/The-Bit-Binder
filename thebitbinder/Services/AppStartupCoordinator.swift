import Foundation
import SwiftData
import UIKit

@MainActor
final class AppStartupCoordinator: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var statusText = "Loading..."
    @Published private(set) var dataProtectionStatus = ""
    /// Set to true when DataValidationService detects significant data loss.
    /// The main app view should observe this and show a recovery alert.
    @Published var showDataLossAlert = false
    /// Details of the data loss for the alert message.
    @Published var dataLossDetails: String = ""
    
    private let dataProtection = DataProtectionService.shared
    private let dataValidation = DataValidationService.shared
    private let dataMigration = DataMigrationService.shared
    private let schemaDeployment = SchemaDeploymentService.shared
    
    /// Prevents `completeDataProtectionWithContext` from running more than once.
    private var hasCompletedDataProtection = false
    /// Prevents overlapping attempts while still allowing a retry if the app
    /// backgrounds before post-startup work finishes.
    private var isCompletingDataProtection = false
    
    func start() async {
        guard !isReady else { return }

        await performDataProtectionSequence()

        statusText = "Ready"
        isReady = true
    }

    private func performDataProtectionSequence() async {
        // Step 1: Version Check and Backup
        statusText = "Checking app version..."
        dataProtectionStatus = "Checking for updates..."
        await dataProtection.checkVersionAndBackupIfNeeded()
        
        // Step 2: Get model context for data operations
        // Note: This would need to be injected from the main app
        // For now, we'll defer the migration until we have context
        statusText = "Initializing data protection..."
        dataProtectionStatus = "Data protection services ready"
        
        // Step 3: Basic validation (without context for now)
        statusText = "Validating system..."
        
        print(" [AppStartup] Data protection sequence completed")
    }
    
    /// Call this after ModelContainer is available to complete data validation and migration
    func completeDataProtectionWithContext(_ context: ModelContext) async {
        // Guard: prevent overlaps and skip if already finished this launch.
        guard !hasCompletedDataProtection else {
            print(" [AppStartup] completeDataProtectionWithContext already ran — skipping")
            return
        }
        guard !isCompletingDataProtection else {
            print(" [AppStartup] completeDataProtectionWithContext already in progress — skipping")
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            print(" [AppStartup] Deferring post-startup work until app is active")
            return
        }
        isCompletingDataProtection = true
        defer { isCompletingDataProtection = false }
        
        print(" [AppStartup] Completing data protection with model context...")
        
        // Ensure memory headroom before running expensive validation/migration
        MemoryManager.shared.ensureMemoryHeadroom()
        
        // ── Post-restore confirmation ─────────────────────────────────────
        // If the user restored from a backup and the app restarted, confirm
        // the restore succeeded now that the store is loaded.
        if dataProtection.hasPendingRestoreRestart() {
            dataProtection.clearPendingRestoreRestart()
            print(" [AppStartup] Post-restore startup — data restored successfully")
            DataOperationLogger.shared.logSuccess("App restarted after backup restore — store loaded OK")
            
            // Reset validation counts since the restored store may have different
            // entity counts than the pre-restore baseline.
            UserDefaults.standard.removeObject(forKey: "DataValidation_Counts")
        }
        
        // ── Store recovery detection ────────────────────────────────────
        // If startup had to fall back because the persistent store could not
        // be opened, inform the user so they can restore from a backup.
        if UserDefaults.standard.bool(forKey: "ModelContainer_CorruptionCleanupPerformed") {
            let isInMemory = UserDefaults.standard.bool(forKey: "ModelContainer_InMemoryFallback")
            let storePreserved = UserDefaults.standard.bool(forKey: "ModelContainer_StorePreservedForRecovery")
            let cleanupTimestamp = UserDefaults.standard.double(forKey: "ModelContainer_CorruptionCleanupTimestamp")
            let cleanupDate = Date(timeIntervalSince1970: cleanupTimestamp)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateStr = formatter.string(from: cleanupDate)
            
            print(" [AppStartup] CRITICAL: Persistent store recovery mode detected at \(dateStr)")
            DataOperationLogger.shared.logCritical("Persistent store recovery mode detected - alerting user")
            
            if isInMemory {
                if storePreserved {
                    dataLossDetails = "Your data store could not be opened on \(dateStr). The original store files were preserved on disk and the app is running in temporary mode so nothing is deleted automatically. Any new changes will be lost when the app closes until you restore from Data Safety."
                } else {
                    dataLossDetails = "Your data store was corrupted and could not be recovered. The app is running in temporary mode — any changes will be lost when the app closes. Please restore from a backup immediately in Settings → Data Safety."
                }
            } else {
                dataLossDetails = "Your data store was corrupted on \(dateStr) and had to be rebuilt. A backup of the corrupted store was saved automatically. You can restore from a recent backup in Settings → Data Safety."
            }
            showDataLossAlert = true
            
            // Clear the one-shot flag so the alert only shows once
            UserDefaults.standard.removeObject(forKey: "ModelContainer_CorruptionCleanupPerformed")
            UserDefaults.standard.removeObject(forKey: "ModelContainer_InMemoryFallback")
            UserDefaults.standard.removeObject(forKey: "ModelContainer_StorePreservedForRecovery")
            // Keep the timestamp for audit trail
            
            // Reset validation counts — the fresh store is empty so comparing
            // against the old baseline would falsely trigger a second "data loss" alert.
            UserDefaults.standard.removeObject(forKey: "DataValidation_Counts")
        }
        
        // NOTE: CloudKit zone cleanup (repairCorruptedZone) already runs in
        // thebitbinderApp.performAggressiveCloudKitCleanup() before this method
        // is called. No need to duplicate it here — both used the same guard key.
        
        // One-time reset: clear stale validation counts from pre-migration era.
        // After a bundle ID change, entity counts start at 0 until CloudKit syncs,
        // which falsely triggers "significant data loss" detection.
        let migrationCountsResetKey = "DataValidation_CountsReset_v10"
        if !UserDefaults.standard.bool(forKey: migrationCountsResetKey) {
            UserDefaults.standard.removeObject(forKey: "DataValidation_Counts")
            UserDefaults.standard.set(true, forKey: migrationCountsResetKey)
            print(" [AppStartup] Reset stale validation counts after bundle ID migration")
        }
        
        // Purge soft-deleted items older than 30 days before validation runs
        await purgeExpiredTrashItems(context: context)
        await Task.yield()
        guard shouldContinueForegroundStartup() else { return }

        // Launch-time validation stays lightweight to avoid faulting large
        // portions of the store before the app is interactive.
        let validation = await dataValidation.validateDataIntegrity(
            context: context,
            includeDeepScan: false
        )
        await Task.yield()
        
        if validation.significantDataLoss && !validation.issues.isEmpty {
            print(" [AppStartup] CRITICAL: Significant data loss detected!")
            dataLossDetails = "Data validation found \(validation.issues.count) issue(s): \(validation.issues.prefix(3).joined(separator: "; ")). You can restore from a recent backup in Settings  Data Safety."
            showDataLossAlert = true
        } else if validation.significantDataLoss {
            // Count dropped but no actual corruption — likely trash purge or migration.
            // Just log it, don't alarm the user.
            print(" [AppStartup] Entity count drop detected but no data issues found — likely normal (trash purge, migration)")
        } else if !validation.isHealthy {
            print(" [AppStartup] Data validation found minor issues")
        } else {
            print(" [AppStartup] Data validation passed")
        }
        
        // Auto-repair broken relationships (JokeFolder AND RoastJokeRoastTarget)
        if !validation.issues.isEmpty {
            let repaired = await dataValidation.repairDataIssues(context: context, issues: validation.issues)
            if !repaired.isEmpty {
                print(" [AppStartup] Auto-repaired \(repaired.count) issue(s): \(repaired.joined(separator: "; "))")
            }
        }
        
        await Task.yield()
        guard shouldContinueForegroundStartup() else { return }

        // Handle schema changes
        await dataMigration.handleSchemaChanges(context: context)
        await Task.yield()
        guard shouldContinueForegroundStartup() else { return }

        // Verify CloudKit schema deployment
        schemaDeployment.logSchemaFields()
        await schemaDeployment.ensureSchemaDeployed(context: context)
        await Task.yield()
        guard shouldContinueForegroundStartup() else { return }

        // Perform any needed migrations
        let migrationResult = await dataMigration.performSafeMigration(context: context)
        
        switch migrationResult {
        case .success(let message):
            print(" [AppStartup] Migration: \(message)")
        case .warning(let message):
            print(" [AppStartup] Migration: \(message)")
        case .failure(let message):
            print(" [AppStartup] Migration: \(message)")
        }
        
        hasCompletedDataProtection = true
    }

    private func shouldContinueForegroundStartup() -> Bool {
        guard UIApplication.shared.applicationState == .active else {
            print(" [AppStartup] Pausing post-startup work because app is no longer active")
            return false
        }
        return true
    }
    
    // MARK: - Trash Auto-Purge

    /// Hard-deletes any soft-deleted records whose `deletedDate` is more than 30 days ago.
    /// Runs once per app launch, before validation, so stale trash doesn't inflate counts.
    /// Recordings: audio files are deleted before the DB record is removed.
    private func purgeExpiredTrashItems(context: ModelContext) async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let distantFuture = Date.distantFuture
        var purgeCount = 0

        // Jokes
        if let jokes = try? context.fetch(FetchDescriptor<Joke>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for joke in jokes { context.delete(joke) }
            purgeCount += jokes.count
        }
        await Task.yield()

        // BrainstormIdeas
        if let ideas = try? context.fetch(FetchDescriptor<BrainstormIdea>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for idea in ideas { context.delete(idea) }
            purgeCount += ideas.count
        }
        await Task.yield()

        // SetLists
        if let setLists = try? context.fetch(FetchDescriptor<SetList>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for setList in setLists { context.delete(setList) }
            purgeCount += setLists.count
        }

        // RoastJokes
        if let roastJokes = try? context.fetch(FetchDescriptor<RoastJoke>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for joke in roastJokes { context.delete(joke) }
            purgeCount += roastJokes.count
        }
        await Task.yield()

        // NotebookPhotoRecords
        if let photos = try? context.fetch(FetchDescriptor<NotebookPhotoRecord>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for photo in photos { context.delete(photo) }
            purgeCount += photos.count
        }

        // RoastTargets — cascade deletes their RoastJokes
        if let targets = try? context.fetch(FetchDescriptor<RoastTarget>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for target in targets { context.delete(target) }
            purgeCount += targets.count
        }
        await Task.yield()

        // JokeFolders — nullifies joke relationships on delete
        if let folders = try? context.fetch(FetchDescriptor<JokeFolder>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for folder in folders { context.delete(folder) }
            purgeCount += folders.count
        }

        // Recordings — delete audio file first, then DB record
        if let recordings = try? context.fetch(FetchDescriptor<Recording>(
            predicate: #Predicate { $0.isTrashed == true && ($0.deletedDate ?? distantFuture) < cutoff }
        )) {
            for recording in recordings {
                let fileURL = recording.resolvedURL
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        print(" [AutoPurge] Could not delete audio file '\(fileURL.lastPathComponent)': \(error)")
                    }
                }
                context.delete(recording)
            }
            purgeCount += recordings.count
        }
        await Task.yield()

        // Orphan recordings — soft-delete active recordings whose backing
        // audio file was externally deleted.
        let handledIDs = Set(UserDefaults.standard.stringArray(forKey: "DataValidation_HandledMissingRecordingIDs") ?? [])
        if let activeRecordings = try? context.fetch(FetchDescriptor<Recording>(
            predicate: #Predicate { $0.isTrashed == false }
        )) {
            var orphanCount = 0
            var updatedHandledIDs = handledIDs
            for recording in activeRecordings {
                guard !handledIDs.contains(recording.id.uuidString) else { continue }
                if !recording.fileURL.isEmpty && !recording.backingFileExists {
                    print(" [OrphanCleanup] Recording '\(recording.title)' has no backing file — moving to trash")
                    recording.moveToTrash()
                    updatedHandledIDs.insert(recording.id.uuidString)
                    orphanCount += 1
                }
            }
            if orphanCount > 0 {
                purgeCount += orphanCount
                UserDefaults.standard.set(Array(updatedHandledIDs.prefix(200)), forKey: "DataValidation_HandledMissingRecordingIDs")
                print(" [OrphanCleanup] Moved \(orphanCount) orphan recording(s) to trash (recoverable for 30 days)")
            }
        }

        if purgeCount > 0 {
            do {
                try context.save()
                print(" [AutoPurge] Permanently deleted \(purgeCount) item(s) from trash (>30 days old)")
            } catch {
                print(" [AutoPurge] Failed to save after trash purge: \(error)")
            }
        } else {
            print(" [AutoPurge] No expired trash items found")
        }
    }

}
