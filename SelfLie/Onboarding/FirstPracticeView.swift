import SwiftUI
import AVFoundation

enum OnboardingPracticeState {
    case playback
    case recording
    case analyzing
    case success
    case failure
}

struct FirstPracticeView: View {
    @Bindable var onboardingData: OnboardingData
    
    @State private var practiceState: OnboardingPracticeState = .playback
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Word highlighting states (reused from PracticeView)
    @State internal var highlightedWordIndices: Set<Int> = []
    @State internal var currentWordIndex: Int = -1
    @State private var wordTimings: [WordTiming] = []
    
    // Practice recording URL
    @State private var practiceRecordingURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("practice_\(UUID().uuidString).m4a")
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
            
            Spacer()
            
            // Hint bubble for listening/speaking
            if practiceState == .playback || practiceState == .recording {
                Text(hintTextForState)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .cornerRadius(20)
            }
            
            // Affirmation text with highlighting
            HighlightedAffirmationText(
                text: onboardingData.affirmationText,
                highlightedWordIndices: highlightedWordIndices
            )
            .font(.title2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Action area based on state
            actionAreaForState
            
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
            setupPracticeSession()
        }
    }
    
    private var titleForState: String {
        switch practiceState {
        case .playback:
            return "Recording is playing..."
        case .recording:
            return "Recording..."
        case .analyzing:
            return "Analyzing..."
        case .success:
            return "🎉 Amazing! You just completed your first self motivation."
        case .failure:
            return "Please try again, speaking louder and more clearly."
        }
    }
    
    private var hintTextForState: String {
        switch practiceState {
        case .playback:
            return "Listen..."
        case .recording:
            return "Speak now"
        default:
            return ""
        }
    }
    
    @ViewBuilder
    private var actionAreaForState: some View {
        switch practiceState {
        case .playback:
            // Auto-playing, no interaction needed
            EmptyView()
            
        case .recording:
            // No explicit stop button - uses silence detection like PracticeView
            EmptyView()
            
        case .analyzing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                .scaleEffect(2.0)
            
        case .success:
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)
                
                OnboardingContinueButton(
                    title: "Continue",
                    isEnabled: true
                ) {
                    // Increment practice count and proceed to Step 5
                    onboardingData.practiceCount = 1
                    onboardingData.nextStep()
                }
                .padding(.horizontal, 20)
            }
            
        case .failure:
            VStack(spacing: 20) {
                Text("✕ Try again")
                    .font(.body)
                    .foregroundColor(.gray)
                
                HStack(spacing: 20) {
                    // Play original recording button
                    Button(action: playOriginalRecording) {
                        VStack(spacing: 8) {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.purple)
                            
                            Text("Listen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Restart practice button
                    Button(action: retryPractice) {
                        VStack(spacing: 8) {
                            Text("Restart")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.purple)
                                .cornerRadius(20)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Practice Logic
    
    private func setupPracticeSession() {
        // Setup speech service
        speechService.onWordRecognized = { [self] recognizedText, wordIndices in
            Task { @MainActor in
                highlightedWordIndices = wordIndices
            }
        }
        
        // Setup automatic transitions (similar to PracticeView)
        speechService.onSilenceDetected = { [self] isSilent in
            Task { @MainActor in
                if practiceState == .recording && isSilent {
                    stopRecording()
                }
            }
        }
        
        // Start by playing the original recording
        playOriginalRecording()
    }
    
    private func playOriginalRecording() {
        guard let audioURL = onboardingData.audioURL else { return }
        
        practiceState = .playback
        highlightedWordIndices = Set(0..<onboardingData.affirmationText.components(separatedBy: " ").count)
        
        Task {
            do {
                try await audioService.playAudio(from: audioURL)
                await MainActor.run {
                    startRecording()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to play recording. Please try again."
                    showingError = true
                }
            }
        }
    }
    
    private func startRecording() {
        practiceState = .recording
        highlightedWordIndices.removeAll()
        
        Task {
            do {
                // Start recording
                try await audioService.startRecording(to: practiceRecordingURL)
                
                // Start speech recognition
                try speechService.startRecognition(expectedText: onboardingData.affirmationText)
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start recording: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
    
    private func stopRecording() {
        practiceState = .analyzing
        
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
            // Check if enough words were recognized
            let recognizedWordCount = highlightedWordIndices.count
            let totalWords = onboardingData.affirmationText.components(separatedBy: " ").count
            let recognitionRatio = Float(recognizedWordCount) / Float(totalWords)
            
            if recognitionRatio >= 0.7 { // 70% threshold
                practiceState = .success
            } else {
                practiceState = .failure
                // Clean up failed recording
                try? FileManager.default.removeItem(at: practiceRecordingURL)
                // Generate new URL for next attempt
                practiceRecordingURL = {
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    return documentsPath.appendingPathComponent("practice_\(UUID().uuidString).m4a")
                }()
            }
        }
    }
    
    private func retryPractice() {
        // Restart the recording phase (not the entire practice cycle)
        startRecording()
    }
}

#Preview {
    let data = OnboardingData()
    data.currentStep = 4
    data.goal = "quit smoke"
    data.reason = "smoke is smelly"
    data.generateAffirmation()
    data.audioURL = URL(fileURLWithPath: "/tmp/test.m4a") // Mock URL
    return FirstPracticeView(onboardingData: data)
}