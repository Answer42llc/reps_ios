import SwiftUI

@Observable
class NavigationCoordinator {
    var path = NavigationPath()
    private var pathStack: [NavigationDestination] = []
    
    // MARK: - Navigation Actions
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
    case practice(affirmation: Affirmation)
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        switch self {
        case .practice(let affirmation):
            hasher.combine("practice")
            hasher.combine(affirmation.id)
        }
    }
    
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.practice(let aff1), .practice(let aff2)):
            return aff1.id == aff2.id
        }
    }
}