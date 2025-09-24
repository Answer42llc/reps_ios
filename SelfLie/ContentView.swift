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
    @State private var subscriptionManager = SubscriptionManager()
    @State private var paywallController = PaywallController()
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
            .environment(subscriptionManager)
            .environment(paywallController)
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
                            if subscriptionManager.isAffirmationWithinFreeQuota(latest) {
                                navigationCoordinator.navigateToPractice(affirmation: latest)
                            } else {
                                let objectID = latest.objectID
                                paywallController.present(context: .practiceAffirmation) {
                                    let context = PersistenceController.shared.container.viewContext
                                    if let refreshed = try? context.existingObject(with: objectID) as? Affirmation {
                                        navigationCoordinator.navigateToPractice(affirmation: refreshed)
                                    }
                                }
                            }
                        }
                    }
                    notificationObserverAdded = true
                }
            }
            .fullScreenCover(isPresented: paywallBinding, onDismiss: handlePaywallDismiss) {
                PaywallView()
                    .environment(subscriptionManager)
                    .environment(paywallController)
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

    private var paywallBinding: Binding<Bool> {
        Binding(
            get: { paywallController.isPresented },
            set: { paywallController.isPresented = $0 }
        )
    }

    private func handlePaywallDismiss() {
        let pendingAction = paywallController.pendingAction
        let shouldRun = subscriptionManager.hasPremiumAccess
        paywallController.reset()
        if shouldRun {
            pendingAction?()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
