//
//  CloudErrorClassifier.swift
//  thebitbinder
//
//  Maps any CloudKit / Core Data / network error into a small set of
//  user-meaningful categories. UI surfaces the category; behavior code
//  decides whether to retry, prompt, or just log.
//
//  Golden rule: classification NEVER triggers data deletion. Every
//  destructive operation must be the result of an explicit user action.
//

import Foundation
import CloudKit
import CoreData

enum CloudErrorCategory: Equatable {
    /// No iCloud account signed in, or restricted by parental controls / MDM.
    case iCloudUnavailable

    /// The signed-in iCloud account changed since the last app run.
    /// Local data is preserved; shared state must be re-evaluated.
    case accountChanged

    /// User is over their iCloud storage quota.
    case quotaExceeded

    /// Account or device lacks permission for the operation (e.g. share
    /// participant trying to write to a read-only share).
    case permissionFailure

    /// Share previously accepted by this user has been deleted by its owner.
    /// Local copy should be kept until the user opts to discard it.
    case shareDeleted

    /// Transient network problem. Retry with backoff; don't bug the user.
    case networkFailure

    /// CloudKit is rate-limiting us; back off and retry later.
    case throttled

    /// A change conflict was detected. Core Data + NSMergeByPropertyObjectTrump
    /// usually resolves automatically; surfaces here only when escalation is
    /// needed.
    case conflict

    /// The server thinks our schema is wrong. Often appears in development
    /// before schema deployment. Logged loudly, not user-facing.
    case schemaMismatch

    /// Bucket for anything we didn't anticipate. Logged and surfaced to the
    /// developer status screen, but app continues running.
    case unknown
}

struct ClassifiedCloudError: Equatable {
    let category: CloudErrorCategory
    let underlying: NSError
    let userFacingMessage: String
    let isTransient: Bool

    var shouldRetry: Bool { isTransient }
}

enum CloudErrorClassifier {

