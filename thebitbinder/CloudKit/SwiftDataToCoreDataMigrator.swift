//
//  SwiftDataToCoreDataMigrator.swift
//  thebitbinder
//
//  One-shot migrator from the existing SwiftData store (`default.store`) into
//  the new Core Data + CloudKit store (`BitBinder-private.sqlite`).
//
//  Design rules
//  ------------
//  1. Migration is gated by `UserDefaults["DidMigrateToCoreData_v1"]`.
//  2. The SwiftData store is NEVER deleted by this migrator. After migration
//     it is left in place as a recoverable snapshot.
//  3. We do not promote the new Core Data store until ALL copies succeed.
//     If anything throws, the partial Core Data writes remain in their store
//     file (Core Data has no transactional rollback for cross-context writes)
//     but `didMigrateKey` is never flipped, so:
//       - next launch the SwiftData stack is still authoritative,
//       - the partial Core Data store is overwritten on the next attempt.
//  4. UUIDs from SwiftData are preserved as the `id` attribute on every
//     managed object. CloudKit uses these as stable record identifiers.
//  5. External-storage blobs (RoastTarget.photoData,
//     NotebookPhotoRecord.imageData) are copied byte-for-byte through Core
//     Data's external-storage mechanism — just setting the Data attribute is
//     enough; Core Data stores it externally automatically.
//

import CoreData
import Foundation
import SwiftData

@MainActor
final class SwiftDataToCoreDataMigrator: ObservableObject {

    static let shared = SwiftDataToCoreDataMigrator()

    private let didMigrateKey = "DidMigrateToCoreData_v1"
    private let migrationStageKey = "MigrateToCoreData_v1_Stage"
    private let migrationStartedAtKey = "MigrateToCoreData_v1_StartedAt"
    private let migrationCompletedAtKey = "MigrateToCoreData_v1_CompletedAt"

    /// Human-readable description of the current stage. Empty when idle.
    /// Observable so UI can show step-by-step messages.
    @Published private(set) var liveStageMessage: String = ""

    /// Running per-entity counts of what's been copied so far.
    @Published private(set) var liveCounts: [String: Int] = [:]

    /// Skip counters per entity — rows that were already present and didn't
    /// need to be re-copied. Used to assure the user nothing is duplicated.
    @Published private(set) var liveSkipped: [String: Int] = [:]

    /// True while `runIfNeeded()` is actively running.
    @Published private(set) var isRunning: Bool = false

    /// Tracks an in-flight migration so concurrent calls join the same run
    /// instead of starting a duplicate copy pass.
    private var inFlightRun: Task<MigrationReport?, Never>?

    enum Stage: String {
        case notStarted
        case openingSwiftData
        case loadingCoreDataStores
        case copyingWorkspaceRoot
        case copyingFolders
        case copyingContainers
        case copyingPrimaryRecords
        case copyingDependentRecords
        case finalizing
        case completed
        case failed
    }

    struct MigrationReport {
        var entitiesCopied: [String: Int] = [:]
        var externalBlobsCopied: Int = 0
        var failures: [String] = []
        var startedAt: Date
        var finishedAt: Date?

        mutating func bump(_ entity: String, by count: Int = 1) {
            entitiesCopied[entity, default: 0] += count
        }
    }

    enum MigrationError: LocalizedError {
        case swiftDataContainerUnavailable(Error)
        case coreDataStoresFailedToLoad(Error)
        case workspaceCreationFailed
        case saveFailed(stage: Stage, error: Error)

        var errorDescription: String? {
            switch self {
            case .swiftDataContainerUnavailable(let err):
                return "Could not open SwiftData store for migration read: \(err.localizedDescription)"
            case .coreDataStoresFailedToLoad(let err):
                return "Could not load Core Data stores: \(err.localizedDescription)"
            case .workspaceCreationFailed:
                return "Could not create the new Workspace root."
            case .saveFailed(let stage, let err):
                return "Save failed during stage \(stage.rawValue): \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Public API

    var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: didMigrateKey)
    }

    var currentStage: Stage {
        let raw = UserDefaults.standard.string(forKey: migrationStageKey) ?? Stage.notStarted.rawValue
        return Stage(rawValue: raw) ?? .notStarted
    }

