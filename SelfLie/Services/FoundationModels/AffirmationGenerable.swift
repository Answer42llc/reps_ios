//
//  AffirmationGenerable.swift
//  SelfLie
//
//  Generable data structures for Foundation Models affirmation generation
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels

// All FoundationModels and macro code is guarded for iOS 26+
// This prevents availability errors with generated code

@available(iOS 26.0, *)
@Generable
struct FMAffirmation: Equatable {
    @Guide(description: "A powerful, positive first-person affirmation statement (10-20 words), always keep the reason")
    let statement: String
    
    @Guide(description: "Two alternative phrasings with the same meaning (provide exactly 2)")
    let alternatives: [String]
}


@available(iOS 26.0, *)
extension FMAffirmation {
    /// Validate that all parts of the affirmation are present and valid
    func validate() throws {
        guard !statement.isEmpty else {
            throw AffirmationValidationError.emptyStatement
        }
        
        guard alternatives.count == 2 && alternatives.allSatisfy({ !$0.isEmpty }) else {
            throw AffirmationValidationError.invalidAlternatives
        }
    }
}

#else
// Fallback implementation for pre-iOS 26 or without FoundationModels
struct FMAffirmation: Equatable {
    let statement: String
    let alternatives: [String]
    
    init(statement: String, alternatives: [String]) {
        self.statement = statement
        self.alternatives = alternatives
    }
}
#endif

// Error enum used by both implementations

enum AffirmationValidationError: LocalizedError {
    case emptyStatement
    case invalidAlternatives
    case containsNegativeLanguage
    
    var errorDescription: String? {
        switch self {
        case .emptyStatement:
            return "Affirmation statement is empty"
        case .invalidAlternatives:
            return "Invalid alternative phrasings"
        case .containsNegativeLanguage:
            return "Affirmation contains negative language"
        }
    }
}