    /// Classify any error coming out of CloudKit or Core Data CloudKit
    /// integration. Pass the raw error you receive from a save / fetch / sync
    /// callback; this function looks through wrapping layers (NSError,
    /// CKError, NSCocoaError).
    static func classify(_ error: Error) -> ClassifiedCloudError {
        let nsError = error as NSError

        // Walk the error chain looking for a CKError or a Cocoa Core Data
        // error code we recognize. CKError is the most specific source of
        // truth when it exists.
        if let ckError = error as? CKError ?? findCKError(in: nsError) {
            return classifyCKError(ckError, originalNSError: nsError)
        }

        // Core Data conflict?
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSManagedObjectMergeError, NSManagedObjectConstraintMergeError:
                return ClassifiedCloudError(
                    category: .conflict,
                    underlying: nsError,
                    userFacingMessage: "Two devices edited the same item at the same time. We kept your local edits.",
                    isTransient: false
                )
            case NSPersistentStoreIncompatibleVersionHashError,
                 NSMigrationError,
                 NSMigrationMissingSourceModelError,
                 NSMigrationMissingMappingModelError:
                return ClassifiedCloudError(
                    category: .schemaMismatch,
                    underlying: nsError,
                    userFacingMessage: "Sync schema mismatch. Reopening the app usually resolves this.",
                    isTransient: false
                )
            default:
                break
            }
        }

        // URLError surfaced when the device has no network.
        if let urlError = error as? URLError {
            return ClassifiedCloudError(
                category: .networkFailure,
                underlying: nsError,
                userFacingMessage: "You're offline. Changes will sync when the network is back.",
                isTransient: urlError.code != .badURL
            )
        }

        return ClassifiedCloudError(
            category: .unknown,
            underlying: nsError,
            userFacingMessage: "Sync hit an unexpected issue. Your data is safe locally.",
            isTransient: false
        )
    }

    // MARK: - CKError specifics

    private static func classifyCKError(_ ckError: CKError, originalNSError: NSError) -> ClassifiedCloudError {
        let nsError = ckError as NSError
        switch ckError.code {
        case .notAuthenticated:
            return ClassifiedCloudError(
                category: .iCloudUnavailable,
                underlying: nsError,
                userFacingMessage: "Sign in to iCloud in Settings to enable sync.",
                isTransient: true
            )

        case .accountTemporarilyUnavailable:
            return ClassifiedCloudError(
                category: .iCloudUnavailable,
                underlying: nsError,
                userFacingMessage: "iCloud is briefly unavailable. We'll retry automatically.",
                isTransient: true
            )

        case .userDeletedZone, .zoneNotFound:
            // For shared zones this means the share was deleted by its owner;
            // for private zones it can mean a destructive cloud reset.
            return ClassifiedCloudError(
                category: .shareDeleted,
                underlying: nsError,
                userFacingMessage: "A shared item is no longer available from its owner. Your local copy is kept.",
                isTransient: false
            )

        case .quotaExceeded:
            return ClassifiedCloudError(
                category: .quotaExceeded,
                underlying: nsError,
                userFacingMessage: "Your iCloud storage is full. New changes can't sync until space is freed.",
                isTransient: true
            )

        case .permissionFailure:
            return ClassifiedCloudError(
                category: .permissionFailure,
                underlying: nsError,
                userFacingMessage: "Permission denied for this iCloud action.",
                isTransient: false
            )

        case .networkUnavailable, .networkFailure:
            return ClassifiedCloudError(
                category: .networkFailure,
                underlying: nsError,
                userFacingMessage: "You're offline. Changes will sync when the network is back.",
                isTransient: true
            )

        case .requestRateLimited, .serviceUnavailable, .zoneBusy:
            return ClassifiedCloudError(
                category: .throttled,
                underlying: nsError,
                userFacingMessage: "iCloud is throttling sync requests. We'll back off and try again.",
                isTransient: true
            )

        case .serverRecordChanged:
            return ClassifiedCloudError(
                category: .conflict,
                underlying: nsError,
                userFacingMessage: "Sync conflict resolved.",
                isTransient: false
            )

        case .badContainer, .missingEntitlement, .badDatabase, .incompatibleVersion:
            return ClassifiedCloudError(
                category: .schemaMismatch,
                underlying: nsError,
                userFacingMessage: "Sync configuration error. Restart the app; if it persists, contact support.",
                isTransient: false
            )

        case .unknownItem, .invalidArguments:
            // Often appears mid-share-revocation. Treat as transient at the
            // network layer; the higher-level sharing flow decides whether to
            // mark a share as orphaned.
            return ClassifiedCloudError(
                category: .shareDeleted,
                underlying: nsError,
                userFacingMessage: "Couldn't find a synced item. It may have been removed from iCloud.",
                isTransient: false
            )

        case .changeTokenExpired:
            return ClassifiedCloudError(
                category: .throttled,
                underlying: nsError,
                userFacingMessage: "Sync needs to refresh. We'll handle this automatically.",
                isTransient: true
            )

        case .partialFailure:
            // CKError.partialFailure carries a per-record-ID dictionary of
            // sub-errors. Classify the first one we can find that isn't
            // .unknownItem (which is normal for missing records during a
            // batch op). Otherwise fall through to .unknown.
            if let partials = ckError.partialErrorsByItemID {
                for (_, sub) in partials {
                    if let subCK = sub as? CKError, subCK.code != .unknownItem {
                        return classifyCKError(subCK, originalNSError: nsError)
                    }
                }
            }
            return ClassifiedCloudError(
                category: .unknown,
                underlying: nsError,
                userFacingMessage: "Some items couldn't sync. We'll retry.",
                isTransient: true
            )

        default:
            return ClassifiedCloudError(
                category: .unknown,
                underlying: nsError,
                userFacingMessage: "Sync hit an unexpected CloudKit issue. Your data is safe locally.",
                isTransient: false
            )
        }
    }

    /// Some errors arrive wrapped in NSError's userInfo (e.g. from
    /// CoreData+CloudKit). Dig through and pull out a CKError if present.
    private static func findCKError(in nsError: NSError) -> CKError? {
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            if let ck = underlying as? CKError {
                return ck
            }
            return findCKError(in: underlying as NSError)
        }
        return nil
    }
}
