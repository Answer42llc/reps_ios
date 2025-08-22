import SwiftUI
import CoreData

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    
    let affirmationText: String
    @Binding var showingAddAffirmation: Bool
    
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    @State private var recordingState: RecordingState = .idle
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var similarity: Float = 0.0
    
    @State private var recordingFileName = ""
    
    // Smart recording stop
    @State private var maxRecordingTimer: Timer?
    @State private var recordingStartTime: Date?
    @State private var hasGoodSimilarity = false
    @State private var capturedRecognitionText: String = ""
    
    // Word highlighting states (matching SpeakAndRecordView)
    @State internal var highlightedWordIndices: Set<Int> = []
    @State internal var currentWordIndex: Int = -1
    
    private var recordingURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(recordingFileName)
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color(hex: "#f9f9f9")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Fixed height title and description area
                VStack(alignment: .leading, spacing: 8) {
                    Text(titleForState)
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 88, maxHeight: 88, alignment: .top)
                    
                    Text(descriptionForState)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(recordingState == .idle ? 1 : 0)
                        .frame(minHeight: 66, maxHeight: 66)
                }
                .padding(.horizontal, 16)
                
                // Card view with fixed position
                cardView
                    .padding(.top, 40)
                
                Spacer()
                
                // Bottom action area
                actionButtonForState
                    .padding(.bottom, 40)
            }
            .padding(.top, 80)
            
            // Cancel button overlay (top-left)
            VStack {
                HStack {
                    Button("Cancel") {
                        cleanup()
                        showingAddAffirmation = false
                    }
                    .font(.body)
                    .foregroundColor(.purple)
                    .padding()
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .fontDesign(.serif)
        .navigationBarHidden(true)
        .onAppear {
            // Generate unique filename for this recording session
            recordingFileName = "\(UUID().uuidString).m4a"
            setupSpeechService()
        }
        .task {
            await requestPermissions()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: speechService.recognizedText) { _, newText in
            // Monitor for smart recording stop
            if recordingState == .recording && !newText.isEmpty {
                capturedRecognitionText = newText
                
                let currentSimilarity = speechService.calculateSimilarity(
                    expected: affirmationText, 
                    recognized: newText
                )
                
                if currentSimilarity >= 0.8 && !hasGoodSimilarity {
                    hasGoodSimilarity = true
                    print("🎯 Good similarity achieved: \(currentSimilarity)")
                    monitorSilenceForSmartStop()
                }
            }
        }
    }
    
    // MARK: - Card View
    private var cardView: some View {
        PracticeCardView(
            statusContent: {
                statusArea
            },
            mainContent: {
                VStack(spacing: 16) {
                    // Affirmation text with highlighting
                    HighlightedAffirmationText(
                        text: affirmationText,
                        highlightedWordIndices: highlightedWordIndices
                    )
                    .padding(24)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    
                    // Real-time recognition feedback (only during recording)
                    if recordingState == .recording && !speechService.recognizedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recognized:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(speechService.recognizedText)
                                .font(.body)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
            },
            actionContent: {
                EmptyView()
            },
            showActionArea: false
        )
    }
    
    @ViewBuilder
    private var statusArea: some View {
        if recordingState == .recording {
            PracticeStatusPill(text: "Speak now")
        } else if recordingState == .analyzing {
            PracticeStatusPill(text: "Analyzing...")
        } else if recordingState == .completed && similarity >= 0.8 {
            PracticeSuccessStatus()
        } else if recordingState == .completed && similarity < 0.8 {
            PracticeFailureStatus()
        }
    }
    
    private var titleForState: String {
        switch recordingState {
        case .idle:
            return "Record Your Affirmation"
        case .recording:
            return "Recording..."
        case .analyzing:
            return "Analyzing..."
        case .completed:
            if similarity >= 0.8 {
                return "Great! Recording saved"
            } else {
                return "Please try again"
            }
        }
    }
    
    private var descriptionForState: String {
        switch recordingState {
        case .idle:
            return "Speak clearly and with conviction"
        default:
            return ""
        }
    }
    
    @ViewBuilder
    private var actionButtonForState: some View {
        switch recordingState {
        case .idle:
            RecordingButton(isRecording: false, action: toggleRecording)
            
        case .recording:
            RecordingButton(isRecording: true, action: toggleRecording)
            
        case .analyzing:
            LoadingIndicator()
            
        case .completed:
            if similarity >= 0.8 {
                // Success - auto-navigate after delay
                EmptyView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showingAddAffirmation = false
                        }
                    }
            } else {
                // Retry button
                RecordingButton(isRecording: false, action: toggleRecording)
            }
        }
    }
    
    // MARK: - Setup
    private func setupSpeechService() {
        speechService.onWordRecognized = { [self] recognizedText, wordIndices in
            Task { @MainActor in
                highlightedWordIndices = wordIndices
            }
        }
    }
    
    // MARK: - Recording Logic
    private func toggleRecording() {
        switch recordingState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .analyzing:
            break // Can't interrupt analysis
        case .completed:
            // Allow retry if similarity was too low
            if similarity < 0.8 {
                // Reset for retry
                recordingState = .idle
                similarity = 0.0
                capturedRecognitionText = ""
                highlightedWordIndices.removeAll()
                hasGoodSimilarity = false
                // Generate new filename for retry
                recordingFileName = "\(UUID().uuidString).m4a"
                startRecording()
            }
        }
    }
    
    private func startRecording() {
        recordingState = .recording
        recordingStartTime = Date()
        hasGoodSimilarity = false
        highlightedWordIndices.removeAll()
        capturedRecognitionText = ""
        
        Task {
            do {
                // Start recording audio
                try await audioService.startRecording(to: recordingURL)
                
                // Start real-time speech recognition simultaneously
                try speechService.startRecognition(expectedText: affirmationText)
                
                // Set up maximum recording timer (10 seconds)
                await MainActor.run {
                    maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                        print("⏰ Maximum recording time reached - stopping recording")
                        self.stopRecording()
                    }
                }
                
            } catch {
                await MainActor.run {
                    showError("Failed to start recording: \(error.localizedDescription)")
                    recordingState = .idle
                }
            }
        }
    }
    
    private func stopRecording() {
        recordingState = .analyzing
        
        // Clean up smart recording timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Stop both audio recording and speech recognition
        audioService.stopRecording()
        speechService.stopRecognition()
        
        Task {
            // Calculate similarity using the real-time recognized text
            let recognizedText = capturedRecognitionText.isEmpty ? 
                speechService.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines) : 
                capturedRecognitionText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("🎯 Expected: '\(affirmationText)'")
            print("✅ Recognized: '\(recognizedText)'")
            
            if recognizedText.isEmpty {
                await MainActor.run {
                    showError("No speech was recognized. Please try speaking more clearly.")
                    recordingState = .idle
                }
                return
            }
            
            // Calculate similarity using embedding-based comparison
            similarity = speechService.calculateSimilarity(expected: affirmationText, recognized: recognizedText)
            
            print("🔍 Calculated similarity: \(similarity)")
            
            await MainActor.run {
                recordingState = .completed
                
                // Save if similarity meets threshold
                if similarity >= 0.8 {
                    saveAffirmation()
                }
            }
        }
    }
    
    private func saveAffirmation() {
        let newAffirmation = Affirmation(context: viewContext)
        newAffirmation.id = UUID()
        newAffirmation.text = affirmationText
        newAffirmation.audioFileName = recordingFileName
        newAffirmation.repeatCount = 0
        newAffirmation.targetCount = 1000
        newAffirmation.dateCreated = Date()
        
        print("Saving affirmation with audio file: \(recordingFileName)")
        
        do {
            try viewContext.save()
            
            // Start audio analysis in background to generate precise word timings
            Task {
                await analyzeAudioForWordTimings(affirmation: newAffirmation)
            }
        } catch {
            showError("Failed to save affirmation: \(error.localizedDescription)")
        }
    }
    
    /// Analyze the recorded audio to extract precise word timings
    private func analyzeAudioForWordTimings(affirmation: Affirmation) async {
        guard let audioURL = affirmation.audioURL else {
            print("⚠️ [RecordingView] No audio URL available for analysis")
            return
        }
        
        print("🎯 [RecordingView] Starting background audio analysis for word timings")
        
        do {
            let wordTimings = try await speechService.analyzeAudioFile(at: audioURL, expectedText: affirmation.text)
            
            // Update the affirmation with precise timings on main thread
            await MainActor.run {
                affirmation.wordTimings = wordTimings
                
                do {
                    try viewContext.save()
                    print("✅ [RecordingView] Saved \(wordTimings.count) precise word timings")
                } catch {
                    print("⚠️ [RecordingView] Failed to save word timings: \(error)")
                }
            }
        } catch {
            print("⚠️ [RecordingView] Audio analysis failed: \(error)")
            // Don't fail the affirmation creation - it will use fallback timing
        }
    }
    
    private func requestPermissions() async {
        let microphoneGranted = await audioService.requestMicrophonePermission()
        let speechGranted = await speechService.requestSpeechRecognitionPermission()
        
        if !microphoneGranted {
            showError("Microphone permission is required for recording")
        }
        
        if !speechGranted {
            showError("Speech recognition permission is required for verification")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func monitorSilenceForSmartStop() {
        // Set up silence detection callback for smart stop
        speechService.onSilenceDetected = { isSilent in
            if isSilent && self.hasGoodSimilarity && self.recordingState == .recording {
                print("🤫 Silence detected with good similarity - stopping recording")
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
    }
    
    private func cleanup() {
        // Stop both services
        audioService.stopRecording()
        speechService.stopRecognition()
        
        // Clean up timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Clean up the recording file if it exists and wasn't saved
        if recordingState != .completed || similarity < 0.8 {
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }
}

enum RecordingState {
    case idle
    case recording
    case analyzing
    case completed
}

#Preview {
    RecordingView(
        affirmationText: "I never smoke, because smoking is smelly",
        showingAddAffirmation: .constant(true)
    )
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}