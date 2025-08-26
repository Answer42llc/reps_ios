//
//  AffirmationService.swift
//  SelfLie
//
//  Unified affirmation generation service that intelligently chooses between
//  Foundation Models (when available) and pattern-based generation (as fallback)
//

import SwiftUI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
class AffirmationService {
    
    // MARK: - Dependencies
    private let patternGenerator = PatternBasedAffirmationGenerator()
    
    // MARK: - Session Management (following Apple's pattern)
    #if canImport(FoundationModels)
    private var foundationModelsSessionStorage: Any?  // Type-erased storage to avoid @Observable macro issues
    
    @available(iOS 26.0, *)
    private var foundationModelsSession: LanguageModelSession? {
        get { foundationModelsSessionStorage as? LanguageModelSession }
        set { foundationModelsSessionStorage = newValue }
    }
    #endif
    private var sessionPrewarmed = false
    
    // MARK: - Generation State
    var isGenerating = false
    var generationError: AffirmationError?
    var generatedText = ""
    var generationProgress: String = "idle"
    
    // MARK: - Configuration
    var useFoundationModelsWhenAvailable = true
    
    // MARK: - Initialization
    
    init() {
        initializeFoundationModelsSession()
    }
    
    private func initializeFoundationModelsSession() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let checker = FMAvailabilityChecker()
            if checker.checkAvailability() {
                let instructions = """
                You are an expert affirmation coach specializing in positive psychology and habit formation.
                
                Your expertise includes:
                - Creating powerful, first-person affirmations
                - Understanding psychological principles of belief change
                - Crafting statements that support behavior modification
                
                IMPORTANT RULES for affirmations:
                1. Always use first-person, present-tense language ("I am", "I have", "I choose")
                2. Focus on positive outcomes, never use negative words (no, not, never, can't, won't, don't)
                3. Be specific and actionable rather than vague
                4. Make statements believable and achievable
                5. Support psychological well-being and healthy habits
                6. Keep statements concise (10-20 words ideal)
                7. Create empowering, motivating language
                
                NEVER create affirmations that:
                - Use negative language or words
                - Make unrealistic promises
                - Could be harmful or dangerous
                - Are overly generic or meaningless
                
                Examples of GOOD affirmations:
                - "I choose healthy foods that nourish my body"
                - "I am becoming stronger through my daily actions"
                - "I have the power to create positive change in my life"
                
                Examples of BAD affirmations:
                - "I never eat junk food" (uses "never")
                - "I am not a smoker" (uses negative language)
                - "I am perfect in every way" (unrealistic)
                """
                
                foundationModelsSession = LanguageModelSession(instructions: instructions)
                print("✅ [AffirmationService] Foundation Models session created")
                if let session = foundationModelsSession {
                    print("📍 [AffirmationService] Session created with ID: \(ObjectIdentifier(session))")
                }
            }
        }
        #endif
    }
    
    // MARK: - Public Interface
    
    /// Check if Foundation Models is available
    var canUseFoundationModels: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Create temporary service to check availability
            let checker = FMAvailabilityChecker()
            return checker.checkAvailability()
        } else {
            return false
        }
        #else
        return false
        #endif
    }
    
    /// Get user-friendly availability status
    var availabilityMessage: String {
        if canUseFoundationModels {
            return "AI generation available"
        } else {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let checker = FMAvailabilityChecker()
                return checker.getUnavailableReason()
            } else {
                return "Foundation Models requires iOS 26 or later"
            }
            #else
            return "Foundation Models not available on this platform"
            #endif
        }
    }
    
    /// Get current generation status message
    var statusMessage: String {
        if isGenerating {
            if canUseFoundationModels && useFoundationModelsWhenAvailable {
                #if canImport(FoundationModels)
                return generationProgress.description
                #else
                return "Generating affirmation..."
                #endif
            } else {
                return "Generating affirmation..."
            }
        }
        
        if let error = generationError {
            return error.userFriendlyMessage
        }
        
        return "Ready to generate"
    }
    
    /// Check if we can retry after error
    var canRetry: Bool {
        guard let error = generationError else { return false }
        return error.isRetryable
    }
    
    /// Generate affirmation with intelligent fallback strategy
    func generateAffirmation(goal: String, reason: String) async throws -> String {
        // Reset state
        resetState()
        isGenerating = true
        
        defer { isGenerating = false }
        
        // Validate input
        guard validateInput(goal: goal, reason: reason) else {
            throw AffirmationError.invalidInput
        }
        
        // Choose generation strategy
        if canUseFoundationModels && useFoundationModelsWhenAvailable {
            return try await generateWithFoundationModels(goal: goal, reason: reason)
        } else {
            return generateWithPattern(goal: goal, reason: reason)
        }
    }
    
    /// Retry generation after error
    func retryGeneration(goal: String, reason: String) async throws -> String {
        guard canRetry else {
            throw generationError ?? AffirmationError.generationFailed("Cannot retry")
        }
        
        return try await generateAffirmation(goal: goal, reason: reason)
    }
    
    /// Preemptively warm up Foundation Models session when user shows intent
    func prewarmSession() {
        guard canUseFoundationModels && useFoundationModelsWhenAvailable else { 
            print("📝 [AffirmationService] Using pattern generation, no prewarm needed")
            return 
        }
        
        guard !sessionPrewarmed else {
            print("✅ [AffirmationService] Session already prewarmed, skipping")
            return
        }
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let session = foundationModelsSession else {
                print("⚠️ [AffirmationService] No Foundation Models session available for prewarm")
                return
            }
            
            print("🔥 [AffirmationService] Prewarming Foundation Models session...")
            print("📍 [AffirmationService] Prewarming session with ID: \(ObjectIdentifier(session))")
            session.prewarm()
            sessionPrewarmed = true
            print("✅ [AffirmationService] Session prewarmed successfully")
        }
        #endif
    }
    
    // MARK: - Private Implementation
    
    private func resetState() {
        isGenerating = false
        generationError = nil
        generatedText = ""
        generationProgress = "idle"
    }
    
    private func validateInput(goal: String, reason: String) -> Bool {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return !trimmedGoal.isEmpty && 
               !trimmedReason.isEmpty && 
               trimmedGoal.count >= 2 && 
               trimmedReason.count >= 2
    }
    
    private func generateWithFoundationModels(goal: String, reason: String) async throws -> String {
        #if canImport(FoundationModels)
        print("🤖 [AffirmationService] Using Foundation Models generation")
        
        guard #available(iOS 26.0, *) else {
            print("⚠️ [AffirmationService] Foundation Models requires iOS 26.0+, using pattern fallback")
            return generateWithPattern(goal: goal, reason: reason)
        }
        
        guard let session = foundationModelsSession else {
            print("⚠️ [AffirmationService] No Foundation Models session available, using pattern fallback")
            return generateWithPattern(goal: goal, reason: reason)
        }
        
        print("📍 [AffirmationService] Using session for generation with ID: \(ObjectIdentifier(session))")
        
        // Construct safe prompt to prevent injection
        let safeGoal = goal.replacingOccurrences(of: "\"", with: "'")
        let safeReason = reason.replacingOccurrences(of: "\"", with: "'")
        
        let prompt = """
        Create a personalized affirmation for someone with this goal and reason:
        
        Goal: \(safeGoal)
        Reason: \(safeReason)
        
        Make the affirmation powerful, personal, and psychologically effective.
        Focus on positive transformation and empowerment.
        """
        
        do {
            generationProgress = "Generating affirmation..."
            
            // Use respond with includeSchemaInPrompt: false for optimal performance
            // This is the key optimization mentioned in Apple's presentation
            let response = try await session.respond(
                to: prompt,
                generating: FMAffirmation.self,
            )
            
            let affirmation = response.content
            
            generationProgress = "Validating affirmation..."
            
            // Validate final result
            try affirmation.validate()
            
            let statement = affirmation.statement
            generatedText = statement
            generationProgress = "Complete"
            
            // Print both the generated content and session ID for debugging
            print("✅ [AffirmationService] Foundation Models generated: '\(statement)'")
            print("📍 [AffirmationService] Generated by session ID: \(ObjectIdentifier(session))")
            return statement
            
        } catch let error as FoundationModels.LanguageModelSession.GenerationError {
            print("❌ [AffirmationService] Foundation Models error: \(error)")
            
            // Handle specific Foundation Models errors
            switch error {
            case .exceededContextWindowSize:
                // For our single-round generation, this shouldn't happen, but fallback
                generationError = AffirmationError.contextOverflow
                return generateWithPattern(goal: goal, reason: reason)
                
            case .guardrailViolation:
                // Content safety issue, use fallback
                generationError = AffirmationError.contentSafetyViolation
                return generateWithPattern(goal: goal, reason: reason)
                
            case .unsupportedLanguageOrLocale:
                generationError = AffirmationError.languageNotSupported
                return generateWithPattern(goal: goal, reason: reason)
                
            default:
                generationError = AffirmationError.generationFailed(error.localizedDescription)
                return generateWithPattern(goal: goal, reason: reason)
            }
            
        } catch let error as AffirmationValidationError {
            print("❌ [AffirmationService] Validation error: \(error)")
            generationError = AffirmationError.contentValidationFailed
            return generateWithPattern(goal: goal, reason: reason)
            
        } catch {
            print("❌ [AffirmationService] Unexpected error: \(error)")
            generationError = AffirmationError.generationFailed(error.localizedDescription)
            return generateWithPattern(goal: goal, reason: reason)
        }
        #else
        // Foundation Models not available at compile time - use pattern fallback
        print("⚠️ [AffirmationService] Foundation Models not available at compile time, using pattern fallback")
        return generateWithPattern(goal: goal, reason: reason)
        #endif
    }
    
    private func generateWithPattern(goal: String, reason: String) -> String {
        print("📝 [AffirmationService] Using pattern-based generation")
        
        let result = patternGenerator.generateAffirmation(goal: goal, reason: reason)
        generatedText = result
        generationProgress = "completed"
        
        print("✅ [AffirmationService] Pattern-based generated: '\(result)'")
        return result
    }
}

