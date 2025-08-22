//
//  AddAffirmationData.swift
//  SelfLie
//
//  Created by lw on 8/22/25.
//

import Foundation

@Observable
class AddAffirmationData: AffirmationDataProtocol {
    var currentStep = 1
    var goal = ""
    var reason = ""
    var affirmationText = ""
    var audioURL: URL?
    var wordTimings: [WordTiming] = []
    
    var progress: Double {
        Double(currentStep) / 3
    }
    
    func generateAffirmation() {
        // Mock implementation - will be enhanced later with proper generation logic
        let goalLower = goal.lowercased()
        let reasonLower = reason.lowercased()
        
        // Simple pattern for now
        if goalLower.contains("quit") {
            let habit = goalLower.replacingOccurrences(of: "quit ", with: "")
            affirmationText = "I never \(habit) because \(reasonLower)"
        } else {
            affirmationText = "I am always \(goalLower) because \(reasonLower)"
        }
    }
    
    func nextStep() {
        if currentStep < 3 {
            currentStep += 1
        }
    }
    
    func reset() {
        currentStep = 1
        goal = ""
        reason = ""
        affirmationText = ""
        audioURL = nil
        wordTimings = []
    }
}
