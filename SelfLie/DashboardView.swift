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
        sortDescriptors: [NSSortDescriptor(keyPath: \Affirmation.dateCreated, ascending: false)])
    private var affirmations: FetchedResults<Affirmation>
    
    @State private var selectedAffirmation: Affirmation?
    @State private var showingAddAffirmation = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: 16) {
                    if affirmations.isEmpty {
                        emptyStateView
                            .padding(.top, 100)
                    } else {
                        ForEach(affirmations, id: \.objectID) { affirmation in
                            AffirmationCardView(
                                affirmation: affirmation,
                                onPlayTapped: {
                                    selectedAffirmation = affirmation
                                },
                                onDelete: {
                                    deleteAffirmation(affirmation)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("My Reps")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    HapticManager.shared.trigger(.mediumImpact)
                    showingAddAffirmation = true
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
        .fullScreenCover(isPresented: $showingAddAffirmation) {
            AddAffirmationContainerView(showingAddAffirmation: $showingAddAffirmation)
        }
    }

    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No reps yet")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Tap 'Add' to create your first rep")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private func deleteAffirmations(offsets: IndexSet) {
        offsets.map { affirmations[$0] }.forEach(viewContext.delete)
        
        do {
            try viewContext.save()
        } catch {
            // Handle error appropriately
        }
    }
    
    private func deleteAffirmation(_ affirmation: Affirmation) {
        // Clear selection if deleting the selected affirmation
        if selectedAffirmation?.objectID == affirmation.objectID {
            selectedAffirmation = nil
        }
        
        viewContext.delete(affirmation)
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete affirmation: \(error)")
        }
    }
}

struct AffirmationCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var affirmation: Affirmation
    let onPlayTapped: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 0) {
                    Text("🔥")
                    Text("\(affirmation.repeatCount)/1000")
                        .foregroundColor(.primary)
                }
                .font(.subheadline)
                
                Text(affirmation.text)
                    .font(.title3)
                    .lineLimit(nil)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Button(action: {
                HapticManager.shared.trigger(.mediumImpact)
                onPlayTapped()
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.purple)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(colorScheme == .dark ? UIColor.secondarySystemBackground : UIColor.systemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.trigger(.mediumImpact)
            onPlayTapped()
        }
        .contextMenu {
            Button(role: .destructive) {
                HapticManager.shared.trigger(.heavyImpact)
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
        DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

