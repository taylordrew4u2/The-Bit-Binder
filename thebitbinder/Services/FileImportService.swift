import Foundation
import UIKit
import SwiftData

final class FileImportService {
    static let shared = FileImportService()
    
    private let pipelineCoordinator = ImportPipelineCoordinator.shared
    private let dataLogger = DataOperationLogger.shared
    
    private init() {}
    
    /// Modern import method that returns the full pipeline result. Optional
    /// `hints` from the user tell the pipeline how the document is structured.
    /// Defaults to `.unspecified` so existing callers keep working unchanged.
    func importWithPipeline(from url: URL, hints: ExtractionHints = .unspecified) async throws -> ImportPipelineResult {
        dataLogger.logInfo("Starting pipeline import for \(url.lastPathComponent)")

        do {
            let result = try await pipelineCoordinator.processFile(url: url, hints: hints)
            
            dataLogger.logInfo("Pipeline import completed successfully")
            dataLogger.logInfo("Auto-saved: \(result.autoSavedJokes.count)")
            dataLogger.logInfo("Review queue: \(result.reviewQueueJokes.count)")
            dataLogger.logInfo("Rejected: \(result.rejectedBlocks.count)")
            
            return result
            
        } catch {
            dataLogger.logError(error, operation: "PIPELINE_IMPORT", context: url.lastPathComponent)
            throw error
        }
    }
    
    /// Saves approved jokes to the data store
    func saveApprovedJokes(_ jokes: [ImportedJoke], to modelContext: ModelContext) throws {
        for importedJoke in jokes {
            let joke = Joke(content: importedJoke.body, title: importedJoke.title ?? "")
            joke.dateCreated  = importedJoke.sourceMetadata.importTimestamp
            joke.dateModified = importedJoke.sourceMetadata.importTimestamp
            joke.tags         = importedJoke.tags

            // Populate import-tracking fields so history / CloudKit schema stay consistent
            joke.importSource     = importedJoke.sourceMetadata.fileName
            joke.importConfidence = importedJoke.confidence.rawValue
            joke.importTimestamp  = importedJoke.sourceMetadata.importTimestamp

            modelContext.insert(joke)
            dataLogger.logDataCreation(joke, context: modelContext)
        }

        try modelContext.save()
        dataLogger.logBulkOperation("IMPORT_SAVE", entityType: "Joke", count: jokes.count, context: modelContext)
    }
}
