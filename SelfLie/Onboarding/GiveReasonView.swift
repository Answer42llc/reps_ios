import SwiftUI

struct GiveReasonView<DataModel: AffirmationDataProtocol>: View {
    @Bindable var dataModel: DataModel
    @State private var customReason = ""
    @FocusState private var isReasonFieldFocused: Bool
    
    private var isReasonValid: Bool {
        !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var dynamicPlaceholder: String {
        "Why you want to \(dataModel.goal.lowercased())?"
    }
    
    private var presetReasons: [String] {
        // Mock data for now - will be dynamic later
        if dataModel.goal.lowercased().contains("smoke") {
            return ["Smoke is smelly", "Girls don't like it"]
        } else {
            return ["It makes me feel good", "It's the right thing to do"]
        }
    }
    
    var body: some View {
        ZStack{
            ScrollView{
                VStack(spacing: 0) {
                    // Title and description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Give it a reason")
                            .font(.largeTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("Giving your goals a clear reason can helps you achieve them, as our brains are always looking for reasons.")
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
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(presetReasons, id: \.self) { reason in
                                HStack {
                                    OnboardingPresetButton(title: reason) {
                                        customReason = reason
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                }
                .padding(.top, 80)
                .fontDesign(.serif)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            
            VStack{
                // Progress indicator
                OnboardingProgressBar(progress: dataModel.progress)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                Spacer()
            }
            
            // Bottom section with text field and navigation
            VStack(spacing: 0) {
                Spacer()
                // Text input area
                HStack(spacing: 12) {
                    OnboardingTextField(
                        placeholder: dynamicPlaceholder,
                        text: $customReason
                    )
                    .focused($isReasonFieldFocused)
                    
                    // Navigation arrow
                    OnboardingArrowButton(isEnabled: isReasonValid) {
                        dataModel.reason = customReason
                        dataModel.generateAffirmation()
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
            }
        }
        .background(Color(hex: "#f9f9f9"))
        .onAppear {
            isReasonFieldFocused = true
        }
    }
}

#Preview {
    let data = OnboardingData()
    data.goal = "Quit smoke"
    return GiveReasonView(dataModel: data)
}
