import SwiftUI

struct GiveReasonView<DataModel: AffirmationDataProtocol>: View {
    @Bindable var dataModel: DataModel
    @State private var customReason = ""
    @FocusState private var isReasonFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    
    private var isReasonValid: Bool {
        !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var dynamicPlaceholder: String {
        "Why you want to \(dataModel.goal.lowercased())?"
    }
    
    private var presetReasons: [String] {
        // Use dynamically generated suggestions if available
        if !dataModel.reasonSuggestions.isEmpty {
            return dataModel.reasonSuggestions
        }
        
        // Fallback to basic suggestions if generation hasn't completed or failed
        let goalLower = dataModel.goal.lowercased()
        if goalLower.contains("smoke") || goalLower.contains("烟") {
            return ["save money", "breathe easier", "smell fresh", "live longer"]
        } else if goalLower.contains("exercise") || goalLower.contains("锻炼") {
            return ["boost energy", "improve mood", "sleep better", "build strength"]
        } else if goalLower.contains("porn") || goalLower.contains("色情") {
            return ["better relationships", "more productive", "improved focus", "self-control"]
        } else {
            return ["feel better", "improve life", "achieve goals", "be happier"]
        }
    }
    
    var body: some View {
        ZStack{
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
                        
                        // Loading indicator or preset buttons
                        if dataModel.isGeneratingReasons {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                                    .scaleEffect(0.8)
                                Text("Generating personalized suggestions...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fontDesign(.serif)
                            }
                            .padding(.vertical, 8)
                        } else {
                            // Preset buttons
                            ScrollView{
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
                                .padding(.bottom, 64)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                }
                .padding(.top, 80)
                .fontDesign(.serif)
            
            
            // Bottom section with text field and navigation
            VStack(spacing: 0) {
                Spacer()
                
                // Generation status indicator (when generating)
                if dataModel.isGeneratingAffirmation {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                                .scaleEffect(0.8)
                            
                            Text(dataModel.generationStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontDesign(.serif)
                        }
                    }
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale))
                }
                
                // Text input area
                HStack(spacing: 12) {
                    OnboardingTextField(
                        placeholder: dynamicPlaceholder,
                        text: $customReason
                    )
                    .focused($isReasonFieldFocused)
                    
                    // Navigation arrow
                    OnboardingArrowButton(isEnabled: isReasonValid && !dataModel.isGeneratingAffirmation) {
                        dataModel.reason = customReason
                        
                        // Use async generation for better AI-powered affirmations
                        Task {
                            do {
                                _ = try await dataModel.generateAffirmationAsync()
                                await MainActor.run {
                                    dataModel.nextStep()
                                }
                            } catch {
                                // Error is already handled within generateAffirmationAsync
                                // It will use fallback generation, so we can continue
                                await MainActor.run {
                                    dataModel.nextStep()
                                }
                                print("⚠️ Affirmation generation completed with fallback: \(error.localizedDescription)")
                            }
                        }
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
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.3), value: dataModel.isGeneratingAffirmation)
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
