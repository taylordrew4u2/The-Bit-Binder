//
//  JokesImportState.swift
//  thebitbinder
//
//  Transient state for the joke import flow, extracted from JokesView.
//

import Foundation

/// Groups the import pipeline's transient UI state into a single value type.
///
/// `JokesView` owns one `@State private var importState = JokesImportState()`
/// instead of ~17 individual `@State` properties. Bindings to individual
/// fields are projected with `$importState.field`, and the two view modifiers
/// (`JokesSheetsModifier`, `JokesAlertsModifier`) continue to receive the same
/// per-field bindings — only the call site changed.
struct JokesImportState {
    // Image / scan processing
    var isProcessingImages = false
    var processingCurrent: Int = 0
    var processingTotal: Int = 0
    var importSummary: (added: Int, skipped: Int) = (0, 0)
    var showingImportSummary = false

    // Review queue
    var reviewCandidates: [JokeImportCandidate] = []
    var showingReviewSheet = false
    var possibleDuplicates: [String] = []
    var unresolvedImportFragments: [UnresolvedImportFragment] = []

    // Live import progress
    var importStatusMessage = ""
    var importedJokeNames: [String] = []
    var importFileCount = 0
    var importFileIndex = 0

    // Smart import review
    var smartImportResult: ImportPipelineResult?
    var importError: Error?
    var showingImportError = false

    // Pre-flight extraction-hints sheet. Set when the user picks files via the
    // document picker; presenting the sheet gathers hints before the pipeline runs.
    var pendingDocumentImport: PendingDocumentImport?
}
