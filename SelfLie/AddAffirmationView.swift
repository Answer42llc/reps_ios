import SwiftUI
import CoreData

struct AddAffirmationContainerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var showingAddAffirmation: Bool
    @State private var addAffirmationData = AddAffirmationData()
    @State private var shouldSaveAffirmation = false
    
    var body: some View {
        ZStack {
            // Background color
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            // Child view content
            Group {
                switch addAffirmationData.currentStep {
                case 1:
                    DefineGoalView(dataModel: addAffirmationData)
                case 2:
                    GiveReasonView(dataModel: addAffirmationData)
                case 3:
                    // Wrapper to handle saving before using generic SpeakAndRecordView
                    AddAffirmationRecordingWrapper(
                        addAffirmationData: addAffirmationData,
                        showingAddAffirmation: $showingAddAffirmation
                    )
                    .environment(\.managedObjectContext, viewContext)
                default:
                    DefineGoalView(dataModel: addAffirmationData)
                }
            }
            
            // Unified progress bar at the top for add affirmation flow
            VStack {
                OnboardingProgressBar(progress: addAffirmationData.progress)
                    .padding(.top, 48)
                    .padding(.bottom, 30)
                Spacer()
            }
            
            VStack {
                HStack {
                    Button(action: {
                        showingAddAffirmation = false

                    }) {
                        Image(systemName: "xmark")
                    }
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)
                    .fontDesign(.default)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Spacer()
                }
                Spacer()
            }

        }
        .navigationBarHidden(true)
    }
}

// Wrapper view to handle saving affirmation to Core Data
struct AddAffirmationRecordingWrapper: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(CloudSyncService.self) private var cloudSyncService
    @Bindable var addAffirmationData: AddAffirmationData
    @Binding var showingAddAffirmation: Bool
    @State private var internalShowingAddAffirmation: Bool = true
    
    var body: some View {
        SpeakAndRecordView(
            dataModel: addAffirmationData,
            flowType: .addAffirmation,
            showingAddAffirmation: $internalShowingAddAffirmation
        )
        .onChange(of: internalShowingAddAffirmation) { _, newValue in
            if !newValue && addAffirmationData.audioURL != nil {
                // Save affirmation when SpeakAndRecordView completes successfully
                saveAffirmation()
            } else if !newValue {
                // Just close without saving if no audio
                showingAddAffirmation = false
            }
        }
    }
    
    private func saveAffirmation() {
        guard let audioURL = addAffirmationData.audioURL else { return }
        
        // Generate unique filename and move the recording to permanent location
        let recordingFileName = "\(UUID().uuidString).m4a"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let permanentURL = documentsPath.appendingPathComponent(recordingFileName)
        
        do {
            // Move file from temporary to permanent location
            try FileManager.default.moveItem(at: audioURL, to: permanentURL)
            
            // Create and save affirmation
            let newAffirmation = Affirmation(context: viewContext)
            newAffirmation.id = UUID()
            newAffirmation.text = addAffirmationData.affirmationText
            newAffirmation.audioFileName = recordingFileName
            newAffirmation.repeatCount = 0
            newAffirmation.targetCount = 1000
            newAffirmation.dateCreated = Date()
            newAffirmation.wordTimings = addAffirmationData.wordTimings
            newAffirmation.updatedAt = Date()
            newAffirmation.lastPracticedAt = nil
            newAffirmation.isArchived = false
            
            try viewContext.save()
            cloudSyncService.enqueueUpload(for: newAffirmation.objectID)
            print("✅ Affirmation saved successfully with audio file: \(recordingFileName)")
            
            // Close the view
            showingAddAffirmation = false
        } catch {
            print("❌ Failed to save affirmation: \(error.localizedDescription)")
            showingAddAffirmation = false
        }
    }
}

#Preview {
    let previewPersistence = PersistenceController.preview
    let syncService = CloudSyncService.liveService(persistence: previewPersistence)
    syncService.activateSync()

    return AddAffirmationContainerView(showingAddAffirmation: .constant(true))
        .environment(\.managedObjectContext, previewPersistence.container.viewContext)
        .environment(syncService)
}
