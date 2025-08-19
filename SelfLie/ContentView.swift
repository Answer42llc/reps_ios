//
//  ContentView.swift
//  SelfLie
//
//  Created by lw on 7/18/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @State private var navigationCoordinator = NavigationCoordinator()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        if hasCompletedOnboarding {
            // Show main app after onboarding is complete
            NavigationStack(path: $navigationCoordinator.path) {
                DashboardView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .addAffirmation:
                            AddAffirmationView()
                        case .recording(let text):
                            RecordingView(affirmationText: text)
                        case .practice(let affirmation):
                            PracticeView(affirmation: affirmation)
                        }
                    }
            }
            .environment(navigationCoordinator)
        } else {
            // Show onboarding for new users
            OnboardingContainerView()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
