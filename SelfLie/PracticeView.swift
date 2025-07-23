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
    @State private var silentRecordingDetected = false
    
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
            
            if practiceState == .completed {
                actionButtons
            }
            
            Spacer()
            
            if practiceState != .completed {
                cantSpeakButton
            }
        }
        .padding()
        .foregroundColor(.white)
        .onAppear {
            Task {
                await startPracticeFlow()
            }
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
            
            if practiceState == .completed && !silentRecordingDetected && similarity > 0 {
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
                VStack(spacing: 4) {
                    Text("Listen carefully")
                        .font(.headline)
                    Text("Pay attention to your voice")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            case .recording:
                VStack(spacing: 4) {
                    Text("Now speak aloud")
                        .font(.headline)
                    Text("Repeat the affirmation clearly")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            case .analyzing:
                Text("Verifying your speech...")
            case .completed:
                if silentRecordingDetected {
                    VStack(spacing: 4) {
                        Text("No voice detected")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("Please speak clearly during recording")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    Text(similarity >= 0.8 ? "Excellent! You did great!" : "Keep practicing, you can do better!")
                }
            }
        }
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
    
    private var actionButtons: some View {
        VStack(spacing: 16) {
            if silentRecordingDetected {
                Button("Try Speaking Again") {
                    Task {
                        await restartPractice()
                    }
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .cornerRadius(12)
                
                Button("Done for Now") {
                    cleanup()
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.vertical, 8)
            } else if similarity >= 0.8 {
                Button("I'm Great! 🎉") {
                    cleanup()
                    dismiss()
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(12)
            } else {
                Button("Try Again") {
                    Task {
                        await restartPractice()
                    }
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
                
                Button("Done for Now") {
                    cleanup()
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }
    
    private func startPracticeFlow() async {
        print("🎯 [PracticeView] Starting practice flow for affirmation: '\(affirmation.text)'")
        
        #if targetEnvironment(simulator)
        print("📱 [PracticeView] Running in simulator mode - skipping actual audio/recording")
        // Simplified simulator flow: just increment count
        await MainActor.run {
            practiceState = .completed
            similarity = 0.8
            incrementCount()
        }
        #else
        print("📱 [PracticeView] Running on real device - requesting permissions")
        // Real device flow with full audio playback and recording
        // Request permissions first
        let microphoneGranted = await audioService.requestMicrophonePermission()
        let speechGranted = await speechService.requestSpeechRecognitionPermission()
        
        print("🔐 [PracticeView] Permissions - Microphone: \(microphoneGranted), Speech: \(speechGranted)")
        
        guard microphoneGranted && speechGranted else {
            print("❌ [PracticeView] Permission denied - cannot proceed with practice")
            showError("Permissions required for practice session")
            return
        }
        
        // Start the automatic flow
        print("▶️ [PracticeView] Permissions granted - starting audio playback")
        await playAffirmation()
        #endif
    }
    
    private func playAffirmation() async {
        print("🔊 [PracticeView] Starting audio playback stage")
        await MainActor.run {
            practiceState = .playing
            silentRecordingDetected = false
        }
        
        guard let audioURL = affirmation.audioURL else {
            print("❌ [PracticeView] Audio URL not found for affirmation")
            showError("Audio file not found")
            return
        }
        
        // Check if file actually exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ [PracticeView] Audio file missing at path: \(audioURL.path)")
            showError("Audio file missing at: \(audioURL.path)")
            return
        }
        
        print("🎵 [PracticeView] Playing audio from: \(audioURL.path)")
        
        do {
            try await audioService.playAudio(from: audioURL)
            print("✅ [PracticeView] Audio playback completed successfully")
            
            // Brief pause before starting recording
            print("⏳ [PracticeView] Waiting 0.5 seconds before starting recording")
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await startRecording()
            
        } catch {
            print("❌ [PracticeView] Audio playback failed: \(error.localizedDescription)")
            await MainActor.run {
                showError("Failed to play audio: \(error.localizedDescription)")
            }
        }
    }
    
    private func startRecording() async {
        print("🎤 [PracticeView] Starting recording stage")
        await MainActor.run {
            practiceState = .recording
        }
        
        do {
            // Start recording audio
            print("📹 [PracticeView] Starting audio recording to: \(practiceURL.path)")
            try await audioService.startRecording(to: practiceURL)
            
            // Start real-time speech recognition simultaneously
            print("🗣️ [PracticeView] Starting speech recognition for text: '\(affirmation.text)'")
            try speechService.startRecognition(expectedText: affirmation.text)
            
            // Auto-stop after 10 seconds or when user stops speaking
            print("⏱️ [PracticeView] Recording will auto-stop after 10 seconds")
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds max
            
            if audioService.isRecording {
                print("🛑 [PracticeView] Stopping recording after 10 seconds timeout")
                audioService.stopRecording()
                speechService.stopRecognition()
                await analyzeRecording()
            } else {
                print("ℹ️ [PracticeView] Recording was already stopped")
            }
            
        } catch {
            print("❌ [PracticeView] Failed to start recording: \(error.localizedDescription)")
            await MainActor.run {
                showError("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }
    
    private func analyzeRecording() async {
        print("🔍 [PracticeView] Starting speech analysis stage")
        await MainActor.run {
            practiceState = .analyzing
        }
        
        // Use the real-time recognized text
        let recognizedText = speechService.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🎯 [PracticeView] Expected text: '\(affirmation.text)'")
        print("✅ [PracticeView] Recognized text: '\(recognizedText)'")
        
        if recognizedText.isEmpty {
            print("🔇 [PracticeView] No speech detected during recording")
            await MainActor.run {
                silentRecordingDetected = true
                practiceState = .completed
            }
            return
        }
        
        // Calculate similarity using embedding-based comparison
        print("📊 [PracticeView] Calculating similarity between expected and recognized text")
        similarity = speechService.calculateSimilarity(expected: affirmation.text, recognized: recognizedText)
        
        print("🔍 [PracticeView] Calculated similarity: \(similarity) (threshold: 0.8)")
        
        await MainActor.run {
            practiceState = .completed
            
            if similarity >= 0.8 {
                print("🎉 [PracticeView] Similarity above threshold - incrementing count")
                incrementCount()
            } else {
                print("📈 [PracticeView] Similarity below threshold - encouraging retry")
            }
        }
        
        print("✅ [PracticeView] Speech analysis completed")
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
    
    private func restartPractice() async {
        print("🔄 [PracticeView] Restarting practice session")
        cleanup()
        await MainActor.run {
            similarity = 0.0
            silentRecordingDetected = false
        }
        await startPracticeFlow()
    }
    
    private func cleanup() {
        print("🧹 [PracticeView] Cleaning up audio services and temp files")
        audioService.stopRecording()
        audioService.stopPlayback()
        speechService.stopRecognition()
        
        // Clean up temporary recording file
        if FileManager.default.fileExists(atPath: practiceURL.path) {
            do {
                try FileManager.default.removeItem(at: practiceURL)
                print("🗑️ [PracticeView] Cleaned up temporary recording file: \(practiceURL.path)")
            } catch {
                print("⚠️ [PracticeView] Failed to clean up temp file: \(error.localizedDescription)")
            }
        }
    }
}

enum PracticeState {
    case initial
    case playing
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
