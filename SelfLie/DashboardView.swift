import SwiftUI
import CoreData

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

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
        .fontDesign(.serif)
        .background(Color(hex: "#f9f9f9"))
        .navigationTitle("My Reps")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    navigationCoordinator.navigateToAddAffirmation()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                }
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
                .fontDesign(.serif)
                .foregroundColor(.secondary)
            
            Text("Tap 'Add' to create your first affirmation")
                .font(.body)
                .fontDesign(.serif)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var affirmationsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(affirmations, id: \.id) { affirmation in
                    AffirmationCardView(affirmation: affirmation) {
                        selectedAffirmation = affirmation
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
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

struct AffirmationCardView: View {
    let affirmation: Affirmation
    let onPlayTapped: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("🔥")
                        .font(.title3)
                        .fontDesign(.serif)
                    Text("\(affirmation.repeatCount)/1000")
                        .font(.headline)
                        .fontDesign(.serif)
                        .foregroundColor(.primary)
                }
                
                Text(affirmation.text)
                    .font(.body)
                    .fontDesign(.serif)
                    .lineLimit(nil)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Button(action: onPlayTapped) {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.purple)
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
        DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
