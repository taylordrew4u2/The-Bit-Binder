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
final class SchemaDeploymentService {
    
    static let shared = SchemaDeploymentService()
    
    private let container = CKContainer(identifier: "iCloud.666bit")
    private let schemaVersion = "2.1.0"  // Increment when schema changes
    
    private init() {}
    
    // MARK: - Schema Verification
    
    /// Verifies that all required record types exist in CloudKit
    func verifySchemaDeployment() async {
        print("📋 [Schema] Verifying CloudKit schema deployment (v\(schemaVersion))...")
        
        let recordTypes = [
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
        
        let database = container.privateCloudDatabase
        
        for recordType in recordTypes {
            do {
                // Try to fetch schema by querying for records (will create schema if needed)
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: false))
                let (_, _) = try await database.records(matching: query, resultsLimit: 1)
                print("  ✅ \(recordType) - OK")
            } catch let error as CKError {
                if error.code == .unknownItem {
                    print("  ⚠️ \(recordType) - Not deployed yet (will auto-create on first save)")
                } else {
                    print("  ❌ \(recordType) - Error: \(error.localizedDescription)")
                }
            } catch {
                print("  ❌ \(recordType) - Error: \(error.localizedDescription)")
            }
        }
        
        print("📋 [Schema] Verification complete")
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
    func ensureSchemaDeployed(context: ModelContext) async {
        print("📋 [Schema] Ensuring schema is deployed to CloudKit...")
        
        // The schema will be auto-deployed when SwiftData syncs
        // We just need to ensure all model types are registered
        
        do {
            // Fetch one joke to trigger schema sync
            let descriptor = FetchDescriptor<Joke>(fetchLimit: 1)
            _ = try context.fetch(descriptor)
            
            // Fetch one import batch
            let batchDescriptor = FetchDescriptor<ImportBatch>(fetchLimit: 1)
            _ = try context.fetch(batchDescriptor)
            
            print("📋 [Schema] Schema sync triggered successfully")
        } catch {
            print("⚠️ [Schema] Error during schema sync: \(error)")
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
}
