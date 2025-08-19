import SwiftUI
import AVFoundation

enum OnboardingRecordingState {
    case initial
    case recording
    case analyzing
    case success
    case failure
}

struct SpeakAndRecordView: View {
    @Bindable var onboardingData: OnboardingData
    
    @State private var recordingState: OnboardingRecordingState = .initial
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var similarity: Float = 0.0
    
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
        VStack(spacing: 20) {
            // Progress indicator
            OnboardingProgressBar(progress: onboardingData.progress)
                .padding(.top, 20)
            
            Spacer()
            
            // Title based on state
            Text(titleForState)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            if recordingState == .initial {
                // Description for initial state
                Text("Giving your goals a clear reason can helps you achieve them, as our brains are always looking for reasons.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Affirmation text with highlighting
            VStack {
                if recordingState == .recording || recordingState == .analyzing {
                    // Show "Speak now" hint
                    Text("Speak now")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.purple)
                        .cornerRadius(20)
                }
                
                // Affirmation text with word highlighting
                HighlightedAffirmationText(
                    text: onboardingData.affirmationText,
                    highlightedWordIndices: highlightedWordIndices
                )
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Action button based on state
            actionButtonForState
            
            Spacer()
        }
        .background(Color(hex: "#f9f9f9"))
        .fontDesign(.serif)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            setupSpeechService()
        }
    }
    
    private var titleForState: String {
        switch recordingState {
        case .initial:
            return "Great! Now say it aloud and record yourself 👍"
        case .recording:
            return "Recording..."
        case .analyzing:
            return "Analyzing..."
        case .success:
            return "👏 Well done! Let's listen and repeat it to motivate yourself."
        case .failure:
            return "Please try again, speaking louder and more clearly."
        }
    }
    
    @ViewBuilder
    private var actionButtonForState: some View {
        switch recordingState {
        case .initial:
            Button(action: startRecording) {
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.purple)
                    
                    Text("Tap to record")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
        case .recording:
            Button(action: stopRecording) {
                VStack(spacing: 8) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.purple)
                    
                    Text("Tap to stop record")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
        case .analyzing:
            VStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                    .scaleEffect(2.0)
            }
            
        case .success:
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)
                
                OnboardingContinueButton(
                    title: "Continue",
                    isEnabled: true
                ) {
                    // Save the recording URL and proceed
                    onboardingData.audioURL = onboardingRecordingURL
                    onboardingData.nextStep()
                }
                .padding(.horizontal, 20)
            }
            
        case .failure:
            VStack(spacing: 20) {
                Text("✕ Try again")
                    .font(.body)
                    .foregroundColor(.gray)
                
                Button(action: retryRecording) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Recording Logic (reused from PracticeView)
    
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
            let micGranted = await PermissionManager.requestMicrophonePermission()
            guard micGranted else {
                await MainActor.run {
                    errorMessage = "Microphone permission is required to record your affirmation."
                    showingError = true
                }
                return
            }
            
            let speechGranted = await PermissionManager.requestSpeechRecognitionPermission()
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
            }
            
            // Start recording in background
            do {
                try await audioService.startRecording(to: onboardingRecordingURL)
                
                // Start speech recognition
                try speechService.startRecognition(expectedText: onboardingData.affirmationText)
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start recording: \(error.localizedDescription)"
                    showingError = true
                    recordingState = .initial
                }
            }
        }
    }
    
    private func stopRecording() {
        recordingState = .analyzing
        
        audioService.stopRecording()
        speechService.stopRecognition()
        
        // Analyze the recording
        Task {
            await analyzeRecording()
        }
    }
    
    private func analyzeRecording() async {
        // Simulate analysis time
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        await MainActor.run {
            // Check if enough words were recognized (simple success criteria for now)
            let recognizedWordCount = highlightedWordIndices.count
            let totalWords = onboardingData.affirmationText.components(separatedBy: " ").count
            let recognitionRatio = Float(recognizedWordCount) / Float(totalWords)
            
            if recognitionRatio >= 0.7 { // 70% threshold
                recordingState = .success
            } else {
                recordingState = .failure
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
    
    private func retryRecording() {
        recordingState = .recording
        highlightedWordIndices.removeAll()
        
        // Start recording again
        Task {
            do {
                try await audioService.startRecording(to: onboardingRecordingURL)
                try speechService.startRecognition(expectedText: onboardingData.affirmationText)
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to retry recording: \(error.localizedDescription)"
                    showingError = true
                    recordingState = .failure
                }
            }
        }
    }
}

// MARK: - Highlighted Affirmation Text Component
struct HighlightedAffirmationText: View {
    let text: String
    let highlightedWordIndices: Set<Int>
    
    var body: some View {
        let words = text.components(separatedBy: " ")
        
        Text(buildAttributedString(words: words))
    }
    
    private func buildAttributedString(words: [String]) -> AttributedString {
        var result = AttributedString()
        
        for (index, word) in words.enumerated() {
            var attributedWord = AttributedString(word)
            
            if highlightedWordIndices.contains(index) {
                attributedWord.foregroundColor = .purple
            } else {
                attributedWord.foregroundColor = .primary
            }
            
            result.append(attributedWord)
            
            // Add space between words (except for the last word)
            if index < words.count - 1 {
                result.append(AttributedString(" "))
            }
        }
        
        return result
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