// MARK: - Pattern-Based Generator

private class PatternBasedAffirmationGenerator {
    
    func generateAffirmation(goal: String, reason: String) -> String {
        let goalLower = goal.lowercased()
        let reasonLower = reason.lowercased()
        
        // Enhanced pattern-based generation with more sophisticated rules
        if goalLower.contains("quit") || goalLower.contains("stop") {
            let habit = extractHabit(from: goalLower)
            return generateQuitAffirmation(habit: habit, reason: reasonLower)
        } else if goalLower.contains("lose") && goalLower.contains("weight") {
            return generateWeightLossAffirmation(reason: reasonLower)
        } else if goalLower.contains("exercise") || goalLower.contains("workout") || goalLower.contains("gym") {
            return generateExerciseAffirmation(reason: reasonLower)
        } else if goalLower.contains("sleep") || goalLower.contains("rest") {
            return generateSleepAffirmation(reason: reasonLower)
        } else if goalLower.contains("read") || goalLower.contains("study") {
            return generateLearningAffirmation(goal: goalLower, reason: reasonLower)
        } else if goalLower.contains("confident") || goalLower.contains("confidence") {
            return generateConfidenceAffirmation(reason: reasonLower)
        } else {
            // Generic positive affirmation
            return generateGenericAffirmation(goal: goalLower, reason: reasonLower)
        }
    }
    
