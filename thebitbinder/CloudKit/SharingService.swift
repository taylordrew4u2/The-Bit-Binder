//
//  SharingService.swift
//  thebitbinder
//
//  Bridges NSPersistentCloudKitContainer's share API to the rest of the app.
//
//  Responsibilities:
//   - Create a CKShare on the user's Workspace root (or return an existing one),
//     with duplicate-share protection via an in-flight Task gate.
//   - Look up the existing share, fetch participants, expose copy-invite-link.
//   - Accept incoming share invitations and route records into the
//     PersistenceController's `shared` store. Posts `bitBinderShareAccepted`
//     so the UI can welcome the new participant.
//   - Role-aware end-share: owner deletes the CKShare; participant purges the
//     shared zone locally so they leave cleanly.
//   - Provide a SwiftUI wrapper around UICloudSharingController for the iOS
//     standard share sheet.
//
//  Used by ShareLibraryView (user-facing) and WorkspaceDetailView (browse +
//  manage). Migration is handled by SwiftDataToCoreDataMigrator, invoked
//  silently the first time the user taps Share My Library.
//

import CloudKit
import CoreData
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted right after the user accepts a CKShare invitation. `userInfo`
    /// includes "ownerName" (String) when the metadata exposes the owner's
    /// identity, and "shareID" (String) carrying `share.recordID.recordName`.
    static let bitBinderShareAccepted = Notification.Name("bitBinderShareAccepted")
}

@MainActor
final class SharingService: NSObject, ObservableObject {

    static let shared = SharingService()

    private let persistence: PersistenceController = .shared

    @Published var lastError: ClassifiedCloudError?
    @Published var isPreparingShare = false

    /// Tracks an in-flight `prepareShare` so concurrent callers join the
    /// existing run instead of creating a duplicate CKShare.
    private var inFlightShareTask: Task<(CKShare, CKContainer), Error>?

    // MARK: - Share creation

    /// Creates a new CKShare for the given root object (typically a Workspace)
    /// or returns the existing share if one already exists. Safe to call
    /// concurrently — duplicate calls join the same in-flight task.
    func prepareShare(
        for rootObject: NSManagedObject
    ) async throws -> (CKShare, CKContainer) {
        // If an existing share is already on disk, return it directly without
        // any CloudKit round-trip.
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
        if let existing = try existingShare(for: rootObject) {
            return (existing, ckContainer)
        }

        // If another caller is already creating a share, wait for it.
        if let existingTask = inFlightShareTask {
            return try await existingTask.value
        }

        isPreparingShare = true
        let objectID = rootObject.objectID
        let container = persistence.container

        let task = Task<(CKShare, CKContainer), Error> { @MainActor in
            defer {
                self.isPreparingShare = false
                self.inFlightShareTask = nil
            }

            // Re-check inside the task — another concurrent caller may have
            // landed a share by the time we get here.
            let liveObject = container.viewContext.object(with: objectID)
            if let existing = try? self.existingShare(for: liveObject) {
                return (existing, ckContainer)
            }

            return try await withCheckedThrowingContinuation { continuation in
                container.share([liveObject], to: nil) { _, share, _, error in
                    if let error {
                        Task { @MainActor in
                            self.lastError = CloudErrorClassifier.classify(error)
                        }
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let share else {
                        let fallback = NSError(
                            domain: "SharingService",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "CloudKit returned no share object."]
                        )
                        continuation.resume(throwing: fallback)
                        return
                    }
                    share[CKShare.SystemFieldKey.title] = "The Bit Binder" as CKRecordValue
                    // Everyone invited gets the same access (read + write).
                    // Public link participants too — keeps the model simple.
                    share.publicPermission = .readWrite
                    continuation.resume(returning: (share, ckContainer))
                }
            }
        }

        inFlightShareTask = task
        return try await task.value
    }

    /// Returns the existing CKShare for the given object if one already
    /// exists in the user's private database, otherwise nil.
    func existingShare(for object: NSManagedObject) throws -> CKShare? {
        let container = persistence.container
        let sharesByID = try container.fetchShares(matching: [object.objectID])
        return sharesByID[object.objectID]
    }

    // MARK: - Incoming share acceptance

    /// Accepts an incoming share invitation. Call this from
    /// `UIWindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`
    /// or from `View.onContinueUserActivity` when the share URL is opened.
    func acceptShare(metadata: CKShare.Metadata) async {
        // Make sure the shared store is loaded; we need a real
        // NSPersistentStore to route incoming records into. Await — calling
        // `loadStores` without awaiting races against `store(for: .shared)`
        // below.
        do {
            try await persistence.loadStoresAsync()
        } catch {
            self.lastError = CloudErrorClassifier.classify(error)
            DataOperationLogger.shared.logError(
                error,
                operation: "SharingService.acceptShare",
                context: "loadStoresAsync failed before share routing"
            )
            return
        }

        guard let sharedStore = persistence.store(for: .shared) else {
            let err = NSError(
                domain: "SharingService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Shared persistent store not loaded; cannot accept share."]
            )
            self.lastError = CloudErrorClassifier.classify(err)
            DataOperationLogger.shared.logError(
                err,
                operation: "SharingService.acceptShare",
                context: "shared store missing after loadStoresAsync"
            )
            return
        }

