import SwiftUI
import CoreData

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Affirmation.dateCreated, ascending: false)],
        animation: .default)
    private var affirmations: FetchedResults<Affirmation>
    
    @State private var selectedAffirmation: Affirmation?
    
    var body: some View {
        VStack {
            if affirmations.isEmpty {
                emptyStateView
            } else {
                affirmationsList
            }
            
            Spacer()
        }
        .navigationTitle("I AM")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    navigationCoordinator.navigateToAddAffirmation()
                }
                .foregroundColor(.purple)
            }
        }
        .fullScreenCover(item: $selectedAffirmation) { affirmation in
            PracticeView(affirmation: affirmation)
        }
    }
    
    private var headerView: some View {
        Text("I AM")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding(.top)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No affirmations yet")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Tap 'Add' to create your first affirmation")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var affirmationsList: some View {
        List {
            ForEach(affirmations, id: \.id) { affirmation in
                AffirmationRowView(affirmation: affirmation) {
                    selectedAffirmation = affirmation
                }
            }
            .onDelete(perform: deleteAffirmations)
        }
        .listStyle(PlainListStyle())
    }
    
    private func deleteAffirmations(offsets: IndexSet) {
        withAnimation {
            offsets.map { affirmations[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                // Handle error appropriately
            }
        }
    }
}

struct AffirmationRowView: View {
    let affirmation: Affirmation
    let onPlayTapped: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(affirmation.text)
                    .font(.headline)
                    .lineLimit(2)
                
                Text("Repeated \(affirmation.progressText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onPlayTapped) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.purple)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
