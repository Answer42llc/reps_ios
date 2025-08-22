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
    
    private var recordingURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(recordingFileName)
    }
    
    var body: some View {
        VStack(spacing: 32) {
            headerView
            
            affirmationTextView
            
            recordingSection
            
            if recordingState == .recording {
                realTimeRecognitionView
            }
            
            if recordingState == .analyzing {
                analysisView
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Speak the lie to yourself")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    cleanup()
                    showingAddAffirmation = false
                }
            }
        }
        .onAppear {
            // Generate unique filename for this recording session
            recordingFileName = "\(UUID().uuidString).m4a"
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
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Record Your Affirmation")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Speak clearly and with conviction")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private var affirmationTextView: some View {
        Text(affirmationText)
            .font(.title3)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
    
    private var recordingSection: some View {
        VStack(spacing: 24) {
            recordingButton
            
            recordingStatusText
            
            if recordingState == .completed && similarity > 0 {
                similarityFeedback
            }
        }
    }
    
    private var recordingButton: some View {
        Button(action: toggleRecording) {
            Image(systemName: recordingState == .recording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(recordingButtonColor)
                .scaleEffect(recordingState == .recording ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: recordingState == .recording)
        }
        .disabled(recordingState == .analyzing || (recordingState == .completed && similarity >= 0.8))
        .sensoryFeedback(.impact, trigger: recordingState == .recording)
    }
    
    private var recordingButtonColor: Color {
        switch recordingState {
        case .idle: return .purple
        case .recording: return .red
        case .analyzing: return .gray
        case .completed: return similarity >= 0.8 ? .green : .orange
        }
    }
    
    private var recordingStatusText: some View {
        Group {
            switch recordingState {
            case .idle:
                Text("Tap to start recording")
            case .recording:
                Text("Recording... Tap to stop")
            case .analyzing:
                Text("Analyzing speech...")
            case .completed:
                Text(similarity >= 0.8 ? "Great! Recording saved" : "Tap mic to try again")
            }
        }
        .font(.headline)
        .foregroundColor(.secondary)
    }
    
    private var similarityFeedback: some View {
        VStack(spacing: 8) {
            Text("Accuracy: \(Int(similarity * 100))%")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(similarity >= 0.8 ? .green : .orange)
            
            if similarity >= 0.8 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Recording accepted!")
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Try speaking more clearly")
                }
            }
        }
        .padding()
        .background(similarity >= 0.8 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var realTimeRecognitionView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                Text("Listening...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            if !speechService.recognizedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recognized:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(speechService.recognizedText)
                        .font(.body)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    // Real-time similarity calculation
                    let currentSimilarity = speechService.calculateSimilarity(
                        expected: affirmationText, 
                        recognized: speechService.recognizedText
                    )
                    
                    HStack {
                        Text("Accuracy: \(Int(currentSimilarity * 100))%")
                            .font(.caption)
                            .foregroundColor(currentSimilarity >= 0.8 ? .green : .orange)
                        Spacer()
                        if currentSimilarity >= 0.8 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            if hasGoodSimilarity {
                                Text("🤫")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } else {
                Text("Start speaking...")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var analysisView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Processing your recording...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
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
            let recognizedText = speechService.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
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
            
            // Navigate back to dashboard after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showingAddAffirmation = false
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
    NavigationStack {
        RecordingView(affirmationText: "I never smoke, because smoking is smelly", showingAddAffirmation: .constant(true))
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}