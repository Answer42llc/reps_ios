import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            DashboardView()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}