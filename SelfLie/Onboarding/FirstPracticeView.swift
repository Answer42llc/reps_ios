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
    @State private var similarity: Float = 0.0
    @State private var silentRecordingDetected = false
    
    // Word highlighting states (from PracticeView)
    @State internal var highlightedWordIndices: Set<Int> = []
    @State internal var currentWordIndex: Int = -1
    @State private var wordTimings: [WordTiming] = []
    @State private var audioDuration: TimeInterval = 0
    
    // Smart recording stop states (from PracticeView)
    @State private var hasGoodSimilarity = false
    @State private var capturedRecognitionText: String = ""
    @State private var maxRecordingTimer: Timer?
    @State private var recordingStartTime: Date?
    
    // Replay functionality
    @State private var isReplaying = false
    
    // Practice recording URL
    @State private var practiceRecordingURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("practice_\(UUID().uuidString).m4a")
    }()
    
    var body: some View {
        ZStack {
            // Background color (same as PracticeView)
            Color(red: 0.976, green: 0.976, blue: 0.976) // #f9f9f9
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Fixed height title area (similar to SpeakAndRecordView)
                VStack(alignment: .leading, spacing: 8) {
                    Text(titleForState)
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 88, maxHeight: 88, alignment: .top)
                }
                .padding(.horizontal, 16)
                
                // Main card container (similar to PracticeView)
                cardView
                    .padding(.top, 40)
                
                Spacer()
                
                // External action area (outside card)
                externalActionArea
                    .padding(.bottom, 40)
            }
            .padding(.top, 80)
            
            VStack{
                // Progress indicator at the top
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
            setupServiceCallbacks()
            initializeWordTimings()
            Task {
                await startPracticeFlow()
            }
        }
        .onChange(of: speechService.recognizedText) { _, newText in
            // Monitor for smart recording stop (from PracticeView)
            if practiceState == .recording && !newText.isEmpty {
                capturedRecognitionText = newText
                print("📝 [FirstPracticeView] Captured recognition text: '\(newText)'")
                
                let currentSimilarity = speechService.calculateSimilarity(
                    expected: onboardingData.affirmationText,
                    recognized: newText
                )
                
                // Use 70% threshold for onboarding (more lenient)
                if currentSimilarity >= 0.7 && !hasGoodSimilarity {
                    hasGoodSimilarity = true
                    print("🎯 [FirstPracticeView] Good similarity achieved: \(currentSimilarity)")
                    monitorSilenceForSmartStop()
                }
            }
        }
    }
    
    // MARK: - Card View (using PracticeView's structure)
    private var cardView: some View {
        VStack(spacing: 0) {
            cardContent
        }
        .background(Color.white)
        .cornerRadius(20)
        .padding(.horizontal)
    }
    
    private var cardContent: some View {
        VStack(spacing: 24) {
            // Status area
            statusArea
            
            // Content area
            contentArea
            
            // Action area (inside card) - for retry button
            if practiceState == .failure {
                cardActionArea
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var statusArea: some View {
        VStack(spacing: 8) {
            if practiceState == .playback || practiceState == .recording || practiceState == .analyzing {
                // Active states show status pill
                PracticeStatusPill(text: currentStatusText)
            } else if practiceState == .success {
                // Success state shows checkmark
                PracticeSuccessStatus()
            } else if practiceState == .failure {
                // Failure state shows Try Again
                PracticeFailureStatus()
            }
        }
    }
    
    private var contentArea: some View {
        VStack(spacing: 16) {
            // Main affirmation text with NativeTextHighlighter
            affirmationTextView
            
            // Replay button (shown in failure state)
            if practiceState == .failure {
                replayButton
            }
            
            // Hint text
            hintText
        }
    }
    
    private var affirmationTextView: some View {
        NativeTextHighlighter(
            text: onboardingData.affirmationText,
            highlightedWordIndices: highlightedWordIndices,
            currentWordIndex: currentWordIndex
        )
        .padding(.horizontal)
    }
    
    private var hintText: some View {
        Text(practiceState == .playback ? "Your brain believes your own words most." : "Even a lie repeated a thousand times becomes the truth")
            .fontDesign(.default)
            .font(.footnote)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
    }
    
    private var replayButton: some View {
        Button(action: {
            Task {
                await replayOriginalAudio()
            }
        }) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.title2)
                .foregroundColor(.purple)
        }
    }
    
    private var cardActionArea: some View {
        Button(action: {
            Task {
                await restartPractice()
            }
        }) {
            HStack {
                Image(systemName: "gobackward")
                Text("Restart")
                    .fontDesign(.default)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .foregroundStyle(.purple)
        .clipShape(Capsule())
    }
    
    @ViewBuilder
    private var externalActionArea: some View {
        if practiceState == .success {
            OnboardingContinueButton(
                title: "Continue",
                isEnabled: true
            ) {
                // Increment practice count and proceed
                onboardingData.practiceCount = 1
                onboardingData.nextStep()
            }
            .padding(.horizontal, 20)
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
    
    private var currentStatusText: String {
        switch practiceState {
        case .playback:
            return "Listen..."
        case .recording:
            return "Speak now..."
        case .analyzing:
            return "Processing..."
        default:
            return ""
        }
    }
    
    // MARK: - Practice Flow Logic (adapted from PracticeView)
    
    private func startPracticeFlow() async {
        print("🚀 [FirstPracticeView] Starting practice flow")
        
        // Reset states
        capturedRecognitionText = ""
        hasGoodSimilarity = false
        silentRecordingDetected = false
        
        // Request permissions
        let microphoneGranted = await audioService.requestMicrophonePermission()
        let speechGranted = await speechService.requestSpeechRecognitionPermission()
        
        guard microphoneGranted && speechGranted else {
            showError("Permissions required for practice session")
            return
        }
        
        // Set up audio session
        do {
            try await AudioSessionManager.shared.ensureSessionActive()
        } catch {
            showError("Failed to setup audio session")
            return
        }
        
        // Start with playback
        await playAffirmation()
    }
    
    private func playAffirmation() async {
        print("🔊 [FirstPracticeView] Starting audio playback")
        
        practiceState = .playback
        silentRecordingDetected = false
        
        // Reset highlighting for fresh playback
        highlightedWordIndices.removeAll()
        currentWordIndex = -1
        
        guard let audioURL = onboardingData.audioURL else {
            showError("Audio file not found")
            return
        }
        
        do {
            try await audioService.playAudio(from: audioURL)
            // After playback completes, start recording
            await startRecording()
        } catch {
            showError("Failed to play audio: \(error.localizedDescription)")
        }
    }
    
    private func startRecording() async {
        print("🎤 [FirstPracticeView] Starting recording")
        
        await MainActor.run {
            practiceState = .recording
            recordingStartTime = Date()
            hasGoodSimilarity = false
            
            // Reset text highlighting for recording
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
        }
        
        do {
            // Start recording
            try await audioService.startRecording(to: practiceRecordingURL)
            
            // Start speech recognition
            try speechService.startRecognition(expectedText: onboardingData.affirmationText)
            
            // Set up maximum recording timer (10 seconds)
            await MainActor.run {
                maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                    print("⏰ [FirstPracticeView] Maximum recording time reached")
                    Task {
                        await self.stopRecording()
                    }
                }
            }
        } catch {
            await MainActor.run {
                showError("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }
    
    private func stopRecording() async {
        guard practiceState == .recording else { return }
        
        print("🛑 [FirstPracticeView] Stopping recording")
        
        await MainActor.run {
            practiceState = .analyzing
        }
        
        // Clean up timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Stop services
        audioService.stopRecording()
        speechService.stopRecognition()
        
        await analyzeRecording()
    }
    
    private func analyzeRecording() async {
        print("🔍 [FirstPracticeView] Analyzing recording")
        
        let recognizedText = capturedRecognitionText.isEmpty ? 
            speechService.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines) :
            capturedRecognitionText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("Expected: '\(onboardingData.affirmationText)'")
        print("Recognized: '\(recognizedText)'")
        
        if recognizedText.isEmpty {
            await MainActor.run {
                silentRecordingDetected = true
                practiceState = .failure
            }
            return
        }
        
        // Calculate similarity
        similarity = speechService.calculateSimilarity(
            expected: onboardingData.affirmationText,
            recognized: recognizedText
        )
        
        print("Similarity: \(similarity)")
        
        await MainActor.run {
            if similarity >= 0.7 { // 70% threshold for onboarding
                practiceState = .success
            } else {
                practiceState = .failure
            }
        }
    }
    
    private func restartPractice() async {
        print("🔄 [FirstPracticeView] Restarting practice")
        
        // Cleanup
        audioService.stopRecording()
        audioService.stopPlayback()
        speechService.stopRecognition()
        
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Reset states
        await MainActor.run {
            similarity = 0.0
            silentRecordingDetected = false
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
            isReplaying = false
            
            speechService.recognizedText = ""
            speechService.recognizedWords.removeAll()
            
            capturedRecognitionText = ""
            hasGoodSimilarity = false
        }
        
        // Generate new recording URL
        practiceRecordingURL = {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsPath.appendingPathComponent("practice_\(UUID().uuidString).m4a")
        }()
        
        await startPracticeFlow()
    }
    
    private func replayOriginalAudio() async {
        print("🔄 [FirstPracticeView] Replaying original audio")
        
        guard let audioURL = onboardingData.audioURL else {
            showError("Audio file not found")
            return
        }
        
        await MainActor.run {
            isReplaying = true
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
        }
        
        do {
            try await audioService.playAudio(from: audioURL)
        } catch {
            await MainActor.run {
                showError("Failed to replay audio: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            isReplaying = false
        }
    }
    
    private func monitorSilenceForSmartStop() {
        speechService.onSilenceDetected = { isSilent in
            if isSilent && self.hasGoodSimilarity && self.practiceState == .recording {
                print("🤫 [FirstPracticeView] Silence detected with good similarity")
                Task {
                    await self.stopRecording()
                }
            }
        }
    }
    
    private func setupServiceCallbacks() {
        // Audio playback progress callback (from PracticeView)
        audioService.onPlaybackProgress = { currentTime, duration in
            DispatchQueue.main.async {
                self.audioDuration = duration
                
                // Apply time offset compensation
                let timeOffset: TimeInterval = 0.05
                let adjustedTime = currentTime + timeOffset
                
                // Update current word index based on playback progress
                let newWordIndex = NativeTextHighlighter.getWordIndexForTime(adjustedTime, wordTimings: self.wordTimings)
                
                if newWordIndex != self.currentWordIndex {
                    self.currentWordIndex = newWordIndex
                    self.updateHighlightingWithProgress(currentIndex: newWordIndex)
                }
            }
        }
        
        // Speech recognition callback
        speechService.onWordRecognized = { recognizedText, recognizedWordIndices in
            DispatchQueue.main.async {
                // Direct highlighting for recognized words
                self.highlightedWordIndices.formUnion(recognizedWordIndices)
                
                if let maxIndex = recognizedWordIndices.max() {
                    self.currentWordIndex = maxIndex
                }
            }
        }
        
        // Playback complete callback
        audioService.onPlaybackComplete = {
            DispatchQueue.main.async {
                // Ensure all words are highlighted when playback completes
                if !self.wordTimings.isEmpty {
                    self.highlightedWordIndices = Set(0..<self.wordTimings.count)
                    self.currentWordIndex = self.wordTimings.count - 1
                }
            }
        }
    }
    
    private func updateHighlightingWithProgress(currentIndex: Int) {
        if currentIndex >= 0 {
            // Highlight all words from 0 to currentIndex
            self.highlightedWordIndices = Set(0...currentIndex)
        } else {
            self.highlightedWordIndices.removeAll()
        }
    }
    
    private func initializeWordTimings() {
        // Use word timings from onboardingData if available
        wordTimings = onboardingData.wordTimings
        
        // Defensive check: if no timings exist, create fallback
        if wordTimings.isEmpty {
            print("⚠️ [FirstPracticeView] No word timings available from onboarding, creating fallback")
            createFallbackTimings()
        } else {
            print("✅ [FirstPracticeView] Using \(wordTimings.count) word timings from onboarding")
        }
    }
    
    private func createFallbackTimings() {
        let words = onboardingData.affirmationText.components(separatedBy: " ")
        let timePerWord: TimeInterval = 0.5
        
        wordTimings = words.enumerated().map { index, word in
            WordTiming(
                word: word,
                startTime: Double(index) * timePerWord,
                duration: timePerWord,
                confidence: 0.5
            )
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
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