        let container = persistence.container
        await withCheckedContinuation { continuation in
            container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                if let error {
                    Task { @MainActor in
                        self.lastError = CloudErrorClassifier.classify(error)
                        DataOperationLogger.shared.logError(
                            error,
                            operation: "SharingService.acceptShare",
                            context: "metadata.share=\(metadata.share.recordID.recordName)"
                        )
                    }
                } else {
                    DataOperationLogger.shared.logSuccess(
                        "Accepted share invitation: \(metadata.share.recordID.recordName)"
                    )
                    // Notify any open view that wants to surface a welcome
                    // banner (e.g. ShareLibraryView).
                    let ownerName = SharingService.displayName(for: metadata.ownerIdentity)
                    Task { @MainActor in
                        NotificationCenter.default.post(
                            name: .bitBinderShareAccepted,
                            object: nil,
                            userInfo: [
                                "ownerName": ownerName,
                                "shareID": metadata.share.recordID.recordName
                            ]
                        )
                    }
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Identity helpers

    /// Returns a friendly display name for a CloudKit user identity.
    /// Falls back gracefully: full name → email → phone → "Library owner".
    static func displayName(for identity: CKUserIdentity) -> String {
        if let first = identity.nameComponents?.givenName,
           let last = identity.nameComponents?.familyName {
            return "\(first) \(last)"
        }
        if let email = identity.lookupInfo?.emailAddress { return email }
        if let phone = identity.lookupInfo?.phoneNumber { return phone }
        return "Library owner"
    }

    // MARK: - Stop sharing / leave share

    /// True if the local user owns the share (vs. being a participant).
    func isOwner(of share: CKShare) -> Bool {
        share.owner.role == .owner
            && share.owner.userIdentity.userRecordID == share.currentUserParticipant?.userIdentity.userRecordID
    }

    /// End the user's relationship to a share appropriately:
    /// - Owner: deletes the CKShare from the private database, ending sharing
    ///   for everyone.
    /// - Participant: removes themselves from the share so they no longer
    ///   have access. The share keeps existing for the owner and remaining
    ///   participants.
    func endShare(_ share: CKShare) async {
        if isOwner(of: share) {
            await stopSharingAsOwner(share)
        } else {
            await leaveShareAsParticipant(share)
        }
    }

    /// Owner-side: deletes the CKShare so the workspace becomes private again.
    private func stopSharingAsOwner(_ share: CKShare) async {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
        do {
            _ = try await ckContainer.privateCloudDatabase.deleteRecord(withID: share.recordID)
            DataOperationLogger.shared.logSuccess(
                "Owner stopped sharing workspace (share \(share.recordID.recordName) deleted)"
            )
        } catch {
            self.lastError = CloudErrorClassifier.classify(error)
            DataOperationLogger.shared.logError(
                error,
                operation: "SharingService.stopSharingAsOwner",
                context: "share=\(share.recordID.recordName)"
            )
        }
    }

    /// Participant-side: removes the current user from the share so they
    /// lose access. The share remains for the owner and other participants.
    /// Uses `purgeObjectsAndRecordsInZone` to detach the local copy.
    private func leaveShareAsParticipant(_ share: CKShare) async {
        let zoneID = share.recordID.zoneID
        do {
            try await persistence.container.purgeObjectsAndRecordsInZone(with: zoneID, in: nil)
            DataOperationLogger.shared.logSuccess(
                "Participant left share (purged zone \(zoneID.zoneName))"
            )
        } catch {
            self.lastError = CloudErrorClassifier.classify(error)
            DataOperationLogger.shared.logError(
                error,
                operation: "SharingService.leaveShareAsParticipant",
                context: "zone=\(zoneID.zoneName)"
            )
        }
    }

}

// MARK: - SwiftUI wrapper for UICloudSharingController

/// SwiftUI sheet wrapper around UICloudSharingController. Present this when
/// the user taps "Share Workspace" — it handles invite, permission editing,
/// and stop-sharing UI provided by Apple.
struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onDismiss: () -> Void = {}

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // Everyone you invite gets the same level of access — read + write.
        // Removing the read-only / public-read options keeps the picker simple.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudSharingControllerView
        init(parent: CloudSharingControllerView) { self.parent = parent }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in
                SharingService.shared.lastError = CloudErrorClassifier.classify(error)
            }
            DataOperationLogger.shared.logError(
                error,
                operation: "UICloudSharingController.failedToSaveShare"
            )
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String ?? "The Bit Binder"
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            DataOperationLogger.shared.logSuccess("User stopped sharing via UICloudSharingController")
            parent.onDismiss()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            DataOperationLogger.shared.logSuccess("Share saved via UICloudSharingController")
        }
    }
}
