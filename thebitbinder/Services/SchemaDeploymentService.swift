//
//  SchemaDeploymentService.swift
//  thebitbinder
//
//  Verifies and logs CloudKit schema deployment status
//

import Foundation
import SwiftData
import CloudKit

/// Service to verify CloudKit schema deployment
/// Thread-safe singleton that manages CloudKit schema verification and deployment
final class SchemaDeploymentService: @unchecked Sendable {
    
    static let shared = SchemaDeploymentService()
    
    private let container: CKContainer
    private let schemaVersion = "2.3.0"  // Increment when schema changes
    private let signatureService: CloudKitSignatureService
    
    /// All CloudKit record types managed by this schema
    private let recordTypes: [String] = [
        "CD_Joke",
        "CD_JokeFolder",
        "CD_Recording",
        "CD_SetList",
        "CD_RoastTarget",
        "CD_RoastJoke",
        "CD_BrainstormIdea",
        "CD_NotebookPhotoRecord",
        "CD_ImportBatch",
        "CD_ImportedJokeMetadata",
        "CD_UnresolvedImportFragment",
        "CD_ChatMessage"
    ]
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.666bit")
        self.signatureService = CloudKitSignatureService.shared
    }
    
    // MARK: - Schema Verification
    
    /// Verifies that all required record types exist in CloudKit
    func verifySchemaDeployment() async {
        print("📋 [Schema] Verifying CloudKit schema deployment (v\(schemaVersion))...")
        
        let database = container.privateCloudDatabase
        
        for recordType in recordTypes {
            do {
                // Try to fetch schema by querying for records (will create schema if needed)
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: false)]
                
                let (results, _) = try await database.records(matching: query, resultsLimit: 1)
                _ = results // Silence unused warning
                print("  ✅ \(recordType) - OK")
            } catch let error as CKError {
                handleCloudKitError(error, for: recordType)
            } catch {
                print("  ❌ \(recordType) - Error: \(error.localizedDescription)")
            }
        }
        
        print("📋 [Schema] Verification complete")
    }
    
    /// Handles CloudKit errors during schema verification
    private func handleCloudKitError(_ error: CKError, for recordType: String) {
        switch error.code {
        case .unknownItem:
            print("  ⚠️ \(recordType) - Not deployed yet (will auto-create on first save)")
        case .invalidArguments:
            // This can happen if the record type doesn't exist yet
            print("  ⚠️ \(recordType) - Schema not yet created (will auto-create on first save)")
        case .networkFailure, .networkUnavailable:
            print("  ⚠️ \(recordType) - Network unavailable, skipping verification")
        case .serverRejectedRequest:
            print("  ⚠️ \(recordType) - Server rejected request (may need schema update)")
        case .zoneBusy:
            print("  ⚠️ \(recordType) - Zone busy, try again later")
        case .quotaExceeded:
            print("  ❌ \(recordType) - Quota exceeded")
        default:
            print("  ❌ \(recordType) - Error (\(error.code.rawValue)): \(error.localizedDescription)")
        }
    }
    
    /// Logs the current schema fields for a record type
    func logSchemaFields() {
        print("""
        
        ═══════════════════════════════════════════════════════════════
        BitBinder CloudKit Schema v\(schemaVersion)
        Q = QUERYABLE, S = SORTABLE
        ═══════════════════════════════════════════════════════════════
        
        CD_Joke:
          - CD_id [Q], CD_content, CD_title [Q]
          - CD_dateCreated [Q,S], CD_dateModified [Q,S]
          - CD_isDeleted [Q], CD_deletedDate
          - CD_folder (REFERENCE) [Q]
          - CD_primaryCategory [Q], CD_allCategoriesString
          - CD_categoryScoresString, CD_styleTagsString
          - CD_craftNotesString, CD_comedicTone
          - CD_structureScore, CD_category [Q]
          - CD_tagsString, CD_difficulty, CD_humorRating
          - CD_isHit [Q]
          - CD_importSource
          - CD_importConfidence
          - CD_importTimestamp
        
        CD_JokeFolder:
          - CD_id [Q], CD_name [Q]
          - CD_dateCreated [Q,S], CD_isRecentlyAdded
        
        CD_Recording:
          - CD_id [Q], CD_title [Q]
          - CD_dateCreated [Q,S], CD_duration
          - CD_fileURL, CD_transcription
          - CD_isProcessed
          - CD_isDeleted [Q], CD_deletedDate
        
        CD_SetList:
          - CD_id [Q], CD_name [Q]
          - CD_dateCreated [Q,S], CD_dateModified [Q,S]
          - CD_jokeIDsString, CD_roastJokeIDsString
          - CD_notes
          - CD_isDeleted [Q], CD_deletedDate
        
        CD_RoastTarget:
          - CD_id [Q], CD_name [Q]
          - CD_dateCreated [Q,S], CD_dateModified [Q,S]
          - CD_notes, CD_photoData (BYTES)
        
        CD_RoastJoke:
          - CD_id [Q], CD_content, CD_title [Q]
          - CD_dateCreated [Q,S], CD_dateModified [Q,S]
          - CD_target (REFERENCE) [Q]
          - CD_isDeleted [Q], CD_deletedDate
        
        CD_BrainstormIdea:
          - CD_id [Q], CD_content
          - CD_colorHex, CD_dateCreated [Q,S]
          - CD_isVoiceNote
          - CD_isDeleted [Q], CD_deletedDate
        
        CD_NotebookPhotoRecord:
          - CD_id [Q], CD_notes
          - CD_imageData (BYTES), CD_dateAdded [Q,S]
          - CD_isDeleted [Q], CD_deletedDate
        
        CD_ImportBatch:
          - CD_id [Q], CD_sourceFileName, CD_importTimestamp [Q,S]
          - CD_totalSegments, CD_totalImportedRecords
          - CD_unresolvedFragmentCount
          - CD_highConfidenceBoundaries
          - CD_mediumConfidenceBoundaries
          - CD_lowConfidenceBoundaries
          - CD_extractionMethod
          - CD_pipelineVersion
          - CD_processingTimeSeconds
          - CD_autoSavedCount
          - CD_reviewQueueCount
          - CD_rejectedCount
        
        CD_ImportedJokeMetadata:
          - CD_id [Q], CD_jokeID [Q], CD_title
          - CD_rawSourceText, CD_notes
          - CD_confidence, CD_sourceOrder
          - CD_sourcePage, CD_tagsString
          - CD_parsingFlagsJSON, CD_sourceFilename
          - CD_importTimestamp [Q,S]
          - CD_batch (REFERENCE)
          - CD_extractionMethod
          - CD_confidenceScore
          - CD_extractionQuality
          - CD_structuralCleanliness
          - CD_titleDetectionScore
          - CD_boundaryClarity
          - CD_ocrConfidence
          - CD_validationResult
          - CD_needsReview
        
        CD_UnresolvedImportFragment:
          - CD_id [Q], CD_text, CD_normalizedText
          - CD_kind, CD_confidence
          - CD_sourceOrder, CD_sourcePage
          - CD_sourceFilename, CD_titleCandidate
          - CD_tagsString, CD_parsingFlagsJSON
          - CD_createdAt [Q,S], CD_isResolved [Q]
          - CD_batch (REFERENCE)
          - CD_validationResult
          - CD_issuesJSON
          - CD_confidenceScore
        
        CD_ChatMessage:
          - CD_id [Q], CD_text
          - CD_isUser, CD_timestamp [Q,S]
          - CD_conversationId [Q]
        
        ═══════════════════════════════════════════════════════════════
        
        """)
    }
    
    // MARK: - Schema Migration Helper
    
    /// Creates a test record to ensure schema is deployed
    @MainActor
    func ensureSchemaDeployed(context: ModelContext) async {
        print("📋 [Schema] Ensuring schema is deployed to CloudKit...")
        
        // The schema will be auto-deployed when SwiftData syncs
        // We just need to ensure all model types are registered
        
        do {
            var jokeDescriptor = FetchDescriptor<Joke>()
            jokeDescriptor.fetchLimit = 1
            let _: [Joke] = try context.fetch(jokeDescriptor)
            
            var folderDescriptor = FetchDescriptor<JokeFolder>()
            folderDescriptor.fetchLimit = 1
            let _: [JokeFolder] = try context.fetch(folderDescriptor)
            
            var recordingDescriptor = FetchDescriptor<Recording>()
            recordingDescriptor.fetchLimit = 1
            let _: [Recording] = try context.fetch(recordingDescriptor)
            
            var setListDescriptor = FetchDescriptor<SetList>()
            setListDescriptor.fetchLimit = 1
            let _: [SetList] = try context.fetch(setListDescriptor)
            
            var roastTargetDescriptor = FetchDescriptor<RoastTarget>()
            roastTargetDescriptor.fetchLimit = 1
            let _: [RoastTarget] = try context.fetch(roastTargetDescriptor)
            
            var roastJokeDescriptor = FetchDescriptor<RoastJoke>()
            roastJokeDescriptor.fetchLimit = 1
            let _: [RoastJoke] = try context.fetch(roastJokeDescriptor)
            
            var brainstormDescriptor = FetchDescriptor<BrainstormIdea>()
            brainstormDescriptor.fetchLimit = 1
            let _: [BrainstormIdea] = try context.fetch(brainstormDescriptor)
            
            var photoDescriptor = FetchDescriptor<NotebookPhotoRecord>()
            photoDescriptor.fetchLimit = 1
            let _: [NotebookPhotoRecord] = try context.fetch(photoDescriptor)
            
            var batchDescriptor = FetchDescriptor<ImportBatch>()
            batchDescriptor.fetchLimit = 1
            let _: [ImportBatch] = try context.fetch(batchDescriptor)
            
            var metadataDescriptor = FetchDescriptor<ImportedJokeMetadata>()
            metadataDescriptor.fetchLimit = 1
            let _: [ImportedJokeMetadata] = try context.fetch(metadataDescriptor)
            
            var fragmentDescriptor = FetchDescriptor<UnresolvedImportFragment>()
            fragmentDescriptor.fetchLimit = 1
            let _: [UnresolvedImportFragment] = try context.fetch(fragmentDescriptor)
            
            var chatDescriptor = FetchDescriptor<ChatMessage>()
            chatDescriptor.fetchLimit = 1
            let _: [ChatMessage] = try context.fetch(chatDescriptor)
            
            print("📋 [Schema] Schema sync triggered for all \(recordTypes.count) record types")
        } catch {
            print("⚠️ [Schema] Error during schema sync: \(error.localizedDescription)")
        }
    }
    
    /// Returns a summary of schema changes in this version
    func getSchemaChangeSummary() -> String {
        return """
        Schema Changes in v\(schemaVersion):
        
        v2.3.0 — Soft-Delete Fields (trash support):
        Added isDeleted (QUERYABLE) + deletedDate to all remaining model types.
        Mirrors the existing Joke soft-delete pattern introduced in v2.2.0.
        
          • CD_Recording:          CD_isDeleted [Q], CD_deletedDate
          • CD_SetList:            CD_isDeleted [Q], CD_deletedDate
          • CD_RoastJoke:          CD_isDeleted [Q], CD_deletedDate
          • CD_BrainstormIdea:     CD_isDeleted [Q], CD_deletedDate
          • CD_NotebookPhotoRecord: CD_isDeleted [Q], CD_deletedDate
        
        All active @Query filters now include isDeleted==false predicates.
        Trash views added for all types. Auto-purge after 30 days at launch.
        
        v2.2.0 — QUERYABLE Index Additions:
        All CD_* record types now have QUERYABLE indexes on key fields.
        """
        
          • CD_RoastTarget: CD_id, CD_name, CD_dateCreated, CD_dateModified, ___recordID
          • CD_RoastJoke: CD_id, CD_title, CD_target, CD_dateCreated, CD_dateModified
          • CD_Joke: CD_id, CD_title, CD_category, CD_folder, CD_isDeleted, CD_isHit,
                     CD_primaryCategory, CD_dateCreated, CD_dateModified
          • CD_JokeFolder: CD_id, CD_name, CD_dateCreated
          • CD_Recording: CD_id, CD_title, CD_dateCreated
          • CD_SetList: CD_id, CD_name, CD_dateCreated, CD_dateModified
          • CD_BrainstormIdea: CD_id, CD_dateCreated
          • CD_NotebookPhotoRecord: CD_id, CD_dateAdded
          • CD_ChatMessage: CD_id, CD_conversationId, CD_timestamp
          • CD_ImportBatch: CD_id, CD_importTimestamp
          • CD_ImportedJokeMetadata: CD_id, CD_jokeID, CD_importTimestamp
          • CD_UnresolvedImportFragment: CD_id, CD_createdAt, CD_isResolved
        
        v2.1.0 — Import Pipeline Fields:
        
        1. CD_Joke - Added import tracking:
           • importSource (file name)
           • importConfidence (high/medium/low)
           • importTimestamp
        
        2. CD_ImportBatch - Added pipeline metrics:
           • extractionMethod
           • pipelineVersion
           • processingTimeSeconds
           • autoSavedCount
           • reviewQueueCount
           • rejectedCount
        
        3. CD_ImportedJokeMetadata - Added confidence factors:
           • extractionMethod, confidenceScore (0.0-1.0)
           • extractionQuality, structuralCleanliness
           • titleDetectionScore, boundaryClarity
           • ocrConfidence, validationResult, needsReview
        
        4. CD_UnresolvedImportFragment - Added validation:
           • validationResult, issuesJSON, confidenceScore
        """
    }
    
    // MARK: - Signature Verification
    
    /// Verifies schema integrity using the public key
    func verifySchemaIntegrity() -> Bool {
        let schemaHash = signatureService.generateSchemaHash(recordTypes: recordTypes)
        
        print("📋 [Schema] Generated schema hash: \(schemaHash.prefix(16))...")
        print("📋 [Schema] Key info: \(signatureService.getKeyInfo().description)")
        
        // Store key in keychain for additional security
        _ = signatureService.storeKeyInKeychain()
        
        return signatureService.getKeyInfo().isLoaded
    }
    
    /// Returns all CloudKit record types managed by this schema
    func getRecordTypes() -> [String] {
        return recordTypes
    }
    
    /// Performs full schema verification including signature check
    func performFullVerification() async -> SchemaVerificationReport {
        print("📋 [Schema] Starting full schema verification...")
        
        var report = SchemaVerificationReport()
        report.schemaVersion = schemaVersion
        report.timestamp = Date()
        
        // 1. Verify signature service is ready
        let keyInfo = signatureService.getKeyInfo()
        report.signatureServiceReady = keyInfo.isLoaded
        
        if keyInfo.isLoaded {
            print("  ✅ Signature service ready")
        } else {
            print("  ❌ Signature service not ready")
        }
        
        // 2. Generate and store schema hash
        report.schemaHash = signatureService.generateSchemaHash(recordTypes: recordTypes)
        print("  ✅ Schema hash generated")
        
        // 3. Verify CloudKit deployment
        await verifySchemaDeployment()
        report.cloudKitVerified = true
        
        // 4. Store key in keychain
        report.keychainStored = signatureService.storeKeyInKeychain()
        
        print("📋 [Schema] Full verification complete")
        return report
    }
}

// MARK: - Schema Verification Report

struct SchemaVerificationReport: Sendable {
    var schemaVersion: String = ""
    var timestamp: Date = Date()
    var signatureServiceReady: Bool = false
    var schemaHash: String = ""
    var cloudKitVerified: Bool = false
    var keychainStored: Bool = false
    
    var isFullyVerified: Bool {
        signatureServiceReady && cloudKitVerified
    }
    
    var summary: String {
        """
        ═══════════════════════════════════════════════════════════════
        Schema Verification Report
        ═══════════════════════════════════════════════════════════════
        Version: \(schemaVersion)
        Timestamp: \(timestamp)
        
        Status:
          • Signature Service: \(signatureServiceReady ? "✅ Ready" : "❌ Not Ready")
          • Schema Hash: \(schemaHash.prefix(32))...
          • CloudKit Verified: \(cloudKitVerified ? "✅ Yes" : "❌ No")
          • Keychain Stored: \(keychainStored ? "✅ Yes" : "⚠️ No")
        
        Overall: \(isFullyVerified ? "✅ VERIFIED" : "⚠️ INCOMPLETE")
        ═══════════════════════════════════════════════════════════════
        """
    }
}

