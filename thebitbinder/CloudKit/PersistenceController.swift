//
//  PersistenceController.swift
//  thebitbinder
//
//  NSPersistentCloudKitContainer with two stores:
//
//    1. `private.sqlite`  — backed by the user's CloudKit *private* database.
//                           Holds their personal Workspace.
//    2. `shared.sqlite`   — backed by the CloudKit *shared* database. Holds
//                           Workspaces accepted from share invitations sent
//                           by other iCloud users.
//
//  This stack runs in parallel with the existing SwiftData stack. It does NOT
//  yet replace SwiftData — see `SwiftDataToCoreDataMigrator` and the Phase 4
//  refactor for the cutover plan. Until then, this controller is dormant
//  unless explicitly initialized by debug / verification code paths.
//

import CoreData
import CloudKit
import Foundation

@MainActor
final class PersistenceController {

    static let shared = PersistenceController()

    /// CloudKit container identifier. Must match `thebitbinder.entitlements`
    /// (`com.apple.developer.icloud-container-identifiers`).
    static let cloudKitContainerIdentifier = "iCloud.The-BitBinder.thebitbinder"

    /// SQLite store name on disk for the user's private data.
    private static let privateStoreFilename = "BitBinder-private.sqlite"

    /// SQLite store name on disk for shares accepted from other iCloud accounts.
    private static let sharedStoreFilename = "BitBinder-shared.sqlite"

    /// Logical names used by NSPersistentStoreDescription. CloudKit uses these
    /// to disambiguate which database scope a record belongs to.
    static let privateStoreName = "Private"
    static let sharedStoreName = "Shared"

    /// The lazily-built container. Avoid touching this from the SwiftData code
    /// paths until the cutover is complete.
    let container: NSPersistentCloudKitContainer

    /// Set to `true` once `loadStores()` has succeeded at least once.
    private(set) var storesLoaded = false

    /// Last loader error, exposed for diagnostics.
    private(set) var lastLoadError: Error?

    /// Concurrent callers all park on the same in-flight load instead of
    /// kicking off a duplicate `loadPersistentStores` pass.
    private var inFlightLoadWaiters: [(Error?) -> Void] = []
    private var isLoading = false

    private init(inMemory: Bool = false) {
        let model = BitBinderModel.shared
        let container = NSPersistentCloudKitContainer(name: "BitBinder", managedObjectModel: model)

        let storeDirectory: URL = {
            do {
                return try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
            } catch {
                // Application Support is guaranteed to exist on iOS; if it
                // somehow doesn't, fall back to a temp directory so we don't
                // crash here. The load error will surface through
                // `lastLoadError` / `DataOperationLogger`.
                return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            }
        }()

        // -- Private store description ---------------------------------------
        let privateURL = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : storeDirectory.appendingPathComponent(Self.privateStoreFilename)
        let privateDescription = NSPersistentStoreDescription(url: privateURL)
        privateDescription.configuration = nil // default configuration covers all entities
        privateDescription.shouldInferMappingModelAutomatically = true
        privateDescription.shouldMigrateStoreAutomatically = true
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let privateOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerIdentifier
        )
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        // Give this description a stable logical name so we can identify it
        // later (e.g. for share routing).
        privateDescription.setOption(Self.privateStoreName as NSString, forKey: "name")

        // -- Shared store description ----------------------------------------
        let sharedURL = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : storeDirectory.appendingPathComponent(Self.sharedStoreFilename)
        let sharedDescription = NSPersistentStoreDescription(url: sharedURL)
        sharedDescription.configuration = nil
        sharedDescription.shouldInferMappingModelAutomatically = true
        sharedDescription.shouldMigrateStoreAutomatically = true
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let sharedOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerIdentifier
        )
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions
        sharedDescription.setOption(Self.sharedStoreName as NSString, forKey: "name")

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        self.container = container

        // Conflict resolution: when local and remote both change the same
        // attribute, the in-memory object's value wins. CloudKit pushes
        // arriving via remote change notifications will then re-merge.
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.transactionAuthor = "thebitbinder.app"
    }

    /// Loads both store descriptions. Safe to call multiple times — concurrent
    /// callers all park on the same in-flight load.
    func loadStores(completion: ((Error?) -> Void)? = nil) {
        if storesLoaded {
            completion?(nil)
            return
        }
        if isLoading {
            if let completion { inFlightLoadWaiters.append(completion) }
            return
        }

        isLoading = true
        if let completion { inFlightLoadWaiters.append(completion) }

        var pendingCount = container.persistentStoreDescriptions.count
        var firstError: Error?

        container.loadPersistentStores { [weak self] description, error in
            pendingCount -= 1
            if let error {
                firstError = firstError ?? error
                let storeName = description.url?.lastPathComponent ?? "<unknown>"
                DataOperationLogger.shared.logError(
                    error,
                    operation: "PersistenceController.loadPersistentStores",
                    context: "Store '\(storeName)' (scope: \(description.cloudKitContainerOptions?.databaseScope.rawValue ?? -1)) failed to load"
                )
            }
            if pendingCount == 0 {
                Task { @MainActor in
                    guard let self else { return }
                    self.lastLoadError = firstError
                    self.storesLoaded = (firstError == nil)
                    self.isLoading = false
                    if firstError == nil {
                        DataOperationLogger.shared.logSuccess("PersistenceController loaded both private + shared stores")
                    }
                    let waiters = self.inFlightLoadWaiters
                    self.inFlightLoadWaiters.removeAll()
                    for waiter in waiters {
                        waiter(firstError)
                    }
                }
            }
        }
    }

    /// Async wrapper around `loadStores`. Safe to call concurrently; all
    /// callers resume once the single in-flight load completes.
    func loadStoresAsync() async throws {
        if storesLoaded {
            if let lastLoadError {
                throw lastLoadError
            }
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadStores { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Helpers

    /// Returns the persistent store with the given logical scope, or nil if it
    /// hasn't been loaded yet.
    func store(for scope: CKDatabase.Scope) -> NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            guard let description = container.persistentStoreDescriptions.first(where: { $0.url == store.url }),
                  let options = description.cloudKitContainerOptions else {
                return false
            }
            return options.databaseScope == scope
        }
    }

    /// True if the given object lives in the shared store (i.e. it came from
    /// another iCloud user's share). Use this to render UI badges and to
    /// gate edits on participant-role objects.
    func isShared(_ object: NSManagedObject) -> Bool {
        guard let objectStore = object.objectID.persistentStore else { return false }
        return objectStore == store(for: .shared)
    }

    /// Returns the user's Workspace root, or nil if migration hasn't created
    /// one yet. Searches the private store first; falls back to any store.
    func currentWorkspace() throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: BitBinderEntity.workspace.rawValue)
        request.fetchLimit = 1
        if let privateStore = store(for: .private) {
            request.affectedStores = [privateStore]
        }
        return try container.viewContext.fetch(request).first
    }
}
