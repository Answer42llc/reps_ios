import SwiftUI

@Observable
class NavigationCoordinator {
    var path = NavigationPath()
    private var pathStack: [NavigationDestination] = []
    
    // MARK: - Navigation Actions
    func navigateToAddAffirmation() {
        let destination = NavigationDestination.addAffirmation
        path.append(destination)
        pathStack.append(destination)
    }
    
    func navigateToRecording(text: String) {
        let destination = NavigationDestination.recording(text: text)
        path.append(destination)
        pathStack.append(destination)
    }
    
    func navigateToPractice(affirmation: Affirmation) {
        let destination = NavigationDestination.practice(affirmation: affirmation)
        path.append(destination)
        pathStack.append(destination)
    }
    
    // MARK: - Navigation Controls
    func goBack() {
        if !pathStack.isEmpty {
            path.removeLast()
            pathStack.removeLast()
        }
    }
    
    func popToRoot() {
        let count = pathStack.count
        if count > 0 {
            path.removeLast(count)
            pathStack.removeAll()
        }
    }
    
    func popToScreen(_ destination: NavigationDestination) {
        // Find the destination in our tracked path and pop to it
        if let index = pathStack.firstIndex(of: destination) {
            let countToRemove = pathStack.count - index - 1
            if countToRemove > 0 {
                path.removeLast(countToRemove)
                pathStack.removeLast(countToRemove)
            }
        }
    }
    
    // MARK: - Convenience Methods
    func completeAddAffirmationFlow() {
        // After successful recording, go back to dashboard
        popToRoot()
    }
    
    func completePracticeSession() {
        // After practice, go back to dashboard
        popToRoot()
    }
    
    // MARK: - Debug Helpers
    var currentPath: [NavigationDestination] {
        pathStack
    }
    
    var pathDescription: String {
        pathStack.map { "\($0)" }.joined(separator: " → ")
    }
}

// MARK: - Navigation Destinations
enum NavigationDestination: Hashable {
    case addAffirmation
    case recording(text: String)
    case practice(affirmation: Affirmation)
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        switch self {
        case .addAffirmation:
            hasher.combine("addAffirmation")
        case .recording(let text):
            hasher.combine("recording")
            hasher.combine(text)
        case .practice(let affirmation):
            hasher.combine("practice")
            hasher.combine(affirmation.id)
        }
    }
    
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.addAffirmation, .addAffirmation):
            return true
        case (.recording(let text1), .recording(let text2)):
            return text1 == text2
        case (.practice(let aff1), .practice(let aff2)):
            return aff1.id == aff2.id
        default:
            return false
        }
    }
}