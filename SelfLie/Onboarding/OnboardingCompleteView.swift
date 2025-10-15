import SwiftUI
import CoreData

enum OnboardingCompleteState {
    case philosophy
    case ready
}

struct OnboardingCompleteView: View {
    @Bindable var onboardingData: OnboardingData
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(CloudSyncService.self) private var cloudSyncService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var completeState: OnboardingCompleteState = .philosophy
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            // Background color
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Fixed height title area (matching FirstPracticeView)
                VStack(alignment: .leading, spacing: 8) {
                    Text(titleForState)
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 88, maxHeight: 88, alignment: .top)
                }
                .padding(.horizontal, 16)
                
                // Fire emoji with +1 - centered with proper spacing
                HStack(spacing: 12) {
                    Text("🔥")
                        .font(.system(size: 64))
                    
                    Text("+1")
                        .font(.system(size: 64))
                        .fontWeight(.bold)
                        .italic()
                        .foregroundColor(.primary)
                }
                .padding(.top, 96)
                
                Spacer()
                
                // Action button
                OnboardingContinueButton(
                    title: buttonTitleForState,
                    isEnabled: true
                ) {
                    handleButtonTap()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .padding(.top, 80)
            
        }
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
            return "Next, all you need is to motivate yourself 1000 times."
        case .ready:
            return "By repeat 1000 times, even a lie can become a truth. I'll remind you."
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
        let granted = await PermissionManager.requestNotificationPermission()
        if granted {
            NotificationManager.shared.scheduleDailyNotifications()
        }

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
        newAffirmation.updatedAt = Date()
        if onboardingData.practiceCount > 0 {
            newAffirmation.lastPracticedAt = Date()
        } else {
            newAffirmation.lastPracticedAt = nil
        }
        newAffirmation.isArchived = false
        
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
        cloudSyncService.enqueueUpload(for: newAffirmation.objectID)
        print("✅ Onboarding affirmation saved successfully")
    }
}

#Preview {
    let data = OnboardingData()
    data.currentStep = 5
    data.goal = "quit smoke"
    data.reason = "smoke is smelly"
    Task {
        do {
            _ = try await data.generateAffirmationAsync()
        } catch {
            // Fallback to pattern-based generation for preview
            data.generateAffirmation()
        }
    }
    data.practiceCount = 1

    let previewPersistence = PersistenceController.preview
    let syncService = CloudSyncService.liveService(persistence: previewPersistence)
    syncService.activateSync()

    return OnboardingCompleteView(onboardingData: data)
        .environment(\.managedObjectContext, previewPersistence.container.viewContext)
        .environment(syncService)
}
