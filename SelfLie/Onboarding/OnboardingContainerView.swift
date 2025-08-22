import SwiftUI

struct OnboardingContainerView: View {
    @State private var onboardingData = OnboardingData()
    
    var body: some View {
        NavigationStack {
            Group {
                switch onboardingData.currentStep {
                case 1:
                    DefineGoalView(dataModel: onboardingData)
                case 2:
                    GiveReasonView(dataModel: onboardingData)
                case 3:
                    SpeakAndRecordView(onboardingData: onboardingData)
                case 4:
                    FirstPracticeView(onboardingData: onboardingData)
                case 5:
                    OnboardingCompleteView(onboardingData: onboardingData)
                default:
                    DefineGoalView(dataModel: onboardingData)
                }
            }
            .navigationBarHidden(true)
            .background(Color(hex: "#f9f9f9"))
        }
    }
}

#Preview {
    OnboardingContainerView()
}