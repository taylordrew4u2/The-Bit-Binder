import Foundation
import SwiftData

@Model
final class ImportBatch: Identifiable {
    var id: UUID = UUID()
    var entityName: String = "ImportBatch"  // Required to match CD_entityName in CloudKit schema
    var sourceFileName: String = ""
    var importTimestamp: Date = Date()
    var totalSegments: Int = 0
    var totalImportedRecords: Int = 0
    var unresolvedFragmentCount: Int = 0
    var highConfidenceBoundaries: Int = 0
    var mediumConfidenceBoundaries: Int = 0
    var lowConfidenceBoundaries: Int = 0
    
    // New pipeline fields
    var extractionMethod: String = ""  // PDFKit Text, Vision OCR, Document Text, Image OCR
    var pipelineVersion: String = "2.0"
    var processingTimeSeconds: Double = 0.0
    var autoSavedCount: Int = 0
    var reviewQueueCount: Int = 0
    var rejectedCount: Int = 0
    
    @Relationship(deleteRule: .cascade, inverse: \ImportedJokeMetadata.batch)
    var importedRecords: [ImportedJokeMetadata]?
    
    @Relationship(deleteRule: .cascade, inverse: \UnresolvedImportFragment.batch)
    var unresolvedFragments: [UnresolvedImportFragment]?
    
    init(
        sourceFileName: String,
        importTimestamp: Date = Date(),
        totalSegments: Int,
        totalImportedRecords: Int,
        unresolvedFragmentCount: Int,
        highConfidenceBoundaries: Int,
        mediumConfidenceBoundaries: Int,
        lowConfidenceBoundaries: Int,
        extractionMethod: String = "",
        pipelineVersion: String = "2.0",
        processingTimeSeconds: Double = 0.0,
        autoSavedCount: Int = 0,
        reviewQueueCount: Int = 0,
        rejectedCount: Int = 0
    ) {
        self.id = UUID()
        self.sourceFileName = sourceFileName
        self.importTimestamp = importTimestamp
        self.totalSegments = totalSegments
        self.totalImportedRecords = totalImportedRecords
        self.unresolvedFragmentCount = unresolvedFragmentCount
        self.highConfidenceBoundaries = highConfidenceBoundaries
        self.mediumConfidenceBoundaries = mediumConfidenceBoundaries
        self.lowConfidenceBoundaries = lowConfidenceBoundaries
        self.extractionMethod = extractionMethod
        self.pipelineVersion = pipelineVersion
        self.processingTimeSeconds = processingTimeSeconds
        self.autoSavedCount = autoSavedCount
        self.reviewQueueCount = reviewQueueCount
        self.rejectedCount = rejectedCount
    }
}

@Model
final class ImportedJokeMetadata: Identifiable {
    var id: UUID = UUID()
    var jokeID: UUID?
    var title: String = ""
    var rawSourceText: String = ""
    var notes: String = ""
    var confidence: String = "low"
    var sourceOrder: Int = 0
    var sourcePage: Int?
    var tagsString: String = ""
    var parsingFlagsJSON: String = "{}"
    var sourceFilename: String = ""
    var importTimestamp: Date = Date()
    
    // New pipeline fields
    var extractionMethod: String = ""
    var confidenceScore: Double = 0.0
    var extractionQuality: Double = 0.0
    var structuralCleanliness: Double = 0.0
    var titleDetectionScore: Double = 0.0
    var boundaryClarity: Double = 0.0
    var ocrConfidence: Double = 0.0
    var validationResult: String = ""  // singleJoke, multipleJokes, requiresReview, notAJoke
    var needsReview: Bool = false
    
    // Relationship to ImportBatch - CloudKit will handle this as a REFERENCE
    var batch: ImportBatch?
    
    var tags: [String] {
        get { tagsString.isEmpty ? [] : tagsString.split(separator: "|").map(String.init) }
        set { tagsString = newValue.joined(separator: "|") }
    }
    
    init(
        jokeID: UUID?,
        title: String,
        rawSourceText: String,
        notes: String,
        confidence: String,
        sourceOrder: Int,
        sourcePage: Int?,
        tags: [String],
        parsingFlagsJSON: String,
        sourceFilename: String,
        importTimestamp: Date = Date(),
        batch: ImportBatch? = nil,
        extractionMethod: String = "",
        confidenceScore: Double = 0.0,
        extractionQuality: Double = 0.0,
        structuralCleanliness: Double = 0.0,
        titleDetectionScore: Double = 0.0,
        boundaryClarity: Double = 0.0,
        ocrConfidence: Double = 0.0,
        validationResult: String = "",
        needsReview: Bool = false
    ) {
        self.id = UUID()
        self.jokeID = jokeID
        self.title = title
        self.rawSourceText = rawSourceText
        self.notes = notes
        self.confidence = confidence
        self.sourceOrder = sourceOrder
        self.sourcePage = sourcePage
        self.tagsString = tags.joined(separator: "|")
        self.parsingFlagsJSON = parsingFlagsJSON
        self.sourceFilename = sourceFilename
        self.importTimestamp = importTimestamp
        self.batch = batch
        self.extractionMethod = extractionMethod
        self.confidenceScore = confidenceScore
        self.extractionQuality = extractionQuality
        self.structuralCleanliness = structuralCleanliness
        self.titleDetectionScore = titleDetectionScore
        self.boundaryClarity = boundaryClarity
        self.ocrConfidence = ocrConfidence
        self.validationResult = validationResult
        self.needsReview = needsReview
    }
}

@Model
final class UnresolvedImportFragment: Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var normalizedText: String = ""
    var kind: String = "unknown"
    var confidence: String = "low"
    var sourceOrder: Int = 0
    var sourcePage: Int?
    var sourceFilename: String = ""
    var titleCandidate: String?
    var tagsString: String = ""
    var parsingFlagsJSON: String = "{}"
    var createdAt: Date = Date()
    var isResolved: Bool = false
    
    // New pipeline fields
    var validationResult: String = ""  // singleJoke, multipleJokes, requiresReview, notAJoke
    var issuesJSON: String = "[]"  // JSON array of validation issues
    var confidenceScore: Double = 0.0
    
    // Relationship to ImportBatch - CloudKit will handle this as a REFERENCE
    var batch: ImportBatch?
    
    var tags: [String] {
        get { tagsString.isEmpty ? [] : tagsString.split(separator: "|").map(String.init) }
        set { tagsString = newValue.joined(separator: "|") }
    }
    
    init(
        text: String,
        normalizedText: String,
        kind: String,
        confidence: String,
        sourceOrder: Int,
        sourcePage: Int?,
        sourceFilename: String,
        titleCandidate: String?,
        tags: [String],
        parsingFlagsJSON: String,
        createdAt: Date = Date(),
        isResolved: Bool = false,
        batch: ImportBatch? = nil,
        validationResult: String = "",
        issuesJSON: String = "[]",
        confidenceScore: Double = 0.0
    ) {
        self.id = UUID()
        self.text = text
        self.normalizedText = normalizedText
        self.kind = kind
        self.confidence = confidence
        self.sourceOrder = sourceOrder
        self.sourcePage = sourcePage
        self.sourceFilename = sourceFilename
        self.titleCandidate = titleCandidate
        self.tagsString = tags.joined(separator: "|")
        self.parsingFlagsJSON = parsingFlagsJSON
        self.createdAt = createdAt
        self.isResolved = isResolved
        self.batch = batch
        self.validationResult = validationResult
        self.issuesJSON = issuesJSON
        self.confidenceScore = confidenceScore
    }
}
