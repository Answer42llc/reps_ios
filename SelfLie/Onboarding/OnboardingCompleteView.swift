import SwiftUI
import CoreData

enum OnboardingCompleteState {
    case philosophy
    case ready
}

struct OnboardingCompleteView: View {
    @Bindable var onboardingData: OnboardingData
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var completeState: OnboardingCompleteState = .philosophy
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Progress indicator - always 100%
            OnboardingProgressBar(progress: 1.0)
                .padding(.top, 20)
            
            Spacer()
            
            // Title based on state
            Text(titleForState)
                .font(.title)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Spacer()
            
            // Fire emoji with +1
            HStack(spacing: 8) {
                Text("🔥")
                    .font(.system(size: 50))
                
                Text("+1")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            // Action button
            OnboardingContinueButton(
                title: buttonTitleForState,
                isEnabled: true
            ) {
                handleButtonTap()
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
        .background(Color(hex: "#f9f9f9"))
        .fontDesign(.serif)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var titleForState: String {
        switch completeState {
        case .philosophy:
            return "Even a lie repeated a thousand times becomes the truth."
        case .ready:
            return "All you need is motivate yourself 1000 times until your goal become true. I'll remind you."
        }
    }
    
    private var buttonTitleForState: String {
        switch completeState {
        case .philosophy:
            return "Continue"
        case .ready:
            return "Let's Start"
        }
    }
    
    private func handleButtonTap() {
        switch completeState {
        case .philosophy:
            completeState = .ready
            
        case .ready:
            // Complete onboarding
            Task {
                await completeOnboarding()
            }
        }
    }
    
    private func completeOnboarding() async {
        // Request notification permission
        let _ = await PermissionManager.requestNotificationPermission()
        
        // Save the affirmation to Core Data
        await MainActor.run {
            do {
                try saveAffirmationToCoreData()
                
                // Mark onboarding as completed
                hasCompletedOnboarding = true
                
            } catch {
                errorMessage = "Failed to complete onboarding: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func saveAffirmationToCoreData() throws {
        // Create new Affirmation entity
        let newAffirmation = Affirmation(context: viewContext)
        let affirmationId = UUID()
        
        newAffirmation.id = affirmationId
        newAffirmation.text = onboardingData.affirmationText
        newAffirmation.repeatCount = Int32(onboardingData.practiceCount) // Should be 1
        newAffirmation.targetCount = 1000 // Default target
        newAffirmation.dateCreated = Date()
        
        // Save the audio file if available
        if let audioURL = onboardingData.audioURL {
            // Create filename for permanent storage
            let audioFileName = "\(affirmationId.uuidString).m4a"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let permanentURL = documentsPath.appendingPathComponent(audioFileName)
            
            do {
                try FileManager.default.copyItem(at: audioURL, to: permanentURL)
                newAffirmation.audioFileName = audioFileName
                
                // Clean up temporary file
                try? FileManager.default.removeItem(at: audioURL)
            } catch {
                print("Failed to save audio file: \(error)")
                // Continue without audio if file save fails
                newAffirmation.audioFileName = ""
            }
        } else {
            newAffirmation.audioFileName = ""
        }
        
        // Save word timings if available
        if !onboardingData.wordTimings.isEmpty {
            newAffirmation.wordTimings = onboardingData.wordTimings
            print("✅ Saved \(onboardingData.wordTimings.count) word timings from onboarding")
        }
        
        // Save to Core Data
        try viewContext.save()
        print("✅ Onboarding affirmation saved successfully")
    }
}

#Preview {
    let data = OnboardingData()
    data.currentStep = 5
    data.goal = "quit smoke"
    data.reason = "smoke is smelly"
    data.generateAffirmation()
    data.practiceCount = 1
    
    return OnboardingCompleteView(onboardingData: data)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}