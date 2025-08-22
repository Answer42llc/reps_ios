import SwiftUI
import CoreData

struct AddAffirmationContainerView: View {
    @Binding var showingAddAffirmation: Bool
    @State private var addAffirmationData = AddAffirmationData()
    
    var body: some View {
        Group {
            switch addAffirmationData.currentStep {
            case 1:
                DefineGoalView(dataModel: addAffirmationData)
            case 2:
                GiveReasonView(dataModel: addAffirmationData)
            case 3:
                RecordingView(
                    affirmationText: addAffirmationData.affirmationText,
                    showingAddAffirmation: $showingAddAffirmation
                )
            default:
                DefineGoalView(dataModel: addAffirmationData)
            }
        }
        .navigationBarHidden(true)
        .background(Color(hex: "#f9f9f9"))
    }
}

#Preview {
    AddAffirmationContainerView(showingAddAffirmation: .constant(true))
}