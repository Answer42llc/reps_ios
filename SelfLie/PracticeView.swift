import SwiftUI
import CoreData

struct PracticeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let affirmation: Affirmation
    
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    @State private var practiceState: PracticeState = .initial
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var similarity: Float = 0.0
    
    private var practiceURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
    }
    
    var body: some View {
        VStack(spacing: 32) {
            headerView
            
            affirmationTextView
            
            practiceSection
            
            if practiceState == .analyzing {
                analysisView
            }
            
            Spacer()
            
            cantSpeakButton
        }
        .padding()
        .foregroundColor(.white)
        .task {
            await startPracticeFlow()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Practice Session")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Progress: \(affirmation.progressText)")
                .font(.body)
                .foregroundColor(.gray)
        }
    }
    
    private var affirmationTextView: some View {
        Text(affirmation.text)
            .font(.title3)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
    }
    
    private var practiceSection: some View {
        VStack(spacing: 24) {
            practiceIcon
            practiceStatusText
            
            if practiceState == .completed && similarity > 0 {
                successFeedback
            }
        }
    }
    
    private var practiceIcon: some View {
        Group {
            switch practiceState {
            case .initial:
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)
            case .playing:
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .scaleEffect(1.1)
                    .animation(.easeInOut(duration: 1).repeatForever(), value: practiceState == .playing)
            case .promptingRecording:
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
            case .recording:
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .scaleEffect(1.2)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: practiceState == .recording)
            case .analyzing:
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
            case .completed:
                Image(systemName: similarity >= 0.8 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(similarity >= 0.8 ? .green : .red)
            }
        }
    }
    
    private var practiceStatusText: some View {
        Group {
            switch practiceState {
            case .initial:
                Text("Starting practice session...")
            case .playing:
                Text("Listen to your affirmation")
            case .promptingRecording:
                Text("Speak this words again")
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            case .recording:
                Text("Recording your voice...")
            case .analyzing:
                Text("Verifying your speech...")
            case .completed:
                Text(similarity >= 0.8 ? "Perfect! Count increased" : "Practice complete")
            }
        }
        .font(.headline)
        .multilineTextAlignment(.center)
    }
    
    private var successFeedback: some View {
        VStack(spacing: 8) {
            if similarity >= 0.8 {
                Text("🎉 Well done!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                
                Text("Your count increased to \(affirmation.repeatCount + 1)")
                    .font(.body)
                    .foregroundColor(.gray)
            } else {
                Text("Keep practicing!")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                Text("Accuracy: \(Int(similarity * 100))%")
                    .font(.body)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(similarity >= 0.8 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
        .cornerRadius(12)
    }
    
    private var analysisView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
        }
    }
    
    private var cantSpeakButton: some View {
        Button("Can't speak now") {
            cleanup()
            dismiss()
        }
        .font(.headline)
        .foregroundColor(.gray)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
    
    private func startPracticeFlow() async {
        #if targetEnvironment(simulator)
        // Simplified simulator flow: just increment count and dismiss
        await MainActor.run {
            practiceState = .completed
            similarity = 0.8
            incrementCount()
            
            // Auto-dismiss after showing success
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismiss()
            }
        }
        #else
        // Real device flow with full audio playback and recording
        // Request permissions first
        let microphoneGranted = await audioService.requestMicrophonePermission()
        let speechGranted = await speechService.requestSpeechRecognitionPermission()
        
        guard microphoneGranted && speechGranted else {
            showError("Permissions required for practice session")
            return
        }
        
        // Start the automatic flow
        await playAffirmation()
        #endif
    }
    
    private func playAffirmation() async {
        practiceState = .playing
        
        guard let audioURL = affirmation.audioURL else {
            showError("Audio file not found")
            return
        }
        
        // Check if file actually exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            showError("Audio file missing at: \(audioURL.path)")
            return
        }
        
        print("Attempting to play audio from: \(audioURL.path)")
        
        do {
            try await audioService.playAudio(from: audioURL)
            await MainActor.run {
                practiceState = .promptingRecording
            }
            
            // Brief pause before starting recording
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await startRecording()
            
        } catch {
            await MainActor.run {
                showError("Failed to play audio: \(error.localizedDescription)")
            }
        }
    }
    
    private func startRecording() async {
        practiceState = .recording
        
        do {
            // Start recording audio
            try await audioService.startRecording(to: practiceURL)
            
            // Start real-time speech recognition simultaneously
            try speechService.startRecognition(expectedText: affirmation.text)
            
            // Auto-stop after 10 seconds or when user stops speaking
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds max
            
            if audioService.isRecording {
                audioService.stopRecording()
                speechService.stopRecognition()
                await analyzeRecording()
            }
            
        } catch {
            await MainActor.run {
                showError("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }
    
    private func analyzeRecording() async {
        practiceState = .analyzing
        
        // Use the real-time recognized text
        let recognizedText = speechService.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🎯 Expected: '\(affirmation.text)'")
        print("✅ Recognized: '\(recognizedText)'")
        
        if recognizedText.isEmpty {
            await MainActor.run {
                showError("No speech was recognized. Please try speaking more clearly.")
            }
            return
        }
        
        // Calculate similarity using embedding-based comparison
        similarity = speechService.calculateSimilarity(expected: affirmation.text, recognized: recognizedText)
        
        print("🔍 Calculated similarity: \(similarity)")
        
        await MainActor.run {
            practiceState = .completed
            
            if similarity >= 0.8 {
                incrementCount()
            }
            
            // Auto-dismiss after showing result
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismiss()
            }
        }
    }
    
    private func incrementCount() {
        affirmation.repeatCount += 1
        
        do {
            try viewContext.save()
        } catch {
            showError("Failed to update progress: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func cleanup() {
        audioService.stopRecording()
        audioService.stopPlayback()
        speechService.stopRecognition()
        
        // Clean up temporary recording file
        try? FileManager.default.removeItem(at: practiceURL)
    }
}

enum PracticeState {
    case initial
    case playing
    case promptingRecording
    case recording
    case analyzing
    case completed
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let sampleAffirmation = Affirmation(context: context)
    sampleAffirmation.id = UUID()
    sampleAffirmation.text = "I never smoke, because smoking is smelly"
    sampleAffirmation.audioFileName = "sample.m4a"
    sampleAffirmation.repeatCount = 84
    sampleAffirmation.targetCount = 1000
    sampleAffirmation.dateCreated = Date()
    
    return PracticeView(affirmation: sampleAffirmation)
        .environment(\.managedObjectContext, context)
}
