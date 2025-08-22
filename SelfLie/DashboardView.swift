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
        VStack {
            if affirmations.isEmpty {
                emptyStateView
            } else {
                affirmationsList
            }
            
            Spacer()
        }
        .background(Color(hex: "#f9f9f9"))
        .navigationTitle("My Reps")
        .ignoresSafeArea(.all, edges: .bottom)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
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
        ScrollView {
            LazyVStack(spacing: 16) {
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
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

// MARK: - Custom Context Menu
struct CustomContextMenu: View {
    @Binding var isShowing: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Delete option
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowing = false
                }
                onDelete()
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(.primary)
                    Text("Delete")
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(width: 150)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct AffirmationCardView: View {
    let affirmation: Affirmation
    let onPlayTapped: () -> Void
    let onDelete: () -> Void
    
    @State private var showCustomMenu = false
    @State private var menuPosition: CGPoint = .zero
    @State private var longPressLocation: CGPoint = .zero
    
    var body: some View {
        ZStack {
            // Card content
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
                
                Button(action: onPlayTapped) {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.purple)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !showCustomMenu {
                                        longPressLocation = value.location
                                        
                                        let cardWidth = geometry.size.width
                                        let cardHeight = geometry.size.height
                                        let menuWidth: CGFloat = 150
                                        let menuHeight: CGFloat = 48  // Height of single menu item
                                        
                                        // Determine if tap is on left or right side of card
                                        let isLeftSide = value.location.x < cardWidth / 2
                                        
                                        // Calculate menu position based on tap location
                                        var xOffset: CGFloat
                                        var yOffset: CGFloat
                                        
                                        if isLeftSide {
                                            // Tap on left: menu appears to the right (menu's left edge at finger)
                                            xOffset = value.location.x - cardWidth/2 + menuWidth/2
                                        } else {
                                            // Tap on right: menu appears to the left (menu's right edge at finger)
                                            xOffset = value.location.x - cardWidth/2 - menuWidth/2
                                        }
                                        
                                        // Y-axis: menu top edge slightly above finger position
                                        yOffset = value.location.y - cardHeight/2 + menuHeight/2 - 20
                                        
                                        // Boundary checks to keep menu within card bounds
                                        let minX = -cardWidth/2 + menuWidth/2 + 10
                                        let maxX = cardWidth/2 - menuWidth/2 - 10
                                        xOffset = max(minX, min(maxX, xOffset))
                                        
                                        // Ensure menu doesn't go too high
                                        if yOffset < -cardHeight/2 + menuHeight/2 {
                                            yOffset = -cardHeight/2 + menuHeight/2 + 10
                                        }
                                        
                                        menuPosition = CGPoint(x: xOffset, y: yOffset)
                                    }
                                }
                        )
                        .onTapGesture {
                            if showCustomMenu {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showCustomMenu = false
                                }
                            } else {
                                onPlayTapped()
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showCustomMenu = true
                            }
                        }
                }
            )
            
            // Custom menu overlay
            if showCustomMenu {
                CustomContextMenu(
                    isShowing: $showCustomMenu,
                    onDelete: onDelete
                )
                .offset(x: menuPosition.x, y: menuPosition.y)
                .transition(.scale(scale: 0.8, anchor: .center).combined(with: .opacity))
                .zIndex(1)
            }
        }
    }
}

#Preview {
        DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

