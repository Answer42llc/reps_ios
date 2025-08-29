//
//  FMAffirmation.swift
//  SelfLie
//
//  Created by lw on 8/28/25.
//


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

@available(iOS 26.0, *)
@Generable
struct FMReasonSuggestions: Equatable {
    @Guide(description: "3-4 contextual, compelling reasons why someone would want to achieve this goal (provide exactly 3 or 4)")
    let reasons: [String]
    
    @Guide(description: "The goal being addressed, for context")
    let contextualGoal: String
}

@available(iOS 26.0, *)
extension FMReasonSuggestions {
    /// Validate reason suggestions
    func validate() throws {
        guard !contextualGoal.isEmpty else {
            throw ReasonValidationError.emptyGoal
        }
        
        guard reasons.count >= 3 && reasons.count <= 4 else {
            throw ReasonValidationError.invalidReasonCount
        }
        
        guard reasons.allSatisfy({ !$0.isEmpty }) else {
            throw ReasonValidationError.emptyReasons
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

struct FMReasonSuggestions: Equatable {
    let reasons: [String]
    let contextualGoal: String
    
    init(reasons: [String], contextualGoal: String) {
        self.reasons = reasons
        self.contextualGoal = contextualGoal
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

enum ReasonValidationError: LocalizedError {
    case emptyGoal
    case invalidReasonCount
    case emptyReasons
    
    var errorDescription: String? {
        switch self {
        case .emptyGoal:
            return "Goal context is empty"
        case .invalidReasonCount:
            return "Must provide 3-4 reason suggestions"
        case .emptyReasons:
            return "Reason suggestions cannot be empty"
        }
    }
}
