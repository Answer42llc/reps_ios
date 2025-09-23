import SwiftUI

struct OnboardingContainerView: View {
    @State private var onboardingData = OnboardingData()
    @State private var showingAddAffirmation = false // Dummy binding for onboarding flow
    @State private var showIntro = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                if showIntro {
                    OnboardingIntroView {
                        withAnimation(.easeInOut) {
                            showIntro = false
                        }
                    }
                    .transition(.opacity)
                }
                
                if !showIntro {
                    ZStack {
                        // Background color
                        Color(UIColor.systemGroupedBackground)
                            .ignoresSafeArea()
                        
                        // Child view content
                        Group {
                            switch onboardingData.currentStep {
                            case 1:
                                DefineGoalView(dataModel: onboardingData)
                            case 2:
                                GiveReasonView(dataModel: onboardingData)
                            case 3:
                                SpeakAndRecordView(
                                    dataModel: onboardingData,
                                    flowType: .onboarding,
                                    showingAddAffirmation: $showingAddAffirmation
                                )
                            case 4:
                                FirstPracticeView(onboardingData: onboardingData)
                            case 5:
                                OnboardingCompleteView(onboardingData: onboardingData)
                            default:
                                DefineGoalView(dataModel: onboardingData)
                            }
                        }
                        
                        // Unified progress bar at the top
                        VStack {
                            OnboardingProgressBar(progress: onboardingData.progress)
                                .padding(.top, 48)
                            Spacer()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: showIntro)
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    OnboardingContainerView()
}
