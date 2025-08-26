//
//  AffirmationContentFilter.swift
//  SelfLie
//
//  Content safety and validation for affirmation generation
//

import Foundation

class AffirmationContentFilter {
    
    // MARK: - Negative words and phrases to avoid
    
    private let negativeWords = [
        "not", "never", "can't", "won't", "don't", "no", "none", "nothing",
        "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't",
        "shouldn't", "couldn't", "wouldn't", "mustn't", "needn't", "shan't"
    ]
    
    private let harmfulPhrases = [
        "worthless", "failure", "stupid", "hate", "ugly", "fat", "loser",
        "useless", "hopeless", "pathetic", "awful", "terrible", "horrible",
        "disgusting", "shameful", "embarrassing", "foolish", "ridiculous"
    ]
    
    private let discouragingWords = [
        "impossible", "hopeless", "pointless", "useless", "waste",
        "fail", "failed", "failing", "lose", "losing", "lost"
    ]
    
    // MARK: - Positive patterns to encourage
    
    private let positiveStarters = [
        "I am", "I have", "I choose", "I create", "I build", "I grow",
        "I embrace", "I welcome", "I attract", "I deserve", "I achieve",
        "I become", "I develop", "I strengthen", "I nurture", "I honor"
    ]
    
    // MARK: - Main validation methods
    
    /// Check if text uses positive language
    func isPositive(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Check for negative words
        for word in negativeWords {
            if containsWord(lowercased, word) {
                return false
            }
        }
        
        // Check for harmful phrases
        for phrase in harmfulPhrases {
            if lowercased.contains(phrase) {
                return false
            }
        }
        
        // Check for discouraging words
        for word in discouragingWords {
            if containsWord(lowercased, word) {
                return false
            }
        }
        
        return true
    }
    
    /// Comprehensive validation of an FMAffirmation
    @available(iOS 26.0, *)
    func validateAffirmation(_ affirmation: FMAffirmation) -> ValidationResult {
        var issues: [ValidationIssue] = []
        
        // Validate main statement
        if !isPositive(affirmation.statement) {
            issues.append(.negativeLanguage(in: "statement"))
        }
        
        if !hasPositiveStart(affirmation.statement) {
            issues.append(.weakStart)
        }
        
        // Validate alternatives
        for (index, alternative) in affirmation.alternatives.enumerated() {
            if !isPositive(alternative) {
                issues.append(.negativeLanguage(in: "alternative \(index + 1)"))
            }
        }
        
        // Check length constraints
        if affirmation.statement.split(separator: " ").count > 25 {
            issues.append(.tooLong)
        }
        
        if affirmation.statement.split(separator: " ").count < 3 {
            issues.append(.tooShort)
        }
        
        // Check for psychological soundness
        if !isPsychologicallySound(affirmation.statement) {
            issues.append(.psychologicallyUnsound)
        }
        
        return ValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            confidence: calculateConfidence(issues: issues)
        )
    }
    
    /// Quick validation for partial content during streaming
    func validatePartial(_ text: String) -> Bool {
        return isPositive(text)
    }
    
    // MARK: - Helper methods
    
    private func containsWord(_ text: String, _ word: String) -> Bool {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let words = text.components(separatedBy: separators)
        return words.contains { $0.lowercased() == word.lowercased() }
    }
    
    private func hasPositiveStart(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return positiveStarters.contains { trimmed.lowercased().hasPrefix($0.lowercased()) }
    }
    
    private func isPsychologicallySound(_ text: String) -> Bool {
        // Check for unrealistic claims
        let unrealisticPatterns = [
            "always", "never", "every", "all", "none", "perfect", "completely"
        ]
        
        let lowercased = text.lowercased()
        let hasUnrealisticClaims = unrealisticPatterns.contains { pattern in
            lowercased.contains(pattern)
        }
        
        return !hasUnrealisticClaims
    }
    
    private func calculateConfidence(issues: [ValidationIssue]) -> Double {
        var confidence = 1.0
        
        for issue in issues {
            switch issue {
            case .negativeLanguage:
                confidence -= 0.4
            case .weakStart:
                confidence -= 0.2
            case .tooLong, .tooShort:
                confidence -= 0.1
            case .psychologicallyUnsound:
                confidence -= 0.3
            }
        }
        
        return max(0.0, confidence)
    }
    
    // MARK: - Content improvement suggestions
    
    /// Suggest improvements for problematic content
    func suggestImprovements(for text: String) -> [String] {
        var suggestions: [String] = []
        
        let lowercased = text.lowercased()
        
        // Check for negative words and suggest alternatives
        for negativeWord in negativeWords {
            if containsWord(lowercased, negativeWord) {
                switch negativeWord {
                case "not", "don't", "won't", "can't":
                    suggestions.append("Try rephrasing to focus on what you WANT instead of what you don't want")
                case "never":
                    suggestions.append("Consider using 'I choose' or 'I am' instead of 'never'")
                default:
                    suggestions.append("Replace negative word '\(negativeWord)' with positive language")
                }
            }
        }
        
        // Check for positive starters
        if !hasPositiveStart(text) {
            suggestions.append("Start with empowering words like 'I am', 'I have', or 'I choose'")
        }
        
        return Array(Set(suggestions)) // Remove duplicates
    }
}

// MARK: - Supporting types

struct ValidationResult {
    let isValid: Bool
    let issues: [ValidationIssue]
    let confidence: Double
    
    var isGoodQuality: Bool {
        return isValid && confidence >= 0.8
    }
}

enum ValidationIssue {
    case negativeLanguage(in: String)
    case weakStart
    case tooLong
    case tooShort
    case psychologicallyUnsound
    
    var description: String {
        switch self {
        case .negativeLanguage(let location):
            return "Contains negative language in \(location)"
        case .weakStart:
            return "Does not start with empowering language"
        case .tooLong:
            return "Affirmation is too long (over 25 words)"
        case .tooShort:
            return "Affirmation is too short (under 3 words)"
        case .psychologicallyUnsound:
            return "Contains unrealistic or psychologically unsound claims"
        }
    }
}