    private func extractHabit(from goalText: String) -> String {
        let habit = goalText
            .replacingOccurrences(of: "quit ", with: "")
            .replacingOccurrences(of: "stop ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return habit.isEmpty ? "harmful habits" : habit
    }
    
    private func generateQuitAffirmation(habit: String, reason: String) -> String {
        let templates = [
            "I choose to be free from \(habit) because \(reason)",
            "I am breaking free from \(habit) because \(reason)",
            "I have the power to overcome \(habit) because \(reason)",
            "I am choosing health over \(habit) because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateWeightLossAffirmation(reason: String) -> String {
        let templates = [
            "I am becoming healthier and stronger because \(reason)",
            "I choose nourishing foods that fuel my body because \(reason)",
            "I am transforming my body with every healthy choice because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateExerciseAffirmation(reason: String) -> String {
        let templates = [
            "I am building strength and energy through movement because \(reason)",
            "I choose to move my body with joy because \(reason)",
            "I am becoming stronger with every workout because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateSleepAffirmation(reason: String) -> String {
        let templates = [
            "I choose restful sleep that rejuvenates my mind and body because \(reason)",
            "I am creating healthy sleep habits because \(reason)",
            "I honor my body's need for quality rest because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateLearningAffirmation(goal: String, reason: String) -> String {
        let templates = [
            "I am expanding my knowledge through \(goal) because \(reason)",
            "I choose to grow my mind through \(goal) because \(reason)",
            "I am becoming wiser through \(goal) because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateConfidenceAffirmation(reason: String) -> String {
        let templates = [
            "I am building unshakeable confidence because \(reason)",
            "I believe in my abilities and worth because \(reason)",
            "I am becoming more confident with each step I take because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateGenericAffirmation(goal: String, reason: String) -> String {
        let templates = [
            "I am \(goal) because \(reason)",
            "I choose to \(goal) because \(reason)",
            "I am becoming someone who \(goal) because \(reason)",
            "I have the power to \(goal) because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
}
