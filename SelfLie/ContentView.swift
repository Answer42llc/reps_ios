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
    
    var body: some View {
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
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
