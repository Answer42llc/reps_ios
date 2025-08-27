import Foundation
import SwiftUI

@MainActor
@Observable
class OnboardingData: AffirmationDataProtocol {
    var currentStep = 1
    var goal = ""
    var reason = ""
    var affirmationText = ""
    var audioURL: URL?
    var practiceCount = 0
    var wordTimings: [WordTiming] = []
    
    // Reason suggestions state
    var reasonSuggestions: [String] = []
    var isGeneratingReasons = false
    
    // Unified affirmation service (handles both Foundation Models and pattern-based generation)
    private let affirmationService = AffirmationService()
    
    // Convenience properties for UI
    var isGeneratingAffirmation: Bool {
        affirmationService.isGenerating
    }
    
    var generationError: AffirmationError? {
        affirmationService.generationError
    }
    
    var progress: Double {
        Double(currentStep) / 5.0
    }
    
    var canUseFoundationModels: Bool {
        affirmationService.canUseFoundationModels
    }
    
    func generateAffirmation() {
        // Legacy synchronous method for backward compatibility
        // This is now a simple fallback that uses pattern generation
        Task {
            do {
                let result = try await generateAffirmationAsync()
                await MainActor.run {
                    affirmationText = result
                }
            } catch {
                // If async generation fails, use simple fallback
                await MainActor.run {
                    let goalLower = goal.lowercased()
                    let reasonLower = reason.lowercased()
                    
                    if goalLower.contains("quit") {
                        let habit = goalLower.replacingOccurrences(of: "quit ", with: "")
                        affirmationText = "I choose to be free from \(habit) because \(reasonLower)"
                    } else {
                        affirmationText = "I am \(goalLower) because \(reasonLower)"
                    }
                }
            }
        }
    }
    
    func generateAffirmationAsync() async throws -> String {
        // Use the unified service which handles both Foundation Models and fallback
        let result = try await affirmationService.generateAffirmation(goal: goal, reason: reason)
        affirmationText = result
        return result
    }
    
    func nextStep() {
        if currentStep < 5 {
            currentStep += 1
        }
    }
    
    func reset() {
        currentStep = 1
        goal = ""
        reason = ""
        affirmationText = ""
        audioURL = nil
        practiceCount = 0
        wordTimings = []
        // Reset service state is handled internally by AffirmationService
    }
    
    // MARK: - Helper Methods
    
    /// Get user-friendly generation status message
    var generationStatusMessage: String {
        return affirmationService.statusMessage
    }
    
    /// Check if we can retry generation after an error
    var canRetryGeneration: Bool {
        return affirmationService.canRetry
    }
    
    /// Retry generation after an error
    func retryGeneration() async throws {
        let result = try await affirmationService.retryGeneration(goal: goal, reason: reason)
        affirmationText = result
    }
    
    /// Prewarm AI session when user shows intent (call when they start typing)
    func prewarmAISession() {
        print("🔥 [OnboardingData] Starting prewarm session...")
        affirmationService.prewarmSession()
        print("✅ [OnboardingData] Prewarm session completed")
    }
    
    /// Generate reason suggestions for the current goal
    func generateReasonSuggestions() async {
        guard !goal.isEmpty else {
            print("⚠️ [OnboardingData] Cannot generate reasons for empty goal")
            reasonSuggestions = []
            return
        }
        
        print("🎯 [OnboardingData] Starting reason generation for goal: '\(goal)'")
        isGeneratingReasons = true
        
        defer { isGeneratingReasons = false }
        
        let suggestions = await affirmationService.generateReasonSuggestions(goal: goal)
        
        await MainActor.run {
            reasonSuggestions = suggestions
            print("✅ [OnboardingData] Generated \(suggestions.count) reason suggestions")
        }
    }
}
