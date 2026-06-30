//
//  BitBinderModel.swift
//  thebitbinder
//
//  Programmatic NSManagedObjectModel for the CloudKit-backed persistence stack.
//
//  Built in code (instead of a .xcdatamodeld bundle) so the schema lives in one
//  reviewable Swift file. The PersistenceController feeds this model into an
//  NSPersistentCloudKitContainer that hosts both a private store and a shared
//  store, enabling CKShare-based cross-account sharing.
//
//  Conventions
//  - Every attribute is optional or has a default. Required by CloudKit.
//  - Every relationship is optional. To-many inverses match by name.
//  - Delete rules: Cascade on Workspace -> children, Cascade on container
//    -> dependent children (ImportBatch -> records, RoastTarget -> jokes).
//    Nullify everywhere else. CloudKit does not support Deny.
//

import CoreData

enum BitBinderEntity: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case workspace = "Workspace"
    case joke = "Joke"
    case jokeFolder = "JokeFolder"
    case setList = "SetList"
    case notebookFolder = "NotebookFolder"
    case notebookPhotoRecord = "NotebookPhotoRecord"
    case recording = "Recording"
    case roastTarget = "RoastTarget"
    case roastJoke = "RoastJoke"
    case brainstormIdea = "BrainstormIdea"
    case importBatch = "ImportBatch"
    case importedJokeMetadata = "ImportedJokeMetadata"
    case unresolvedImportFragment = "UnresolvedImportFragment"
    case chatMessage = "ChatMessage"

    var managedObjectClassName: String {
        // The Core Data bridge uses generic NSManagedObject instances. Keep
        // the model class name aligned with that so stores can load even
        // though there are no generated WorkspaceMO/JokeMO subclasses.
        NSStringFromClass(NSManagedObject.self)
    }
}

enum BitBinderModel {

    /// The single shared NSManagedObjectModel. Built once and cached.
    static let shared: NSManagedObjectModel = build()

