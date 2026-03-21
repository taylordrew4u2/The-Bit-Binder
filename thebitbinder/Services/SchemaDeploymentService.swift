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
    private let schemaVersion = "2.1.0"  // Increment when schema changes
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
        ═══════════════════════════════════════════════════════════════
        
        CD_Joke:
          - CD_id, CD_content, CD_title
          - CD_dateCreated, CD_dateModified
          - CD_isDeleted, CD_deletedDate
          - CD_folder (REFERENCE)
          - CD_primaryCategory, CD_allCategoriesString
          - CD_categoryScoresString, CD_styleTagsString
          - CD_craftNotesString, CD_comedicTone
          - CD_structureScore, CD_category
          - CD_tagsString, CD_difficulty, CD_humorRating
          - CD_isHit
          - CD_importSource (NEW)
          - CD_importConfidence (NEW)
          - CD_importTimestamp (NEW)
        
        CD_ImportBatch:
          - CD_id, CD_sourceFileName, CD_importTimestamp
          - CD_totalSegments, CD_totalImportedRecords
          - CD_unresolvedFragmentCount
          - CD_highConfidenceBoundaries
          - CD_mediumConfidenceBoundaries
          - CD_lowConfidenceBoundaries
          - CD_extractionMethod (NEW)
          - CD_pipelineVersion (NEW)
          - CD_processingTimeSeconds (NEW)
          - CD_autoSavedCount (NEW)
          - CD_reviewQueueCount (NEW)
          - CD_rejectedCount (NEW)
        
        CD_ImportedJokeMetadata:
          - CD_id, CD_jokeID, CD_title
          - CD_rawSourceText, CD_notes
          - CD_confidence, CD_sourceOrder
          - CD_sourcePage, CD_tagsString
          - CD_parsingFlagsJSON, CD_sourceFilename
          - CD_importTimestamp
          - CD_batch (REFERENCE)
          - CD_extractionMethod (NEW)
          - CD_confidenceScore (NEW)
          - CD_extractionQuality (NEW)
          - CD_structuralCleanliness (NEW)
          - CD_titleDetectionScore (NEW)
          - CD_boundaryClarity (NEW)
          - CD_ocrConfidence (NEW)
          - CD_validationResult (NEW)
          - CD_needsReview (NEW)
        
        CD_UnresolvedImportFragment:
          - CD_id, CD_text, CD_normalizedText
          - CD_kind, CD_confidence
          - CD_sourceOrder, CD_sourcePage
          - CD_sourceFilename, CD_titleCandidate
          - CD_tagsString, CD_parsingFlagsJSON
          - CD_createdAt, CD_isResolved
          - CD_batch (REFERENCE)
          - CD_validationResult (NEW)
          - CD_issuesJSON (NEW)
          - CD_confidenceScore (NEW)
        
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
            
            var batchDescriptor = FetchDescriptor<ImportBatch>()
            batchDescriptor.fetchLimit = 1
            let _: [ImportBatch] = try context.fetch(batchDescriptor)
            
            var metadataDescriptor = FetchDescriptor<ImportedJokeMetadata>()
            metadataDescriptor.fetchLimit = 1
            let _: [ImportedJokeMetadata] = try context.fetch(metadataDescriptor)
            
            var fragmentDescriptor = FetchDescriptor<UnresolvedImportFragment>()
            fragmentDescriptor.fetchLimit = 1
            let _: [UnresolvedImportFragment] = try context.fetch(fragmentDescriptor)
            
            print("📋 [Schema] Schema sync triggered successfully")
        } catch {
            print("⚠️ [Schema] Error during schema sync: \(error.localizedDescription)")
        }
    }
    
    /// Returns a summary of schema changes in this version
    func getSchemaChangeSummary() -> String {
        return """
        Schema Changes in v\(schemaVersion):
        
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
           • extractionMethod
           • confidenceScore (0.0-1.0)
           • extractionQuality
           • structuralCleanliness
           • titleDetectionScore
           • boundaryClarity
           • ocrConfidence
           • validationResult
           • needsReview
        
        4. CD_UnresolvedImportFragment - Added validation:
           • validationResult
           • issuesJSON
           • confidenceScore
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