    /// Runs the migration once. Subsequent calls return immediately if the
    /// migration has already completed, or join the in-flight run if one is
    /// already underway.
    @discardableResult
    func runIfNeeded() async -> MigrationReport? {
        if hasMigrated {
            DataOperationLogger.shared.logInfo("Migration already completed; skipping")
            return nil
        }
        if let existing = inFlightRun {
            // A migration is already running — wait for the same one to finish
            // instead of starting a parallel copy pass that would duplicate.
            return await existing.value
        }

        let task = Task<MigrationReport?, Never> { @MainActor in
            await performRun()
        }
        inFlightRun = task
        let result = await task.value
        inFlightRun = nil
        return result
    }

    private func performRun() async -> MigrationReport? {
        isRunning = true
        liveCounts = [:]
        liveSkipped = [:]
        defer {
            isRunning = false
            liveStageMessage = ""
        }

        var report = MigrationReport(startedAt: Date())
        UserDefaults.standard.set(report.startedAt.timeIntervalSince1970, forKey: migrationStartedAtKey)
        DataOperationLogger.shared.logSuccess("Starting SwiftData → Core Data migration")

        do {
            // -- Open SwiftData read source ------------------------------
            advance(to: .openingSwiftData, message: "Opening your existing library…")
            let swiftDataContainer = try openSwiftDataReader()
            let readContext = swiftDataContainer.mainContext

            // -- Load Core Data destination stores ------------------------
            advance(to: .loadingCoreDataStores, message: "Connecting to iCloud…")
            try await ensureCoreDataStoresLoaded()
            let writeContext = PersistenceController.shared.container.viewContext

            // -- Copy workspace root --------------------------------------
            advance(to: .copyingWorkspaceRoot, message: "Preparing your shared library…")
            let workspace = try createWorkspace(in: writeContext)
            report.bump("Workspace")
            try save(writeContext, stage: .copyingWorkspaceRoot)

            // Containers and primary records first establish the relationship
            // targets that dependent records will reference. Track UUID→MO
            // maps so cross-entity links can be re-established.
            var jokeFolderMap: [UUID: NSManagedObject] = [:]
            var notebookFolderMap: [UUID: NSManagedObject] = [:]
            var roastTargetMap: [UUID: NSManagedObject] = [:]
            var importBatchMap: [UUID: NSManagedObject] = [:]
            var jokeMap: [UUID: NSManagedObject] = [:]

            // -- Folders --------------------------------------------------
            advance(to: .copyingFolders, message: "Copying joke folders…")
            try copyJokeFolders(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                map: &jokeFolderMap,
                report: &report
            )
            advance(to: .copyingFolders, message: "Copying notebook folders…")
            try copyNotebookFolders(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                map: &notebookFolderMap,
                report: &report
            )
            try save(writeContext, stage: .copyingFolders)

            // -- Containers (SetList, RoastTarget, ImportBatch) ------------
            advance(to: .copyingContainers, message: "Copying set lists…")
            try copySetLists(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                report: &report
            )
            advance(to: .copyingContainers, message: "Copying roast targets…")
            try copyRoastTargets(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                map: &roastTargetMap,
                report: &report
            )
            advance(to: .copyingContainers, message: "Copying import history…")
            try copyImportBatches(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                map: &importBatchMap,
                report: &report
            )
            try save(writeContext, stage: .copyingContainers)

            // -- Primary records -----------------------------------------
            advance(to: .copyingPrimaryRecords, message: "Copying your jokes…")
            try copyJokes(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                jokeFolderMap: jokeFolderMap,
                map: &jokeMap,
                report: &report
            )
            advance(to: .copyingPrimaryRecords, message: "Copying your roast jokes…")
            try copyRoastJokes(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                roastTargetMap: roastTargetMap,
                report: &report
            )
            advance(to: .copyingPrimaryRecords, message: "Copying brainstorm ideas…")
            try copyBrainstormIdeas(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                report: &report
            )
            advance(to: .copyingPrimaryRecords, message: "Copying recordings…")
            try copyRecordings(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                report: &report
            )
            try save(writeContext, stage: .copyingPrimaryRecords)

            // -- Dependent records ---------------------------------------
            advance(to: .copyingDependentRecords, message: "Copying notebook photos…")
            try copyNotebookPhotos(
                from: readContext,
                into: writeContext,
                workspace: workspace,
                notebookFolderMap: notebookFolderMap,
                report: &report
            )
            advance(to: .copyingDependentRecords, message: "Copying imported joke details…")
            try copyImportedJokeMetadata(
                from: readContext,
                into: writeContext,
                importBatchMap: importBatchMap,
                report: &report
            )
            advance(to: .copyingDependentRecords, message: "Copying unresolved import fragments…")
            try copyUnresolvedImportFragments(
                from: readContext,
                into: writeContext,
                importBatchMap: importBatchMap,
                report: &report
            )
            try save(writeContext, stage: .copyingDependentRecords)



            // -- Finalize ------------------------------------------------
            advance(to: .finalizing, message: "Finishing up…")
            UserDefaults.standard.set(true, forKey: didMigrateKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: migrationCompletedAtKey)

            advance(to: .completed)
            report.finishedAt = Date()
            DataOperationLogger.shared.logSuccess(
                "Migration completed: \(report.entitiesCopied.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"
            )
            return report

        } catch {
            advance(to: .failed)
            DataOperationLogger.shared.logCritical(
                "Migration aborted: \(error.localizedDescription) — SwiftData store left untouched, didMigrateKey NOT set"
            )
            report.failures.append(error.localizedDescription)
            report.finishedAt = Date()
            return report
        }
    }

