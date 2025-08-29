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
    
    // Debug mode - set to true to show debug controls
    private let debugMode = true
    
    var body: some View {
        if hasCompletedOnboarding {
            // Show main app after onboarding is complete
            NavigationStack(path: $navigationCoordinator.path) {
                DashboardView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .practice(let affirmation):
                            PracticeView(affirmation: affirmation)
                        }
                    }
            }
            .environment(navigationCoordinator)
            .onAppear {
                // For debugging: Skip onboarding to test main view
                if debugMode {
                    print("🔧 Debug mode: Skipping onboarding")
                    hasCompletedOnboarding = true
                }
            }
            .overlay(alignment: .topTrailing) {
                // Debug button to reset onboarding
                if debugMode {
                    Button("Reset Onboarding") {
                        hasCompletedOnboarding = false
                    }
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding()
                }
            }
            
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
