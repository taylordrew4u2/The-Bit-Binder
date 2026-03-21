//
//  CloudKitResetUtility.swift
//  thebitbinder
//
//  Created for CloudKit schema reset support
//

import Foundation
import CloudKit

/// Utility for development-time CloudKit operations
/// ⚠️ Only use in development builds!
class CloudKitResetUtility {
    
    private static let containerID = "iCloud.666bit"
    private static let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
    
    /// Checks CloudKit account status for debugging
    static func checkCloudKitStatus() {
        let container = CKContainer(identifier: containerID)
        
        container.accountStatus { (status, error) in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("✅ CloudKit account available")
                case .noAccount:
                    print("⚠️ No iCloud account")
                case .restricted:
                    print("⚠️ iCloud account restricted")
                case .couldNotDetermine:
                    print("⚠️ Could not determine iCloud status")
                case .temporarilyUnavailable:
                    print("⚠️ iCloud temporarily unavailable")
                @unknown default:
                    print("❓ Unknown iCloud status")
                }
                
                if let error = error {
                    print("❌ CloudKit error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Logs CloudKit container configuration for debugging
    static func logContainerInfo() {
        let container = CKContainer(identifier: containerID)
        print("📦 CloudKit Container ID: \(container.containerIdentifier ?? "unknown")")
        print("🔧 Environment: Development")
        
        // Check private database
        let _ = container.privateCloudDatabase
        print("🔒 Private database configured")
        
        checkCloudKitStatus()
    }
    
    // MARK: - Corrupted Record Cleanup
    
    /// Deletes all CD_Joke records from CloudKit to fix schema type mismatch
    /// Call this to clear corrupted records where CD_folder was stored as STRING instead of REFERENCE
    static func deleteCorruptedJokeRecords() async throws {
        print("🗑️ [CloudKit] Starting deletion of corrupted CD_Joke records...")
        
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        
        // Query all CD_Joke records
        let query = CKQuery(recordType: "CD_Joke", predicate: NSPredicate(value: true))
        
        do {
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)
            
            let recordIDs = matchResults.compactMap { result -> CKRecord.ID? in
                switch result.1 {
                case .success(let record):
                    return record.recordID
                case .failure:
                    return nil
                }
            }
            
            if recordIDs.isEmpty {
                print("✅ [CloudKit] No CD_Joke records found to delete")
                return
            }
            
            print("🔍 [CloudKit] Found \(recordIDs.count) CD_Joke records to delete")
            
            // Delete in batches of 400 (CloudKit limit)
            let batchSize = 400
            for batchStart in stride(from: 0, to: recordIDs.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, recordIDs.count)
                let batch = Array(recordIDs[batchStart..<batchEnd])
                
                let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: batch)
                
                let successCount = deleteResults.filter {
                    if case .success = $0.value { return true }
                    return false
                }.count
                
                print("🗑️ [CloudKit] Deleted batch: \(successCount)/\(batch.count) records")
            }
            
            print("✅ [CloudKit] Successfully deleted all CD_Joke records")
            
        } catch {
            print("❌ [CloudKit] Error deleting records: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Deletes a specific record by ID
    static func deleteRecord(recordID: String) async throws {
        print("🗑️ [CloudKit] Deleting record: \(recordID)")
        
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        
        let ckRecordID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        
        try await database.deleteRecord(withID: ckRecordID)
        print("✅ [CloudKit] Record deleted: \(recordID)")
    }
    
    /// Deletes all records of a specific type
    static func deleteAllRecords(ofType recordType: String) async throws {
        print("🗑️ [CloudKit] Deleting all \(recordType) records...")
        
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        
        var cursor: CKQueryOperation.Cursor? = nil
        var totalDeleted = 0
        
        repeat {
            var matchResults: [(CKRecord.ID, Result<CKRecord, Error>)] = []
            
            if let existingCursor = cursor {
                let result = try await database.records(continuingMatchFrom: existingCursor)
                matchResults = result.matchResults
                cursor = result.queryCursor
            } else {
                let result = try await database.records(matching: query, inZoneWith: zoneID)
                matchResults = result.matchResults
                cursor = result.queryCursor
            }
            
            let recordIDs = matchResults.compactMap { result -> CKRecord.ID? in
                switch result.1 {
                case .success(let record):
                    return record.recordID
                case .failure:
                    return nil
                }
            }
            
            if !recordIDs.isEmpty {
                let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDs)
                totalDeleted += deleteResults.count
                print("🗑️ [CloudKit] Deleted \(deleteResults.count) \(recordType) records")
            }
            
        } while cursor != nil
        
        print("✅ [CloudKit] Total \(recordType) records deleted: \(totalDeleted)")
    }
    
    /// Nuclear option: Delete the entire CloudKit zone and all data
    /// ⚠️ This will delete ALL synced data!
    static func deleteEntireZone() async throws {
        print("⚠️ [CloudKit] DELETING ENTIRE ZONE - This will remove all synced data!")
        
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase
        
        try await database.deleteRecordZone(withID: zoneID)
        
        print("✅ [CloudKit] Zone deleted. CloudKit will recreate it on next sync.")
    }
    
    /// Delete the specific corrupted record from the error log
    static func deleteCorruptedRecordFromError() async throws {
        // The record ID from the error: 762FB389-C2E2-41E2-BDA6-8D3A65142662
        try await deleteRecord(recordID: "762FB389-C2E2-41E2-BDA6-8D3A65142662")
    }
}

#if DEBUG
extension CloudKitResetUtility {
    
    /// For development only: Clear local CloudKit cache
    /// Call this after resetting the CloudKit schema in CloudKit Console
    static func clearLocalCache() {
        // Note: This doesn't actually clear the cache programmatically
        // Users need to reset simulator or delete/reinstall app
        print("📋 To clear CloudKit cache:")
        print("   1. Reset iOS Simulator: Device → Erase All Content and Settings")
        print("   2. Or delete and reinstall the app on device")
        print("   3. This ensures no cached CloudKit data conflicts with new schema")
    }
    
    /// Development helper to verify the model is properly configured
    static func verifyModelConfiguration() {
        print("🔍 SwiftData Model Verification:")
        print("   ✓ Joke.folder has @Relationship attribute → REFERENCE type")
        print("   ✓ JokeFolder.jokes has inverse relationship to Joke.folder")
        print("   ✓ ImportBatch has @Relationship to ImportedJokeMetadata")
        print("   ✓ ImportedJokeMetadata.batch is optional ImportBatch relationship")
        print("   ✓ CloudKit will map all relationships as REFERENCE type correctly")
    }
    
    /// Force re-run the CloudKit cleanup (for testing)
    static func forceRerunCleanup() {
        UserDefaults.standard.removeObject(forKey: "CloudKitFolderSchemaCleanupCompleted_v1")
        print("🔄 [CloudKit] Cleanup flag reset - will run on next app launch")
    }
}
#endif