    // MARK: - SwiftData read source

    /// Opens a *read* connection to the existing SwiftData store at the same
    /// path the app already uses, without enabling CloudKit (so we don't
    /// duplicate sync traffic) and without inferring schema migrations from
    /// scratch.
    private func openSwiftDataReader() throws -> ModelContainer {
        let schema = Schema([
            Joke.self,
            JokeFolder.self,
            Recording.self,
            SetList.self,
            NotebookPhotoRecord.self,
            NotebookFolder.self,
            RoastTarget.self,
            RoastJoke.self,
            BrainstormIdea.self,
            ImportBatch.self,
            ImportedJokeMetadata.self,
            UnresolvedImportFragment.self,
        ])

        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        let config = ModelConfiguration(
            "BitBinderStore",
            schema: schema,
            url: storeURL,
            allowsSave: false,            // read-only — we never mutate the source
            cloudKitDatabase: .none       // never touch CloudKit from the reader
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            throw MigrationError.swiftDataContainerUnavailable(error)
        }
    }

    private func ensureCoreDataStoresLoaded() async throws {
        do {
            try await PersistenceController.shared.loadStoresAsync()
        } catch {
            throw MigrationError.coreDataStoresFailedToLoad(error)
        }
    }

    // MARK: - Workspace root

    private func createWorkspace(in ctx: NSManagedObjectContext) throws -> NSManagedObject {
        // If a workspace already exists from a prior partial run, reuse it.
        if let existing = try fetchSingle(entity: .workspace, in: ctx) {
            return existing
        }
        guard let entity = NSEntityDescription.entity(forEntityName: BitBinderEntity.workspace.rawValue, in: ctx) else {
            throw MigrationError.workspaceCreationFailed
        }
        let ws = NSManagedObject(entity: entity, insertInto: ctx)
        ws.setValue(UUID(), forKey: "id")
        ws.setValue(Date(), forKey: "dateCreated")
        return ws
    }

    // MARK: - Entity copies

