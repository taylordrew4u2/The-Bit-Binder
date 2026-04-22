//
//  TextRecognitionService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation

// MARK: - Joke Import Candidate for User Validation
struct JokeImportCandidate: Identifiable {
    let id = UUID()
    var content: String
    var suggestedTitle: String
    var isComplete: Bool
    var confidence: Double
    var issues: [String]
    var suggestedFix: String?
    var userApproved: Bool = false
    var userEdited: Bool = false
    
    var needsReview: Bool {
        return !isComplete || confidence < 0.8 || !issues.isEmpty
    }
    
    var statusDescription: String {
        if isComplete && confidence >= 0.8 {
            return " Complete joke detected"
        } else if confidence >= 0.6 {
            return " Possibly incomplete - please verify"
        } else {
            return " May be missing parts - please review"
        }
    }
}
