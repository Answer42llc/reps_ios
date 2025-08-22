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
        EmptyView()
            .onAppear {
                // For debugging: automatically reset onboarding on each app launch
                if debugMode {
                    print("🔧 Debug mode: Resetting onboarding flag")
                    hasCompletedOnboarding = false
                }
            }
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
            .overlay(alignment: .topTrailing) {
                // Debug button to reset onboarding
                if debugMode {
                    Button("Reset Onboarding") {
                        hasCompletedOnboarding = false
                    }
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
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