    private func copyJokeFolders(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        map: inout [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let folders = try src.fetch(FetchDescriptor<JokeFolder>())
        let alreadyImported = try existingIDs(entity: .jokeFolder, in: dst)
        for f in folders {
            if alreadyImported.contains(f.id) {
                bumpSkipped(entity: "JokeFolder")
                // Hydrate the map so dependent records can still link to the
                // existing row.
                let req = NSFetchRequest<NSManagedObject>(entityName: BitBinderEntity.jokeFolder.rawValue)
                req.predicate = NSPredicate(format: "id == %@", f.id as CVarArg)
                req.fetchLimit = 1
                if let existing = try dst.fetch(req).first {
                    map[f.id] = existing
                }
                continue
            }
            let mo = try make(.jokeFolder, in: dst)
            mo.setValue(f.id, forKey: "id")
            mo.setValue(f.name, forKey: "name")
            mo.setValue(f.dateCreated, forKey: "dateCreated")
            mo.setValue(f.isRecentlyAdded, forKey: "isRecentlyAdded")
            mo.setValue(f.isTrashed, forKey: "isTrashed")
            mo.setValue(f.deletedDate, forKey: "deletedDate")
            mo.setValue(workspace, forKey: "workspace")
            map[f.id] = mo
            report.bump("JokeFolder")
            bumpLive(entity: "JokeFolder")
        }
    }

    private func copyNotebookFolders(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        map: inout [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let folders = try src.fetch(FetchDescriptor<NotebookFolder>())
        let alreadyImported = try existingIDs(entity: .notebookFolder, in: dst)
        for f in folders {
            if alreadyImported.contains(f.id) {
                bumpSkipped(entity: "NotebookFolder")
                if let existing = try fetchByID(.notebookFolder, id: f.id, in: dst) {
                    map[f.id] = existing
                }
                continue
            }
            let mo = try make(.notebookFolder, in: dst)
            mo.setValue(f.id, forKey: "id")
            mo.setValue(f.name, forKey: "name")
            mo.setValue(f.dateCreated, forKey: "dateCreated")
            mo.setValue(Int64(f.sortOrder), forKey: "sortOrder")
            mo.setValue(f.isTrashed, forKey: "isTrashed")
            mo.setValue(f.deletedDate, forKey: "deletedDate")
            mo.setValue(workspace, forKey: "workspace")
            map[f.id] = mo
            report.bump("NotebookFolder")
            bumpLive(entity: "NotebookFolder")
        }
    }

    private func copySetLists(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        report: inout MigrationReport
    ) throws {
        let sets = try src.fetch(FetchDescriptor<SetList>())
        let alreadyImported = try existingIDs(entity: .setList, in: dst)
        for s in sets {
            if alreadyImported.contains(s.id) {
                bumpSkipped(entity: "SetList")
                continue
            }
            let mo = try make(.setList, in: dst)
            mo.setValue(s.id, forKey: "id")
            mo.setValue(s.name, forKey: "name")
            mo.setValue(s.dateCreated, forKey: "dateCreated")
            mo.setValue(s.dateModified, forKey: "dateModified")
            mo.setValue(s.notes, forKey: "notes")
            mo.setValue(s.isTrashed, forKey: "isTrashed")
            mo.setValue(s.deletedDate, forKey: "deletedDate")
            mo.setValue(s.isFinalized, forKey: "isFinalized")
            mo.setValue(s.finalizedDate, forKey: "finalizedDate")
            mo.setValue(Int32(s.estimatedMinutes), forKey: "estimatedMinutes")
            mo.setValue(s.venueName, forKey: "venueName")
            mo.setValue(s.performanceDate, forKey: "performanceDate")
            mo.setValue(s.jokeIDs.map(\.uuidString).joined(separator: ","), forKey: "jokeIDsString")
            mo.setValue(s.roastJokeIDs.map(\.uuidString).joined(separator: ","), forKey: "roastJokeIDsString")
            mo.setValue(workspace, forKey: "workspace")
            report.bump("SetList")
            bumpLive(entity: "SetList")
        }
    }

    private func copyRoastTargets(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        map: inout [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let targets = try src.fetch(FetchDescriptor<RoastTarget>())
        let alreadyImported = try existingIDs(entity: .roastTarget, in: dst)
        for t in targets {
            if alreadyImported.contains(t.id) {
                bumpSkipped(entity: "RoastTarget")
                if let existing = try fetchByID(.roastTarget, id: t.id, in: dst) {
                    map[t.id] = existing
                }
                continue
            }
            let mo = try make(.roastTarget, in: dst)
            mo.setValue(t.id, forKey: "id")
            mo.setValue(t.name, forKey: "name")
            mo.setValue(t.notes, forKey: "notes")
            mo.setValue(encodeStringArray(t.traits), forKey: "traitsData")
            mo.setValue(t.photoData, forKey: "photoData")
            mo.setValue(t.dateCreated, forKey: "dateCreated")
            mo.setValue(t.dateModified, forKey: "dateModified")
            mo.setValue(Int16(t.openingRoastCount), forKey: "openingRoastCount")
            mo.setValue(t.isTrashed, forKey: "isTrashed")
            mo.setValue(t.deletedDate, forKey: "deletedDate")
            mo.setValue(workspace, forKey: "workspace")
            map[t.id] = mo
            if t.photoData != nil { report.externalBlobsCopied += 1 }
            report.bump("RoastTarget")
            bumpLive(entity: "RoastTarget")
        }
    }

    private func copyImportBatches(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        map: inout [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let batches = try src.fetch(FetchDescriptor<ImportBatch>())
        let alreadyImported = try existingIDs(entity: .importBatch, in: dst)
        for b in batches {
            if alreadyImported.contains(b.id) {
                bumpSkipped(entity: "ImportBatch")
                if let existing = try fetchByID(.importBatch, id: b.id, in: dst) {
                    map[b.id] = existing
                }
                continue
            }
            let mo = try make(.importBatch, in: dst)
            mo.setValue(b.id, forKey: "id")
            mo.setValue(b.sourceFileName, forKey: "sourceFileName")
            mo.setValue(b.importTimestamp, forKey: "importTimestamp")
            mo.setValue(Int32(b.totalSegments), forKey: "totalSegments")
            mo.setValue(Int32(b.totalImportedRecords), forKey: "totalImportedRecords")
            mo.setValue(Int32(b.unresolvedFragmentCount), forKey: "unresolvedFragmentCount")
            mo.setValue(Int32(b.highConfidenceBoundaries), forKey: "highConfidenceBoundaries")
            mo.setValue(Int32(b.mediumConfidenceBoundaries), forKey: "mediumConfidenceBoundaries")
            mo.setValue(Int32(b.lowConfidenceBoundaries), forKey: "lowConfidenceBoundaries")
            mo.setValue(b.extractionMethod, forKey: "extractionMethod")
            mo.setValue(b.pipelineVersion, forKey: "pipelineVersion")
            mo.setValue(b.processingTimeSeconds, forKey: "processingTimeSeconds")
            mo.setValue(Int32(b.autoSavedCount), forKey: "autoSavedCount")
            mo.setValue(Int32(b.reviewQueueCount), forKey: "reviewQueueCount")
            mo.setValue(Int32(b.rejectedCount), forKey: "rejectedCount")
            mo.setValue(workspace, forKey: "workspace")
            map[b.id] = mo
            report.bump("ImportBatch")
            bumpLive(entity: "ImportBatch")
        }
    }

    private func copyJokes(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        jokeFolderMap: [UUID: NSManagedObject],
        map: inout [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let jokes = try src.fetch(FetchDescriptor<Joke>())
        let alreadyImported = try existingIDs(entity: .joke, in: dst)
        for j in jokes {
            if alreadyImported.contains(j.id) {
                bumpSkipped(entity: "Joke")
                if let existing = try fetchByID(.joke, id: j.id, in: dst) {
                    map[j.id] = existing
                }
                continue
            }
            let mo = try make(.joke, in: dst)
            mo.setValue(j.id, forKey: "id")
            mo.setValue(j.content, forKey: "content")
            mo.setValue(j.title, forKey: "title")
            mo.setValue(j.dateCreated, forKey: "dateCreated")
            mo.setValue(j.dateModified, forKey: "dateModified")
            mo.setValue(j.isTrashed, forKey: "isTrashed")
            mo.setValue(j.deletedDate, forKey: "deletedDate")
            // categorizationResultsData is private in the SwiftData class; we
            // pull from the public computed wrapper instead.
            if let encoded = try? JSONEncoder().encode(j.categorizationResults) {
                mo.setValue(encoded, forKey: "categorizationResultsData")
            }
            mo.setValue(j.primaryCategory, forKey: "primaryCategory")
            mo.setValue(j.allCategories.joined(separator: ","), forKey: "allCategoriesString")
            mo.setValue(encodeCategoryScores(j.categoryConfidenceScores), forKey: "categoryScoresString")
            mo.setValue(j.styleTags.joined(separator: "|"), forKey: "styleTagsString")
            mo.setValue(j.craftNotes.joined(separator: "|"), forKey: "craftNotesString")
            mo.setValue(j.comedicTone, forKey: "comedicTone")
            mo.setValue(j.structureScore, forKey: "structureScore")
            mo.setValue(j.category, forKey: "category")
            mo.setValue(j.tags.joined(separator: ","), forKey: "tagsString")
            mo.setValue(j.difficulty, forKey: "difficulty")
            mo.setValue(Int16(j.humorRating), forKey: "humorRating")
            mo.setValue(j.isHit, forKey: "isHit")
            mo.setValue(j.isOpenMic, forKey: "isOpenMic")
            mo.setValue(Int32(j.wordCount), forKey: "wordCount")
            mo.setValue(j.notes, forKey: "notes")
            mo.setValue(j.importSource, forKey: "importSource")
            mo.setValue(j.importConfidence, forKey: "importConfidence")
            mo.setValue(j.importTimestamp, forKey: "importTimestamp")
            mo.setValue(workspace, forKey: "workspace")

            // Many-to-many folder edges
            let folderMOs = (j.folders ?? []).compactMap { jokeFolderMap[$0.id] }
            if !folderMOs.isEmpty {
                mo.setValue(NSSet(array: folderMOs), forKey: "folders")
            }

            map[j.id] = mo
            report.bump("Joke")
            bumpLive(entity: "Joke")
        }
    }

    private func copyRoastJokes(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        roastTargetMap: [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let jokes = try src.fetch(FetchDescriptor<RoastJoke>())
        let alreadyImported = try existingIDs(entity: .roastJoke, in: dst)
        for j in jokes {
            if alreadyImported.contains(j.id) {
                bumpSkipped(entity: "RoastJoke")
                continue
            }
            let mo = try make(.roastJoke, in: dst)
            mo.setValue(j.id, forKey: "id")
            mo.setValue(j.content, forKey: "content")
            mo.setValue(j.title, forKey: "title")
            mo.setValue(j.dateCreated, forKey: "dateCreated")
            mo.setValue(j.dateModified, forKey: "dateModified")
            mo.setValue(j.isTrashed, forKey: "isTrashed")
            mo.setValue(j.deletedDate, forKey: "deletedDate")
            mo.setValue(j.setup, forKey: "setup")
            mo.setValue(j.punchline, forKey: "punchline")
            mo.setValue(j.performanceNotes, forKey: "performanceNotes")
            mo.setValue(Int16(j.relatabilityScore), forKey: "relatabilityScore")
            mo.setValue(j.isTested, forKey: "isTested")
            mo.setValue(j.lastPerformedDate, forKey: "lastPerformedDate")
            mo.setValue(Int32(j.performanceCount), forKey: "performanceCount")
            mo.setValue(Int32(j.displayOrder), forKey: "displayOrder")
            mo.setValue(j.isKiller, forKey: "isKiller")
            mo.setValue(j.isOpeningRoast, forKey: "isOpeningRoast")
            mo.setValue(j.parentOpeningRoastID, forKey: "parentOpeningRoastID")
            mo.setValue(j.tags.joined(separator: ","), forKey: "tagsString")
            mo.setValue(workspace, forKey: "workspace")
            if let targetID = j.target?.id, let targetMO = roastTargetMap[targetID] {
                mo.setValue(targetMO, forKey: "target")
            }
            report.bump("RoastJoke")
            bumpLive(entity: "RoastJoke")
        }
    }

    private func copyBrainstormIdeas(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        report: inout MigrationReport
    ) throws {
        let ideas = try src.fetch(FetchDescriptor<BrainstormIdea>())
        let alreadyImported = try existingIDs(entity: .brainstormIdea, in: dst)
        for i in ideas {
            if alreadyImported.contains(i.id) {
                bumpSkipped(entity: "BrainstormIdea")
                continue
            }
            let mo = try make(.brainstormIdea, in: dst)
            mo.setValue(i.id, forKey: "id")
            mo.setValue(i.content, forKey: "content")
            mo.setValue(i.dateCreated, forKey: "dateCreated")
            mo.setValue(i.colorHex, forKey: "colorHex")
            mo.setValue(i.boardPositionX, forKey: "boardPositionX")
            mo.setValue(i.boardPositionY, forKey: "boardPositionY")
            mo.setValue(i.isVoiceNote, forKey: "isVoiceNote")
            mo.setValue(i.notes, forKey: "notes")
            mo.setValue(i.isTrashed, forKey: "isTrashed")
            mo.setValue(i.deletedDate, forKey: "deletedDate")
            mo.setValue(workspace, forKey: "workspace")
            report.bump("BrainstormIdea")
            bumpLive(entity: "BrainstormIdea")
        }
    }

    private func copyRecordings(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        report: inout MigrationReport
    ) throws {
        let recs = try src.fetch(FetchDescriptor<Recording>())
        let alreadyImported = try existingIDs(entity: .recording, in: dst)
        for r in recs {
            if alreadyImported.contains(r.id) {
                bumpSkipped(entity: "Recording")
                continue
            }
            let mo = try make(.recording, in: dst)
            mo.setValue(r.id, forKey: "id")
            mo.setValue(r.title, forKey: "title")
            mo.setValue(r.dateCreated, forKey: "dateCreated")
            mo.setValue(r.duration, forKey: "duration")
            mo.setValue(r.fileURL, forKey: "fileURL")
            mo.setValue(r.transcription, forKey: "transcription")
            mo.setValue(r.isProcessed, forKey: "isProcessed")
            mo.setValue(r.isTrashed, forKey: "isTrashed")
            mo.setValue(r.deletedDate, forKey: "deletedDate")
            mo.setValue(workspace, forKey: "workspace")
            report.bump("Recording")
            bumpLive(entity: "Recording")
        }
    }

    private func copyNotebookPhotos(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        workspace: NSManagedObject,
        notebookFolderMap: [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let photos = try src.fetch(FetchDescriptor<NotebookPhotoRecord>())
        let alreadyImported = try existingIDs(entity: .notebookPhotoRecord, in: dst)
        for p in photos {
            if alreadyImported.contains(p.id) {
                bumpSkipped(entity: "NotebookPhotoRecord")
                continue
            }
            let mo = try make(.notebookPhotoRecord, in: dst)
            mo.setValue(p.id, forKey: "id")
            mo.setValue(p.notes, forKey: "notes")
            mo.setValue(p.imageData, forKey: "imageData")
            mo.setValue(p.dateAdded, forKey: "dateAdded")
            mo.setValue(Int64(p.sortOrder), forKey: "sortOrder")
            mo.setValue(p.isTrashed, forKey: "isTrashed")
            mo.setValue(p.deletedDate, forKey: "deletedDate")
            if let folderID = p.folder?.id, let folderMO = notebookFolderMap[folderID] {
                mo.setValue(folderMO, forKey: "folder")
            }
            mo.setValue(workspace, forKey: "workspace")
            if p.imageData != nil { report.externalBlobsCopied += 1 }
            report.bump("NotebookPhotoRecord")
            bumpLive(entity: "NotebookPhotoRecord")
        }
    }

    private func copyImportedJokeMetadata(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        importBatchMap: [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let records = try src.fetch(FetchDescriptor<ImportedJokeMetadata>())
        let alreadyImported = try existingIDs(entity: .importedJokeMetadata, in: dst)
        for r in records {
            if alreadyImported.contains(r.id) {
                bumpSkipped(entity: "ImportedJokeMetadata")
                continue
            }
            let mo = try make(.importedJokeMetadata, in: dst)
            mo.setValue(r.id, forKey: "id")
            mo.setValue(r.jokeID, forKey: "jokeID")
            mo.setValue(r.title, forKey: "title")
            mo.setValue(r.rawSourceText, forKey: "rawSourceText")
            mo.setValue(r.notes, forKey: "notes")
            mo.setValue(r.confidence, forKey: "confidence")
            mo.setValue(Int32(r.sourceOrder), forKey: "sourceOrder")
            if let sp = r.sourcePage {
                mo.setValue(Int32(sp), forKey: "sourcePage")
            }
            mo.setValue(r.tags.joined(separator: "|"), forKey: "tagsString")
            mo.setValue(r.parsingFlagsJSON, forKey: "parsingFlagsJSON")
            mo.setValue(r.sourceFilename, forKey: "sourceFilename")
            mo.setValue(r.importTimestamp, forKey: "importTimestamp")
            mo.setValue(r.extractionMethod, forKey: "extractionMethod")
            mo.setValue(r.confidenceScore, forKey: "confidenceScore")
            mo.setValue(r.extractionQuality, forKey: "extractionQuality")
            mo.setValue(r.structuralCleanliness, forKey: "structuralCleanliness")
            mo.setValue(r.titleDetectionScore, forKey: "titleDetectionScore")
            mo.setValue(r.boundaryClarity, forKey: "boundaryClarity")
            mo.setValue(r.ocrConfidence, forKey: "ocrConfidence")
            mo.setValue(r.validationResult, forKey: "validationResult")
            mo.setValue(r.needsReview, forKey: "needsReview")
            if let batchID = r.batch?.id, let batchMO = importBatchMap[batchID] {
                mo.setValue(batchMO, forKey: "batch")
            }
            report.bump("ImportedJokeMetadata")
            bumpLive(entity: "ImportedJokeMetadata")
        }
    }

    private func copyUnresolvedImportFragments(
        from src: ModelContext,
        into dst: NSManagedObjectContext,
        importBatchMap: [UUID: NSManagedObject],
        report: inout MigrationReport
    ) throws {
        let frags = try src.fetch(FetchDescriptor<UnresolvedImportFragment>())
        let alreadyImported = try existingIDs(entity: .unresolvedImportFragment, in: dst)
        for f in frags {
            if alreadyImported.contains(f.id) {
                bumpSkipped(entity: "UnresolvedImportFragment")
                continue
            }
            let mo = try make(.unresolvedImportFragment, in: dst)
            mo.setValue(f.id, forKey: "id")
            mo.setValue(f.text, forKey: "text")
            mo.setValue(f.normalizedText, forKey: "normalizedText")
            mo.setValue(f.kind, forKey: "kind")
            mo.setValue(f.confidence, forKey: "confidence")
            mo.setValue(Int32(f.sourceOrder), forKey: "sourceOrder")
            if let sp = f.sourcePage {
                mo.setValue(Int32(sp), forKey: "sourcePage")
            }
            mo.setValue(f.sourceFilename, forKey: "sourceFilename")
            mo.setValue(f.titleCandidate, forKey: "titleCandidate")
            mo.setValue(f.tags.joined(separator: "|"), forKey: "tagsString")
            mo.setValue(f.parsingFlagsJSON, forKey: "parsingFlagsJSON")
            mo.setValue(f.createdAt, forKey: "createdAt")
            mo.setValue(f.isResolved, forKey: "isResolved")
            mo.setValue(f.validationResult, forKey: "validationResult")
            mo.setValue(f.issuesJSON, forKey: "issuesJSON")
            mo.setValue(f.confidenceScore, forKey: "confidenceScore")
            if let batchID = f.batch?.id, let batchMO = importBatchMap[batchID] {
                mo.setValue(batchMO, forKey: "batch")
            }
            report.bump("UnresolvedImportFragment")
            bumpLive(entity: "UnresolvedImportFragment")
        }
    }

    // MARK: - Helpers

    private func make(_ entity: BitBinderEntity, in ctx: NSManagedObjectContext) throws -> NSManagedObject {
        guard let desc = NSEntityDescription.entity(forEntityName: entity.rawValue, in: ctx) else {
            throw MigrationError.workspaceCreationFailed
        }
        return NSManagedObject(entity: desc, insertInto: ctx)
    }

    private func fetchSingle(entity: BitBinderEntity, in ctx: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity.rawValue)
        request.fetchLimit = 1
        return try ctx.fetch(request).first
    }

    private func fetchByID(_ entity: BitBinderEntity, id: UUID, in ctx: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity.rawValue)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try ctx.fetch(request).first
    }

    private func save(_ ctx: NSManagedObjectContext, stage: Stage) throws {
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            throw MigrationError.saveFailed(stage: stage, error: error)
        }
    }

    private func advance(to stage: Stage, message: String? = nil) {
        UserDefaults.standard.set(stage.rawValue, forKey: migrationStageKey)
        DataOperationLogger.shared.logInfo("Migration stage: \(stage.rawValue)")
        if let message {
            liveStageMessage = message
        }
    }

    /// Fetches existing UUIDs of an entity already present in the destination
    /// store. Used so a re-run after partial failure doesn't import duplicates.
    private func existingIDs(entity: BitBinderEntity, in ctx: NSManagedObjectContext) throws -> Set<UUID> {
        let request = NSFetchRequest<NSDictionary>(entityName: entity.rawValue)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        let rows = try ctx.fetch(request)
        var set = Set<UUID>()
        for row in rows {
            if let id = row["id"] as? UUID {
                set.insert(id)
            }
        }
        return set
    }

    /// Increments live counts after a successful copy.
    private func bumpLive(entity: String) {
        liveCounts[entity, default: 0] += 1
    }

    /// Increments live skip count (existing row, not copied).
    private func bumpSkipped(entity: String) {
        liveSkipped[entity, default: 0] += 1
    }

    private func encodeStringArray(_ array: [String]) -> Data? {
        try? JSONEncoder().encode(array)
    }

    private func encodeCategoryScores(_ scores: [String: Double]) -> String {
        scores
            .map { "\($0.key.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ":", with: "")):\($0.value)" }
            .joined(separator: "|")
    }
}