    private static func build() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entities = makeEntities()
        wireRelationships(entities)
        model.entities = entities.map(\.entity)
        return model
    }

    // MARK: - Entity table

    private struct EntityBuild {
        let key: BitBinderEntity
        let entity: NSEntityDescription
        let attributes: [NSAttributeDescription]
        // [propertyName: (destinationEntityKey, toMany, deleteRule, inverseName, maxCount)]
        let relationships: [RelationshipSpec]
    }

    private struct RelationshipSpec {
        let name: String
        let destination: BitBinderEntity
        let isToMany: Bool
        let deleteRule: NSDeleteRule
        let inverseName: String
        let maxCount: Int
    }

    private static func makeEntities() -> [EntityBuild] {
        BitBinderEntity.allCases.map { key in
            let entity = NSEntityDescription()
            entity.name = key.rawValue
            entity.managedObjectClassName = key.managedObjectClassName
            let attrs = attributes(for: key)
            // Final `properties` (attributes + relationships) is set in
            // `wireRelationships` once the relationship descriptions exist.
            entity.properties = attrs
            return EntityBuild(
                key: key,
                entity: entity,
                attributes: attrs,
                relationships: relationshipSpecs(for: key)
            )
        }
    }

    private static func wireRelationships(_ builds: [EntityBuild]) {
        let byKey = Dictionary(uniqueKeysWithValues: builds.map { ($0.key, $0.entity) })

        // First pass: create relationship descriptions on each entity (without inverse).
        var relsByEntity: [BitBinderEntity: [String: NSRelationshipDescription]] = [:]
        for build in builds {
            var rels: [String: NSRelationshipDescription] = [:]
            for spec in build.relationships {
                let rel = NSRelationshipDescription()
                rel.name = spec.name
                rel.destinationEntity = byKey[spec.destination]
                rel.isOptional = true
                rel.deleteRule = spec.deleteRule
                rel.maxCount = spec.isToMany ? 0 : spec.maxCount
                rel.minCount = 0
                rels[spec.name] = rel
            }
            relsByEntity[build.key] = rels
            build.entity.properties = build.attributes + Array(rels.values)
        }

        // Second pass: link inverses.
        for build in builds {
            guard let rels = relsByEntity[build.key] else { continue }
            for spec in build.relationships {
                guard let rel = rels[spec.name],
                      let counterpart = relsByEntity[spec.destination]?[spec.inverseName] else {
                    continue
                }
                rel.inverseRelationship = counterpart
            }
        }
    }

    // MARK: - Attributes per entity

    private static func attributes(for key: BitBinderEntity) -> [NSAttributeDescription] {
        switch key {
        case .workspace:
            return [
                attr("id", .UUIDAttributeType),
                attr("dateCreated", .dateAttributeType),
                attr("ownerName", .stringAttributeType),
            ]

        case .joke:
            return [
                attr("id", .UUIDAttributeType),
                attr("content", .stringAttributeType, defaultValue: ""),
                attr("title", .stringAttributeType, defaultValue: ""),
                attr("dateCreated", .dateAttributeType),
                attr("dateModified", .dateAttributeType),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
                attr("categorizationResultsData", .binaryDataAttributeType),
                attr("primaryCategory", .stringAttributeType),
                attr("allCategoriesString", .stringAttributeType, defaultValue: ""),
                attr("categoryScoresString", .stringAttributeType, defaultValue: ""),
                attr("styleTagsString", .stringAttributeType, defaultValue: ""),
                attr("craftNotesString", .stringAttributeType, defaultValue: ""),
                attr("comedicTone", .stringAttributeType),
                attr("structureScore", .doubleAttributeType, defaultValue: 0.0),
                attr("category", .stringAttributeType),
                attr("tagsString", .stringAttributeType, defaultValue: ""),
                attr("difficulty", .stringAttributeType),
                attr("humorRating", .integer16AttributeType, defaultValue: 0),
                attr("isHit", .booleanAttributeType, defaultValue: false),
                attr("isOpenMic", .booleanAttributeType, defaultValue: false),
                attr("wordCount", .integer32AttributeType, defaultValue: 0),
                attr("notes", .stringAttributeType, defaultValue: ""),
                attr("importSource", .stringAttributeType),
                attr("importConfidence", .stringAttributeType),
                attr("importTimestamp", .dateAttributeType),
            ]

        case .jokeFolder:
            return [
                attr("id", .UUIDAttributeType),
                attr("name", .stringAttributeType, defaultValue: ""),
                attr("dateCreated", .dateAttributeType),
                attr("isRecentlyAdded", .booleanAttributeType, defaultValue: false),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
            ]

        case .setList:
            return [
                attr("id", .UUIDAttributeType),
                attr("name", .stringAttributeType, defaultValue: ""),
                attr("dateCreated", .dateAttributeType),
                attr("dateModified", .dateAttributeType),
                attr("notes", .stringAttributeType, defaultValue: ""),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
                attr("isFinalized", .booleanAttributeType, defaultValue: false),
                attr("finalizedDate", .dateAttributeType),
                attr("estimatedMinutes", .integer32AttributeType, defaultValue: 0),
                attr("venueName", .stringAttributeType, defaultValue: ""),
                attr("performanceDate", .dateAttributeType),
                attr("jokeIDsString", .stringAttributeType, defaultValue: ""),
                attr("roastJokeIDsString", .stringAttributeType, defaultValue: ""),
            ]

        case .notebookFolder:
            return [
                attr("id", .UUIDAttributeType),
                attr("name", .stringAttributeType, defaultValue: ""),
                attr("dateCreated", .dateAttributeType),
                attr("sortOrder", .integer64AttributeType, defaultValue: 0),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
            ]

        case .notebookPhotoRecord:
            return [
                attr("id", .UUIDAttributeType),
                attr("notes", .stringAttributeType, defaultValue: ""),
                attr("imageData", .binaryDataAttributeType, externalStorage: true),
                attr("dateAdded", .dateAttributeType),
                attr("sortOrder", .integer64AttributeType, defaultValue: 0),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
            ]

        case .recording:
            return [
                attr("id", .UUIDAttributeType),
                attr("title", .stringAttributeType, defaultValue: ""),
                attr("dateCreated", .dateAttributeType),
                attr("duration", .doubleAttributeType, defaultValue: 0.0),
                attr("fileURL", .stringAttributeType, defaultValue: ""),
                attr("transcription", .stringAttributeType),
                attr("isProcessed", .booleanAttributeType, defaultValue: false),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
            ]

        case .roastTarget:
            return [
                attr("id", .UUIDAttributeType),
                attr("name", .stringAttributeType, defaultValue: ""),
                attr("notes", .stringAttributeType, defaultValue: ""),
                attr("traitsData", .binaryDataAttributeType),
                attr("photoData", .binaryDataAttributeType, externalStorage: true),
                attr("dateCreated", .dateAttributeType),
                attr("dateModified", .dateAttributeType),
                attr("openingRoastCount", .integer16AttributeType, defaultValue: 3),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
            ]

        case .roastJoke:
            return [
                attr("id", .UUIDAttributeType),
                attr("content", .stringAttributeType, defaultValue: ""),
                attr("title", .stringAttributeType, defaultValue: ""),
                attr("dateCreated", .dateAttributeType),
                attr("dateModified", .dateAttributeType),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
                attr("setup", .stringAttributeType, defaultValue: ""),
                attr("punchline", .stringAttributeType, defaultValue: ""),
                attr("performanceNotes", .stringAttributeType, defaultValue: ""),
                attr("relatabilityScore", .integer16AttributeType, defaultValue: 0),
                attr("isTested", .booleanAttributeType, defaultValue: false),
                attr("lastPerformedDate", .dateAttributeType),
                attr("performanceCount", .integer32AttributeType, defaultValue: 0),
                attr("displayOrder", .integer32AttributeType, defaultValue: 0),
                attr("isKiller", .booleanAttributeType, defaultValue: false),
                attr("isOpeningRoast", .booleanAttributeType, defaultValue: false),
                attr("parentOpeningRoastID", .UUIDAttributeType),
                attr("tagsString", .stringAttributeType, defaultValue: ""),
            ]

        case .brainstormIdea:
            return [
                attr("id", .UUIDAttributeType),
                attr("content", .stringAttributeType, defaultValue: ""),
                attr("dateCreated", .dateAttributeType),
                attr("colorHex", .stringAttributeType, defaultValue: "F5E6D3"),
                attr("boardPositionX", .doubleAttributeType, defaultValue: -1.0),
                attr("boardPositionY", .doubleAttributeType, defaultValue: -1.0),
                attr("isVoiceNote", .booleanAttributeType, defaultValue: false),
                attr("notes", .stringAttributeType, defaultValue: ""),
                attr("isTrashed", .booleanAttributeType, defaultValue: false),
                attr("deletedDate", .dateAttributeType),
            ]

        case .importBatch:
            return [
                attr("id", .UUIDAttributeType),
                attr("sourceFileName", .stringAttributeType, defaultValue: ""),
                attr("importTimestamp", .dateAttributeType),
                attr("totalSegments", .integer32AttributeType, defaultValue: 0),
                attr("totalImportedRecords", .integer32AttributeType, defaultValue: 0),
                attr("unresolvedFragmentCount", .integer32AttributeType, defaultValue: 0),
                attr("highConfidenceBoundaries", .integer32AttributeType, defaultValue: 0),
                attr("mediumConfidenceBoundaries", .integer32AttributeType, defaultValue: 0),
                attr("lowConfidenceBoundaries", .integer32AttributeType, defaultValue: 0),
                attr("extractionMethod", .stringAttributeType, defaultValue: ""),
                attr("pipelineVersion", .stringAttributeType, defaultValue: "2.0"),
                attr("processingTimeSeconds", .doubleAttributeType, defaultValue: 0.0),
                attr("autoSavedCount", .integer32AttributeType, defaultValue: 0),
                attr("reviewQueueCount", .integer32AttributeType, defaultValue: 0),
                attr("rejectedCount", .integer32AttributeType, defaultValue: 0),
            ]

        case .importedJokeMetadata:
            return [
                attr("id", .UUIDAttributeType),
                attr("jokeID", .UUIDAttributeType),
                attr("title", .stringAttributeType, defaultValue: ""),
                attr("rawSourceText", .stringAttributeType, defaultValue: ""),
                attr("notes", .stringAttributeType, defaultValue: ""),
                attr("confidence", .stringAttributeType, defaultValue: "low"),
                attr("sourceOrder", .integer32AttributeType, defaultValue: 0),
                attr("sourcePage", .integer32AttributeType, isOptional: true),
                attr("tagsString", .stringAttributeType, defaultValue: ""),
                attr("parsingFlagsJSON", .stringAttributeType, defaultValue: "{}"),
                attr("sourceFilename", .stringAttributeType, defaultValue: ""),
                attr("importTimestamp", .dateAttributeType),
                attr("extractionMethod", .stringAttributeType, defaultValue: ""),
                attr("confidenceScore", .doubleAttributeType, defaultValue: 0.0),
                attr("extractionQuality", .doubleAttributeType, defaultValue: 0.0),
                attr("structuralCleanliness", .doubleAttributeType, defaultValue: 0.0),
                attr("titleDetectionScore", .doubleAttributeType, defaultValue: 0.0),
                attr("boundaryClarity", .doubleAttributeType, defaultValue: 0.0),
                attr("ocrConfidence", .doubleAttributeType, defaultValue: 0.0),
                attr("validationResult", .stringAttributeType, defaultValue: ""),
                attr("needsReview", .booleanAttributeType, defaultValue: false),
            ]

        case .unresolvedImportFragment:
            return [
                attr("id", .UUIDAttributeType),
                attr("text", .stringAttributeType, defaultValue: ""),
                attr("normalizedText", .stringAttributeType, defaultValue: ""),
                attr("kind", .stringAttributeType, defaultValue: "unknown"),
                attr("confidence", .stringAttributeType, defaultValue: "low"),
                attr("sourceOrder", .integer32AttributeType, defaultValue: 0),
                attr("sourcePage", .integer32AttributeType, isOptional: true),
                attr("sourceFilename", .stringAttributeType, defaultValue: ""),
                attr("titleCandidate", .stringAttributeType),
                attr("tagsString", .stringAttributeType, defaultValue: ""),
                attr("parsingFlagsJSON", .stringAttributeType, defaultValue: "{}"),
                attr("createdAt", .dateAttributeType),
                attr("isResolved", .booleanAttributeType, defaultValue: false),
                attr("validationResult", .stringAttributeType, defaultValue: ""),
                attr("issuesJSON", .stringAttributeType, defaultValue: "[]"),
                attr("confidenceScore", .doubleAttributeType, defaultValue: 0.0),
            ]

        case .chatMessage:
            return [
                attr("id", .UUIDAttributeType),
                attr("text", .stringAttributeType, defaultValue: ""),
                attr("isUser", .booleanAttributeType, defaultValue: false),
                attr("timestamp", .dateAttributeType),
                attr("conversationId", .stringAttributeType, defaultValue: ""),
            ]
        }
    }

    // MARK: - Relationships per entity

    private static func relationshipSpecs(for key: BitBinderEntity) -> [RelationshipSpec] {
        switch key {
        case .workspace:
            // Each child relationship cascades on workspace deletion.
            // The inverse on the child is .nullify (so deleting a single child
            // never deletes the workspace).
            return [
                toMany("brainstormIdeas", .brainstormIdea, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("chatMessages", .chatMessage, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("importBatches", .importBatch, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("jokeFolders", .jokeFolder, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("jokes", .joke, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("notebookFolders", .notebookFolder, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("notebookPhotos", .notebookPhotoRecord, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("recordings", .recording, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("roastJokes", .roastJoke, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("roastTargets", .roastTarget, inverse: "workspace", rule: .cascadeDeleteRule),
                toMany("setLists", .setList, inverse: "workspace", rule: .cascadeDeleteRule),
            ]

        case .joke:
            return [
                toMany("folders", .jokeFolder, inverse: "jokes", rule: .nullifyDeleteRule),
                toOne("workspace", .workspace, inverse: "jokes", rule: .nullifyDeleteRule),
            ]

        case .jokeFolder:
            return [
                toMany("jokes", .joke, inverse: "folders", rule: .nullifyDeleteRule),
                toOne("workspace", .workspace, inverse: "jokeFolders", rule: .nullifyDeleteRule),
            ]

        case .setList:
            return [
                toOne("workspace", .workspace, inverse: "setLists", rule: .nullifyDeleteRule),
            ]

        case .notebookFolder:
            return [
                toMany("photos", .notebookPhotoRecord, inverse: "folder", rule: .nullifyDeleteRule),
                toOne("workspace", .workspace, inverse: "notebookFolders", rule: .nullifyDeleteRule),
            ]

        case .notebookPhotoRecord:
            return [
                toOne("folder", .notebookFolder, inverse: "photos", rule: .nullifyDeleteRule),
                toOne("workspace", .workspace, inverse: "notebookPhotos", rule: .nullifyDeleteRule),
            ]

        case .recording:
            return [
                toOne("workspace", .workspace, inverse: "recordings", rule: .nullifyDeleteRule),
            ]

        case .roastTarget:
            return [
                toMany("jokes", .roastJoke, inverse: "target", rule: .cascadeDeleteRule),
                toOne("workspace", .workspace, inverse: "roastTargets", rule: .nullifyDeleteRule),
            ]

        case .roastJoke:
            return [
                toOne("target", .roastTarget, inverse: "jokes", rule: .nullifyDeleteRule),
                toOne("workspace", .workspace, inverse: "roastJokes", rule: .nullifyDeleteRule),
            ]

        case .brainstormIdea:
            return [
                toOne("workspace", .workspace, inverse: "brainstormIdeas", rule: .nullifyDeleteRule),
            ]

        case .importBatch:
            return [
                toMany("importedRecords", .importedJokeMetadata, inverse: "batch", rule: .cascadeDeleteRule),
                toMany("unresolvedFragments", .unresolvedImportFragment, inverse: "batch", rule: .cascadeDeleteRule),
                toOne("workspace", .workspace, inverse: "importBatches", rule: .nullifyDeleteRule),
            ]

        case .importedJokeMetadata:
            return [
                toOne("batch", .importBatch, inverse: "importedRecords", rule: .nullifyDeleteRule),
            ]

        case .unresolvedImportFragment:
            return [
                toOne("batch", .importBatch, inverse: "unresolvedFragments", rule: .nullifyDeleteRule),
            ]

        case .chatMessage:
            return [
                toOne("workspace", .workspace, inverse: "chatMessages", rule: .nullifyDeleteRule),
            ]
        }
    }

    // MARK: - Builders

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        defaultValue: Any? = nil,
        isOptional: Bool = true,
        externalStorage: Bool = false
    ) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = isOptional
        if let defaultValue {
            a.defaultValue = defaultValue
        }
        a.allowsExternalBinaryDataStorage = externalStorage
        // Scalar Bool/Int storage is the Core Data default for Boolean and
        // Integer types; no flag needed at the NSAttributeDescription level.
        return a
    }

    private static func toMany(
        _ name: String,
        _ destination: BitBinderEntity,
        inverse inverseName: String,
        rule: NSDeleteRule
    ) -> RelationshipSpec {
        RelationshipSpec(
            name: name,
            destination: destination,
            isToMany: true,
            deleteRule: rule,
            inverseName: inverseName,
            maxCount: 0
        )
    }

    private static func toOne(
        _ name: String,
        _ destination: BitBinderEntity,
        inverse inverseName: String,
        rule: NSDeleteRule
    ) -> RelationshipSpec {
        RelationshipSpec(
            name: name,
            destination: destination,
            isToMany: false,
            deleteRule: rule,
            inverseName: inverseName,
            maxCount: 1
        )
    }
}
