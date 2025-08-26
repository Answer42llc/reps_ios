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
    @Guide(description: "A powerful, positive first-person affirmation statement (10-20 words)")
    let statement: String
    
    @Guide(description: "Brief explanation of why this affirmation is psychologically effective (15-30 words)")
    let rationale: String
    
    @Guide(description: "One of: morning, evening, workout, meditation, anytime")
    
    let suggestedTime: String
    
    @Guide(description: "Two alternative phrasings with the same meaning (provide exactly 2)")
    let alternatives: [String]
}

@available(iOS 26.0, *)
extension FMAffirmation {
    /// Check if the affirmation uses positive language
    var isPositive: Bool {
        let negativeWords = ["not", "never", "can't", "won't", "don't", "no"]
        let lowercased = statement.lowercased()
        
        return !negativeWords.contains { lowercased.contains($0) }
    }
    
    /// Get the primary affirmation text for use in the app
    var primaryText: String {
        return statement
    }
    
    /// Get all variations of the affirmation (main + alternatives)
    var allVariations: [String] {
        return [statement] + alternatives
    }
    
    /// Format for display in UI
    var displayText: String {
        return statement
    }
    
    /// Format for speech synthesis
    var speechText: String {
        // Remove any special characters that might interfere with speech
        return statement.replacingOccurrences(of: "\"", with: "")
    }
}

@available(iOS 26.0, *)
extension FMAffirmation {
    /// Validate that all parts of the affirmation are present and valid
    func validate() throws {
        guard !statement.isEmpty else {
            throw AffirmationValidationError.emptyStatement
        }
        
        guard !rationale.isEmpty else {
            throw AffirmationValidationError.emptyRationale
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
    let rationale: String
    let suggestedTime: String
    let alternatives: [String]
    
    init(statement: String, rationale: String, suggestedTime: String, alternatives: [String]) {
        self.statement = statement
        self.rationale = rationale
        self.suggestedTime = suggestedTime
        self.alternatives = alternatives
    }
}
#endif

// Error enum used by both implementations

enum AffirmationValidationError: LocalizedError {
    case emptyStatement
    case emptyRationale
    case invalidAlternatives
    case invalidTime
    case containsNegativeLanguage
    
    var errorDescription: String? {
        switch self {
        case .emptyStatement:
            return "Affirmation statement is empty"
        case .emptyRationale:
            return "Affirmation rationale is empty"
        case .invalidAlternatives:
            return "Invalid alternative phrasings"
        case .invalidTime:
            return "Invalid suggested time"
        case .containsNegativeLanguage:
            return "Affirmation contains negative language"
        }
    }
}
