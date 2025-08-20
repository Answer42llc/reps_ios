import SwiftUI
import AVFoundation

struct SpeakAndRecordView: View {
    @Bindable var onboardingData: OnboardingData
    
    @State private var recordingState: RecordingState = .idle
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var similarity: Float = 0.0
    
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
                    
                    Text("Giving your goals a clear reason can helps you achieve them, as our brains are always looking for reasons.")
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
            
            VStack{
                // Progress indicator
                OnboardingProgressBar(progress: onboardingData.progress)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                Spacer()
            }

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
                    expected: onboardingData.affirmationText,
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
    }
    
    // MARK: - Card View (using common component from PracticeView)
    private var cardView: some View {
        PracticeCardView(
            statusContent: {
                statusArea
            },
            mainContent: {
                // Affirmation text
                HighlightedAffirmationText(
                    text: onboardingData.affirmationText,
                    highlightedWordIndices: highlightedWordIndices
                )
                .font(.title2)
                .multilineTextAlignment(.center)
            },
            actionContent: {
                PracticeCardActionButton(
                    title: "Retry",
                    systemImage: "gobackward",
                    action: toggleRecording
                )
            },
            showActionArea: recordingState == .completed && similarity < 0.8
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
    
    private var titleForState: String {
        switch recordingState {
        case .idle:
            return "Great! Now say it aloud and record yourself 👍"
        case .recording:
            return "Recording..."
        case .analyzing:
            if isGeneratingTimings {
                return "Preparing for practice..."
            } else {
                return "Analyzing..."
            }
        case .completed:
            if similarity >= 0.8 {
                return "👏 Well done! Let's listen and repeat it to motivate yourself."
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
                OnboardingContinueButton(
                    title: "Continue",
                    isEnabled: true
                ) {
                    // Save the recording URL and proceed
                    onboardingData.audioURL = onboardingRecordingURL
                    onboardingData.nextStep()
                }
                .padding(.horizontal, 20)
            } else {
                // Empty - retry button is in cardActionArea inside the card
                EmptyView()
            }
        }
    }
    
    // MARK: - Recording Logic (reused from PracticeView)
    
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
                similarity = 0.0
                capturedRecognitionText = ""
                highlightedWordIndices.removeAll()
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
                hasGoodSimilarity = false
                capturedRecognitionText = ""
            }
            
            // Start recording in background
            do {
                try await audioService.startRecording(to: onboardingRecordingURL)
                
                // Start speech recognition
                try speechService.startRecognition(expectedText: onboardingData.affirmationText)
                
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
                    expected: onboardingData.affirmationText,
                    recognized: capturedRecognitionText
                )
            } else {
                // Fallback to word count ratio
                let recognizedWordCount = highlightedWordIndices.count
                let totalWords = onboardingData.affirmationText.components(separatedBy: " ").count
                finalSimilarity = Float(recognizedWordCount) / Float(totalWords)
            }
            
            print("📊 [SpeakAndRecordView] Final similarity: \(finalSimilarity)")
            
            await MainActor.run {
                similarity = finalSimilarity
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
                        expectedText: onboardingData.affirmationText
                    )
                    
                    await MainActor.run {
                        onboardingData.wordTimings = timings
                        print("✅ [SpeakAndRecordView] Generated \(timings.count) word timings")
                        
                        // Now all analysis is complete, switch to completed state
                        recordingState = .completed
                        isGeneratingTimings = false
                    }
                } catch {
                    print("⚠️ [SpeakAndRecordView] Failed to generate word timings: \(error)")
                    
                    await MainActor.run {
                        // Even if timing generation fails, allow user to continue
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

#Preview {
    let data = OnboardingData()
    data.currentStep = 3
    data.goal = "quit smoke"
    data.reason = "smoke is smelly"
    data.generateAffirmation()
    return SpeakAndRecordView(onboardingData: data)
}

