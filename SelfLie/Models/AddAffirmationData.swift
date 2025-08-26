//
//  AddAffirmationData.swift
//  SelfLie
//
//  Created by lw on 8/22/25.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class AddAffirmationData: AffirmationDataProtocol {
    var currentStep = 1
    var goal = ""
    var reason = ""
    var affirmationText = ""
    var audioURL: URL?
    var wordTimings: [WordTiming] = []
    var isRecordingComplete = false
    
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
        // For add affirmation flow, keep at step 2 until recording completes
        if currentStep == 3 && !isRecordingComplete {
            return 2.0 / 3.0  // Stay at step 2
        }
        return Double(currentStep) / 3.0
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
        if currentStep < 3 {
            currentStep += 1
        }
    }
    
    func completeRecording() {
        isRecordingComplete = true
    }
    
    func reset() {
        currentStep = 1
        goal = ""
        reason = ""
        affirmationText = ""
        audioURL = nil
        wordTimings = []
        isRecordingComplete = false
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
        print("🔥 [AddAffirmationData] Starting prewarm session...")
        affirmationService.prewarmSession()
        print("✅ [AddAffirmationData] Prewarm session completed")
    }
}
