//
//  CloudKitResetUtility.swift
//  thebitbinder
//
//  Created for CloudKit schema reset support
//

import Foundation
import CloudKit

/// Utility for CloudKit schema-mismatch recovery.
///
/// CoreData+CloudKit maps every `@Relationship` property as a CloudKit
/// `REFERENCE` field. If a corrupted record wrote that field as a `STRING`
/// instead, the mirroring delegate enters a permanent error loop:
///
///   "invalid attempt to set value type STRING for field 'CD_folder'
///    for type 'CD_Joke', defined to be: REFERENCE"
///
/// Because CoreData-managed record types (CD_*) are **not indexed**, you
/// cannot query them with `CKQuery`. The only reliable fix is to delete the
/// entire private-database zone. CoreData will recreate it and re-export
/// every local record with the correct schema on next launch.
///
/// **Local data is never touched** — only remote CloudKit records are deleted.
class CloudKitResetUtility {

    static let containerID = "iCloud.The-BitBinder.thebitbinder"
    static let zoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )

    /// Version key for the cleanup. Bump this whenever a new round of
    /// schema-mismatch fixes is needed so the one-time guard re-fires.
    /// v4: Added soft-delete fields (CD_isDeleted, CD_deletedDate) to
    ///     Recording, SetList, RoastJoke, BrainstormIdea, NotebookPhotoRecord
    ///     and CD_wordCount to Joke.
    ///
    /// NOTE (post-v4): The soft-delete flag was later renamed
    /// `isDeleted` -> `isTrashed` on every @Model because the old name
    /// shadowed `PersistentModel.isDeleted` and never round-tripped through
    /// SwiftData/CloudKit. That rename does NOT need a zone wipe — CoreData
    /// adds the new `CD_isTrashed` column via lightweight schema migration
    /// and the orphaned `CD_isDeleted` column is harmlessly ignored. We
    /// intentionally do NOT bump the cleanup key for the rename so that
    /// existing local + remote user data is preserved untouched.
    static let cleanupVersionKey = "cloudkit_schema_cleanup_v4"

    // MARK: - Public Entry Point

    /// One-time cleanup that fixes **all** STRING-vs-REFERENCE mismatches.
    ///
    /// Affected fields (all should be REFERENCE in CloudKit):
    ///  - `CD_Joke.CD_folder`                       → `JokeFolder`
    ///  - `CD_RoastJoke.CD_target`                  → `RoastTarget`
    ///  - `CD_ImportedJokeMetadata.CD_batch`         → `ImportBatch`
    ///  - `CD_UnresolvedImportFragment.CD_batch`     → `ImportBatch`
    ///
    /// Strategy:
    ///  1. Try deleting every **known** corrupted record by ID.
    ///  2. Regardless of step-1 outcome, **delete the entire zone** so
    ///     CoreData rebuilds it cleanly from the local SQLite store.
    ///
    /// Safe because:
    ///  - The local `default.store` is the source of truth.
    ///  - After zone deletion CoreData re-exports every local record
    ///    with correct REFERENCE types on its next export cycle.
    static func repairCorruptedZone() async throws {
        print(" [CloudKit] Starting schema-mismatch repair (v4 — adds soft-delete fields + CD_wordCount)...")

        let container = CKContainer(identifier: containerID)
        let database  = container.privateCloudDatabase

        // ── Step 1: Best-effort deletion of known bad records ──────────
        // This list comes from error logs. If any ID is already gone we
        // treat that as success (.unknownItem is fine).
        let knownCorruptedIDs = [
            "762FB389-C2E2-41E2-BDA6-8D3A65142662"  // CD_Joke with STRING CD_folder
        ]

        for name in knownCorruptedIDs {
            let rid = CKRecord.ID(recordName: name, zoneID: zoneID)
            do {
                try await database.deleteRecord(withID: rid)
                print("   Deleted known corrupt record \(name)")
            } catch let e as CKError where e.code == .unknownItem {
                print("   Record \(name) already gone")
            } catch {
                print("   Could not delete \(name): \(error.localizedDescription)")
                // Continue — zone delete below will catch everything
            }
        }

        // ── Step 2: Delete the entire CoreData CloudKit zone ───────────
        // This is the only 100 % reliable fix because:
        //   • CD_* record types are now indexed (QUERYABLE) in the schema,
        //   • There may be corrupted records we don't have IDs for.
        //   • Zone delete wipes the server-side schema for this zone,
        //     letting CoreData re-create it with correct field types.
        do {
            try await database.deleteRecordZone(withID: zoneID)
            print("   Zone deleted — CoreData will re-export local data")
        } catch let e as CKError where e.code == .zoneNotFound {
            print("   Zone already deleted — nothing to do")
        } catch {
            print("   Zone deletion failed: \(error.localizedDescription)")
            throw error
        }

        // ── Step 3: Mark success ───────────────────────────────────────
        UserDefaults.standard.set(true, forKey: cleanupVersionKey)
        print(" [CloudKit] Schema-mismatch repair complete")
    }

    // MARK: - Helpers

    /// Checks CloudKit account status for debugging
    static func checkCloudKitStatus() async -> CKAccountStatus {
        let container = CKContainer(identifier: containerID)
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:            print(" CloudKit account available")
            case .noAccount:            print(" No iCloud account")
            case .restricted:           print(" iCloud account restricted")
            case .couldNotDetermine:    print(" Could not determine iCloud status")
            case .temporarilyUnavailable: print(" iCloud temporarily unavailable")
            @unknown default:           print(" Unknown iCloud status: \(status.rawValue)")
            }
            return status
        } catch {
            print(" CloudKit error: \(error.localizedDescription)")
            return .couldNotDetermine
        }
    }

    /// Logs CloudKit container configuration for debugging
    static func logContainerInfo() {
        let container = CKContainer(identifier: containerID)
        print(" CloudKit Container ID: \(container.containerIdentifier ?? "unknown")")
        print(" Environment: Development")
        let _ = container.privateCloudDatabase
        print(" Private database configured")

        Task { _ = await checkCloudKitStatus() }
    }

}
