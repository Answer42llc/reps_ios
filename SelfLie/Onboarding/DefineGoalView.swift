import SwiftUI

struct DefineGoalView<DataModel: AffirmationDataProtocol>: View {
    @Bindable var dataModel: DataModel
    @State private var customGoal = ""
    @FocusState private var isGoalFieldFocused: Bool
    
    private var isGoalValid: Bool {
        !customGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        ZStack{
            VStack(spacing: 0) {
                    // Title and description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Define your goal")
                            .font(.largeTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("Your goals can be anything you want to achieve, such as quitting porn, go to the gym everyday, or staying positive and optimistic.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                    
                    // Preset options section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select blow or type your own")
                            .font(.headline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Preset buttons
                        HStack(spacing: 12) {
                            OnboardingPresetButton(title: "Quit smoke") {
                                customGoal = "Quit smoke"
                            }
                            
                            OnboardingPresetButton(title: "Quit porn") {
                                customGoal = "Quit porn"
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            OnboardingPresetButton(title: "Be nice") {
                                customGoal = "Be nice"
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                    

                }
                .padding(.top,80)
                .fontDesign(.serif)

            
            
            // Bottom section with text field and navigation
            VStack(spacing: 0) {
                Spacer()
                // Text input area
                HStack(spacing: 12) {
                    OnboardingTextField(
                        placeholder: "What's your goal?",
                        text: $customGoal
                    )
                    .focused($isGoalFieldFocused)
                    
                    // Navigation arrow
                    OnboardingArrowButton(isEnabled: isGoalValid) {
                        dataModel.goal = customGoal
                        
                        // Generate reason suggestions in the background
                        Task {
                            await dataModel.generateReasonSuggestions()
                        }
                        
                        dataModel.nextStep()
                    }
                }
                .padding(.vertical, 4)
                .overlay(
                    Rectangle()
                        .frame(height: 0.3)
                        .foregroundColor(Color.gray.opacity(0.6)),
                    alignment: .top
                )
                .padding(.horizontal, 16)
                .background(Color(.systemBackground))
                
            }

        }
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear {
            isGoalFieldFocused = true
            // Prewarm AI session for affirmation generation
            dataModel.prewarmAISession()
        }


    }
}

#Preview {
    DefineGoalView(dataModel: OnboardingData())
}
