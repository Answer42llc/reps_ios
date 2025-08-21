import Foundation

@Observable
class OnboardingData {
    var currentStep = 1
    var goal = ""
    var reason = ""
    var affirmationText = ""
    var audioURL: URL?
    var practiceCount = 0
    var wordTimings: [WordTiming] = []
    
    var progress: Double {
        Double(currentStep) / 5.0
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
    }
}
