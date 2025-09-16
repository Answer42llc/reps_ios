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
    @State private var notificationObserverAdded = false
    
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
                if !notificationObserverAdded {
                    NotificationCenter.default.addObserver(forName: .openPracticeFromNotification, object: nil, queue: .main) { _ in
                        // Navigate to the most recent affirmation if available
                        let context = PersistenceController.shared.container.viewContext
                        let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
                        request.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: false)]
                        request.fetchLimit = 1
                        if let latest = try? context.fetch(request).first {
                            navigationCoordinator.navigateToPractice(affirmation: latest)
                        }
                    }
                    notificationObserverAdded = true
                }
            }
            .overlay(alignment: .topTrailing) {
                // Debug button to reset onboarding
                if debugMode {
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("Reset Onboarding") {
                            hasCompletedOnboarding = false
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                        Button("Log Notif Settings") {
                            Task { await NotificationManager.shared.debugPrintNotificationSettings() }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                        Button("List Pending Notifs") {
                            Task { await NotificationManager.shared.debugPrintPendingRequests() }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                        Button("Schedule 10s Test") {
                            NotificationManager.shared.scheduleQuickTestNotification(after: 10)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
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
