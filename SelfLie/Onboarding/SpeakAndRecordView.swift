import SwiftUI
import AVFoundation

struct SpeakAndRecordView<DataModel: AffirmationDataProtocol>: View {
    @Bindable var dataModel: DataModel
    
    enum FlowType {
        case onboarding
        case addAffirmation
    }
    
    let flowType: FlowType
    @Binding var showingAddAffirmation: Bool
    
    @State private var recordingState: RecordingState = .idle
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var similarity: Float = 0.0
    
    // Edit alert states
    @State private var showEditAlert = false
    @State private var editingText = ""
    @FocusState private var isTextEditorFocused: Bool
    
    // Smart recording stop states (same as PracticeView)
    @State private var hasGoodSimilarity = false
    @State private var capturedRecognitionText: String = ""
    @State private var maxRecordingTimer: Timer?
    
    // Word timing generation tracking
    @State private var isGeneratingTimings = false
    
    
    // Word highlighting states (reused from PracticeView)
    @State internal var highlightedWordIndices: Set<Int> = []
    @State internal var currentWordIndex: Int = -1
    @State private var wordTimings: [WordTiming] = []
    
    // Recording URL for onboarding
    @State private var onboardingRecordingURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("onboarding_\(UUID().uuidString).m4a")
    }()
    
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
                        .fixedSize(horizontal: false, vertical: true) // Allow text to wrap
                        .frame(minHeight: 88, maxHeight: 88, alignment: .top) // Fixed space for up to 3 lines
                    
                    Text(descriptionForState)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true) // Allow text to wrap
                        .opacity(recordingState == .idle ? 1 : 0) // Use opacity instead of conditional rendering
                        .frame(minHeight: 66, maxHeight: 66) // Fixed space for description
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

        }
        .fontDesign(.serif)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            setupSpeechService()
        }
        .onChange(of: speechService.recognizedText) { _, newText in
            // Monitor for smart recording stop (same as PracticeView)
            if recordingState == .recording && !newText.isEmpty {
                // Capture recognized text for later analysis
                capturedRecognitionText = newText
                print("📝 [SpeakAndRecordView] Captured recognition text: '\(newText)'")
                
                let currentSimilarity = speechService.calculateSimilarity(
                    expected: dataModel.affirmationText,
                    recognized: newText
                )
                
                // Use 80% threshold for onboarding (same as practice)
                if currentSimilarity >= 0.8 && !hasGoodSimilarity {
                    hasGoodSimilarity = true
                    print("🎯 [SpeakAndRecordView] Good similarity achieved: \(currentSimilarity)")
                    monitorSilenceForSmartStop()
                }
            }
        }
        .overlay(
            Group {
                if showEditAlert {
                    ZStack {
                        // Background dimming
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture { } // Prevent dismissal on background tap
                        
                        // Alert dialog matching app's visual style
                        VStack(spacing: 24) {
                            // Title
                            Text("Adjust your affirmation")
                                .font(.title3)
                                .fontWeight(.medium)
                                .fontDesign(.serif)
                            
                            // Text editor with app's styling
                            TextEditor(text: $editingText)
                                .font(.body)
                                .fontDesign(.serif)
                                .frame(minHeight: 100, maxHeight: 150)
                                .padding(12)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                )
                                .cornerRadius(12)
                                .focused($isTextEditorFocused)
                            
                            // Buttons matching OnboardingContinueButton style
                            HStack(spacing: 12) {
                                // Cancel button - secondary style
                                Button {
                                    HapticManager.shared.trigger(.impact(.light))
                                    showEditAlert = false
                                    editingText = dataModel.affirmationText // Reset
                                } label: {
                                    Text("Cancel")
                                        .font(.headline)
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Capsule().fill(Color.gray.opacity(0.1)))
                                        .cornerRadius(12)
                                }
                                
                                // Done button - primary style matching OnboardingContinueButton
                                Button {
                                    HapticManager.shared.trigger(.impact(.medium))
                                    let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        dataModel.affirmationText = trimmed
                                        // Reset recording states when text changes
                                        if recordingState != .idle {
                                            recordingState = .idle
                                            similarity = 0.0
                                            highlightedWordIndices.removeAll()
                                            currentWordIndex = -1  // Reset current word index
                                            hasGoodSimilarity = false
                                            capturedRecognitionText = ""
                                            // Reset speech recognizer for new language
                                            speechService.resetRecognizer()
                                            // Clean up any temporary recording
                                            try? FileManager.default.removeItem(at: onboardingRecordingURL)
                                            // Generate new URL for next recording
                                            onboardingRecordingURL = {
                                                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                                return documentsPath.appendingPathComponent("onboarding_\(UUID().uuidString).m4a")
                                            }()
                                        }
                                    }
                                    showEditAlert = false
                                } label: {
                                    Text("Done")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Capsule().fill(Color.purple))
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding(24)
                        .background(Color(hex: "#f9f9f9"))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                        .padding(.horizontal, 30)
                    }
                }
            }
        )
    }
    
    // MARK: - Card View (using common component from PracticeView)
    private var cardView: some View {
        PracticeCardView(
            statusContent: {
                statusArea
            },
            mainContent: {
                VStack(spacing: 16) {
                    // Affirmation text - using NativeTextHighlighter for proper multi-language support
                    NativeTextHighlighter(
                        text: dataModel.affirmationText,
                        highlightedWordIndices: highlightedWordIndices,
                        currentWordIndex: currentWordIndex
                    )
                    .padding(24)
                    
                    // Hint text - only show in idle state
                    if recordingState == .idle {
                        Button(action: {
                            HapticManager.shared.trigger(.impact(.light))
                            editingText = dataModel.affirmationText
                            showEditAlert = true
                            isTextEditorFocused = true
                        }) {
                            HStack {
                                Image(systemName: "pencil.line")
                                Text("Not you expected? Tap to adjust")
                                    .font(.footnote)
                            }
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "f9f9f9"))
                            )
                        }
                    }
                }
            },
            actionContent: {
                PracticeCardActionButton(
                    title: "Retry",
                    systemImage: "gobackward",
                    action: toggleRecording
                )
            },
            showActionArea: false
        )
    }
    
    @ViewBuilder
    private var statusArea: some View {
        if recordingState == .recording {
            // Recording state
            PracticeStatusPill(text: "Speak now")
        } else if recordingState == .analyzing {
            // Analyzing state - show different text based on progress
            PracticeStatusPill(text: isGeneratingTimings ? "Processing..." : "Analyzing...")
        } else if recordingState == .completed && similarity >= 0.8 {
            // Success state shows checkmark (like PracticeView)
            PracticeSuccessStatus()
        } else if recordingState == .completed && similarity < 0.8 {
            // Failure state shows Try Again (like PracticeView)
            PracticeFailureStatus()
        }
    }
    
    private var descriptionForState: String {
        switch recordingState {
        case .idle:
            return flowType == .onboarding ? 
                "Giving your goals a clear reason can helps you achieve them, as our brains are always looking for reasons." :
                "Speak clearly and with conviction"
        default:
            return ""
        }
    }
    
    private var titleForState: String {
        switch recordingState {
        case .idle:
            return "👍 Great! Now say it aloud and record."
        case .recording:
            return "Recording..."
        case .analyzing:
            return "Analyzing..."
        case .completed:
            if similarity >= 0.8 {
                return flowType == .onboarding ? 
                    "👏 Well done! Let's listen and repeat it to motivate yourself." :
                    "👏Well done!"
            } else {
                return "Please try again, speaking louder and more clearly."
            }
        }
    }
    
    @ViewBuilder
    private var actionButtonForState: some View {
        switch recordingState {
        case .idle:
            VStack(spacing: 40) {
                RecordingButton(isRecording: false, action: toggleRecording)
            }
            
        case .recording:
            RecordingButton(isRecording: true, action: toggleRecording)
            
        case .analyzing:
            LoadingIndicator()
            
        case .completed:
            if similarity >= 0.8 {
                if flowType == .onboarding {
                    OnboardingContinueButton(
                        title: "Continue",
                        isEnabled: true
                    ) {
                        // Save the recording URL and proceed
                        dataModel.audioURL = onboardingRecordingURL
                        dataModel.nextStep()
                    }
                    .padding(.horizontal, 20)
                } else {
                    // Add affirmation flow - show Done button that dismisses
                    Button(action: {
                        HapticManager.shared.trigger(.impact(.medium))
                        // Save recording data
                        dataModel.audioURL = onboardingRecordingURL
                        dataModel.wordTimings = wordTimings
                        // Navigate to RecordingView to save affirmation
                        showingAddAffirmation = false
                    }) {
                        Text("Done")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Color.purple))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                // Empty - retry button is in cardActionArea inside the card
                RecordingButton(isRecording: false, action: toggleRecording)
            }
        }
    }
    
    // MARK: - Recording Logic (reused from PracticeView)
    
    private func toggleRecording() {
        switch recordingState {
        case .idle:
            HapticManager.shared.trigger(.selection)
            startRecording()
        case .recording:
            stopRecording()
        case .analyzing:
            break // Can't interrupt analysis
        case .completed:
            // Allow retry if similarity was too low
            if similarity < 0.8 {
                // Reset for retry
                similarity = 0.0
                capturedRecognitionText = ""
                highlightedWordIndices.removeAll()
                currentWordIndex = -1  // Reset current word index
                hasGoodSimilarity = false
                // Generate new URL for retry
                onboardingRecordingURL = {
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    return documentsPath.appendingPathComponent("onboarding_\(UUID().uuidString).m4a")
                }()
                startRecording()
            }
        }
    }
    
    private func setupSpeechService() {
        speechService.onWordRecognized = { [self] recognizedText, wordIndices in
            Task { @MainActor in
                highlightedWordIndices = wordIndices
                // Update current word index to the maximum recognized index
                if let maxIndex = wordIndices.max() {
                    currentWordIndex = maxIndex
                }
            }
        }
    }
    
    private func startRecording() {
        Task {
            // Check permissions in sequence
            let micGranted = await audioService.requestMicrophonePermission()
            guard micGranted else {
                await MainActor.run {
                    errorMessage = "Microphone permission is required to record your affirmation."
                    showingError = true
                }
                return
            }
            
            let speechGranted = await speechService.requestSpeechRecognitionPermission()
            guard speechGranted else {
                await MainActor.run {
                    errorMessage = "Speech recognition permission is required to verify your recording."
                    showingError = true
                }
                return
            }
            
            // Start recording
            await MainActor.run {
                recordingState = .recording
                highlightedWordIndices.removeAll()
                currentWordIndex = -1  // Reset current word index
                hasGoodSimilarity = false
                capturedRecognitionText = ""
            }
            
            // Start recording in background
            do {
                try await audioService.startRecording(to: onboardingRecordingURL)
                
                // Start speech recognition
                try speechService.startRecognition(expectedText: dataModel.affirmationText)
                
                // Set up maximum recording timer (10 seconds) - same as PracticeView
                await MainActor.run {
                    maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                        print("⏰ [SpeakAndRecordView] Maximum recording time reached - stopping recording")
                        self.stopRecording()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start recording: \(error.localizedDescription)"
                    showingError = true
                    recordingState = .idle
                }
            }
        }
    }
    
    private func stopRecording() {
        recordingState = .analyzing
        
        // Cancel max recording timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Stop both audio recording and speech recognition
        audioService.stopRecording()
        speechService.stopRecognition()
        
        // Analyze the recording
        Task {
            // Use captured text for similarity check if available
            let finalSimilarity: Float
            if !capturedRecognitionText.isEmpty {
                finalSimilarity = speechService.calculateSimilarity(
                    expected: dataModel.affirmationText,
                    recognized: capturedRecognitionText
                )
            } else {
                // Fallback to word count ratio
                let recognizedWordCount = highlightedWordIndices.count
                let totalWords = dataModel.affirmationText.components(separatedBy: " ").count
                finalSimilarity = Float(recognizedWordCount) / Float(totalWords)
            }
            
            print("📊 [SpeakAndRecordView] Final similarity: \(finalSimilarity)")
            
            await MainActor.run {
                similarity = finalSimilarity
                // Add haptic feedback for completion
                if finalSimilarity >= 0.8 {
                    HapticManager.shared.trigger(.success)
                } else {
                    HapticManager.shared.trigger(.warning)
                }
            }
            
            // If successful, generate word timings while still in analyzing state
            if finalSimilarity >= 0.8 {
                await MainActor.run {
                    isGeneratingTimings = true
                }
                
                do {
                    print("🎯 [SpeakAndRecordView] Generating word timings...")
                    let timings = try await speechService.analyzeAudioFile(
                        at: onboardingRecordingURL,
                        expectedText: dataModel.affirmationText
                    )
                    
                    await MainActor.run {
                        wordTimings = timings
                        dataModel.wordTimings = timings
                        print("✅ [SpeakAndRecordView] Generated \(timings.count) word timings")
                        
                        // Mark recording as complete in data model for add affirmation flow
                        if flowType == .addAffirmation {
                            if let addData = dataModel as? AddAffirmationData {
                                addData.completeRecording()
                            }
                        }
                        
                        // Now all analysis is complete, switch to completed state
                        recordingState = .completed
                        isGeneratingTimings = false
                    }
                } catch {
                    print("⚠️ [SpeakAndRecordView] Failed to generate word timings: \(error)")
                    
                    await MainActor.run {
                        // Even if timing generation fails, allow user to continue
                        // Mark recording as complete in data model for add affirmation flow
                        if flowType == .addAffirmation {
                            if let addData = dataModel as? AddAffirmationData {
                                addData.completeRecording()
                            }
                        }
                        
                        recordingState = .completed
                        isGeneratingTimings = false
                    }
                }
            } else {
                // Failed similarity check - go directly to completed state
                await MainActor.run {
                    recordingState = .completed
                    
                    // Clean up failed recording
                    try? FileManager.default.removeItem(at: onboardingRecordingURL)
                    // Generate new URL for next attempt
                    onboardingRecordingURL = {
                        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        return documentsPath.appendingPathComponent("onboarding_\(UUID().uuidString).m4a")
                    }()
                }
            }
        }
    }
    
    private func monitorSilenceForSmartStop() {
        // Set up silence detection callback for smart stop (same as PracticeView)
        speechService.onSilenceDetected = { isSilent in
            if isSilent && self.hasGoodSimilarity && self.recordingState == .recording {
                print("🤫 [SpeakAndRecordView] Silence detected with good similarity - stopping recording")
                self.stopRecording()
            }
        }
    }
    
}

#Preview("Onboarding") {
    let data = OnboardingData()
    data.currentStep = 3
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
    return SpeakAndRecordView(
        dataModel: data,
        flowType: .onboarding,
        showingAddAffirmation: .constant(false)
    )


}

#Preview("Add Affirmation") {
    let data = AddAffirmationData()
    data.currentStep = 3
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
    return SpeakAndRecordView(
        dataModel: data,
        flowType: .addAffirmation,
        showingAddAffirmation: .constant(true)
    )
}

