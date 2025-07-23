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
    
    // Smart recording stop
    @State private var maxRecordingTimer: Timer?
    @State private var recordingStartTime: Date?
    @State private var hasGoodSimilarity = false
    
    // Performance timing
    @State private var appearTime: Date?
    
    // 优化：预准备状态切换数据
    @State private var isPreparingForRecording = false
    
    private var practiceURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
    }
    
    // Helper function to calculate elapsed time with millisecond precision
    private func elapsedTime(from startTime: Date?) -> String {
        guard let startTime = startTime else { return "N/A" }
        let elapsed = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
        return String(format: "%.0fms", elapsed)
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
            appearTime = Date()
            print("⏰ [PracticeView] View appeared at \(elapsedTime(from: appearTime))")
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
        .onChange(of: speechService.recognizedText) { _, newText in
            // Monitor for smart recording stop
            if practiceState == .recording && !newText.isEmpty {
                let currentSimilarity = speechService.calculateSimilarity(
                    expected: affirmation.text, 
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
                        // Immediately reset state for better UX
                        await MainActor.run {
                            practiceState = .initial
                            similarity = 0.0
                            silentRecordingDetected = false
                        }
                        
                        cleanup()
                        // Pre-prepare a new recorder for direct recording
                        do {
                            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔧 Pre-preparing new recorder for Try Speaking Again")
                            let prepareStartTime = Date()
                            try await audioService.prepareRecording(to: practiceURL)
                            let prepareDuration = Date().timeIntervalSince(prepareStartTime) * 1000
                            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ New recorder prepared for direct recording in \(String(format: "%.0fms", prepareDuration))")
                        } catch {
                            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Failed to prepare new recorder: \(error.localizedDescription)")
                        }
                        await startRecording()
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
                        // Immediately reset state for better UX
                        await MainActor.run {
                            practiceState = .initial
                            similarity = 0.0
                            silentRecordingDetected = false
                        }
                        
                        cleanup()
                        // Pre-prepare a new recorder for direct recording
                        do {
                            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔧 Pre-preparing new recorder for Try Again")
                            let prepareStartTime = Date()
                            try await audioService.prepareRecording(to: practiceURL)
                            let prepareDuration = Date().timeIntervalSince(prepareStartTime) * 1000
                            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ New recorder prepared for direct recording in \(String(format: "%.0fms", prepareDuration))")
                        } catch {
                            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Failed to prepare new recorder: \(error.localizedDescription)")
                        }
                        await startRecording()
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
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Starting practice flow for affirmation: '\(affirmation.text)'")
        
        #if targetEnvironment(simulator)
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Running in simulator mode - skipping actual audio/recording")
        // Simplified simulator flow: just increment count
        await MainActor.run {
            practiceState = .completed
            similarity = 0.8
            incrementCount()
        }
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Simulator flow completed")
        #else
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Running on real device - requesting permissions")
        // Real device flow with full audio playback and recording
        // Request permissions first
        let permissionStartTime = Date()
        let microphoneGranted = await audioService.requestMicrophonePermission()
        let speechGranted = await speechService.requestSpeechRecognitionPermission()
        let permissionDuration = Date().timeIntervalSince(permissionStartTime) * 1000
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] Permissions completed in \(String(format: "%.0fms", permissionDuration)) - Microphone: \(microphoneGranted), Speech: \(speechGranted)")
        
        guard microphoneGranted && speechGranted else {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Permission denied - cannot proceed with practice")
            showError("Permissions required for practice session")
            return
        }
        
        // Set up audio session immediately after permissions
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔧 Setting up audio session")
        let audioSessionStartTime = Date()
        do {
            try await AudioSessionManager.shared.setupForPlayAndRecord()
            let audioSessionDuration = Date().timeIntervalSince(audioSessionStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Audio session ready in \(String(format: "%.0fms", audioSessionDuration))")
        } catch {
            let audioSessionDuration = Date().timeIntervalSince(audioSessionStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio session setup failed in \(String(format: "%.0fms", audioSessionDuration)): \(error.localizedDescription)")
            showError("Failed to setup audio session")
            return
        }
        
        // Parallel execution: Start audio playback + recording warmup simultaneously
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 Starting parallel audio playback + recording warmup")
        let parallelStartTime = Date()
        
        async let audioPlaybackTask: () = playAffirmation()
        async let recordingWarmupTask: () = performRecordingWarmup()
        
        let _ = await (audioPlaybackTask, recordingWarmupTask)
        
        let parallelDuration = Date().timeIntervalSince(parallelStartTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Parallel tasks completed in \(String(format: "%.0fms", parallelDuration))")
        #endif
    }
    
    private func performRecordingWarmup() async {
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔥 PRECISE: Starting optimized recording warmup")
        let warmupStartTime = Date()
        
        do {
            // 优化：并行执行录音器准备和音频会话预热
            let parallelWarmupStartTime = Date()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 PRECISE: Starting parallel warmup tasks")
            
            async let recorderPrepTask: Void = {
                let prepStartTime = Date()
                try await audioService.prepareRecording(to: practiceURL)
                let prepDuration = Date().timeIntervalSince(prepStartTime) * 1000
                await MainActor.run {
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Recorder preparation completed in \(String(format: "%.0fms", prepDuration))")
                }
            }()
            
            async let sessionWarmupTask: Void = {
                let warmupTaskStartTime = Date()
                try await AudioSessionManager.shared.preWarmRecording(to: practiceURL)
                let warmupTaskDuration = Date().timeIntervalSince(warmupTaskStartTime) * 1000
                await MainActor.run {
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Audio session warmup completed in \(String(format: "%.0fms", warmupTaskDuration))")
                }
            }()
            
            // 等待并行任务完成
            let _ = try await (recorderPrepTask, sessionWarmupTask)
            
            let parallelDuration = Date().timeIntervalSince(parallelWarmupStartTime) * 1000
            let totalWarmupDuration = Date().timeIntervalSince(warmupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Parallel warmup tasks completed in \(String(format: "%.0fms", parallelDuration))")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Total recording warmup completed in \(String(format: "%.0fms", totalWarmupDuration))")
        } catch {
            let warmupDuration = Date().timeIntervalSince(warmupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ PRECISE: Recording warmup failed in \(String(format: "%.0fms", warmupDuration)): \(error.localizedDescription)")
        }
    }
    
    private func playAffirmation() async {
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔊 PRECISE: Starting audio playback stage")
        
        // 优化：直接设置状态，避免MainActor调度延迟
        let stateUpdateStartTime = Date()
        practiceState = .playing
        silentRecordingDetected = false
        let stateUpdateDuration = Date().timeIntervalSince(stateUpdateStartTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚡ PRECISE: State update completed in \(String(format: "%.0fms", stateUpdateDuration))")
        
        guard let audioURL = affirmation.audioURL else {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio URL not found for affirmation")
            showError("Audio file not found")
            return
        }
        
        // Check if file actually exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio file missing at path: \(audioURL.path)")
            showError("Audio file missing at: \(audioURL.path)")
            return
        }
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎵 Playing audio from: \(audioURL.path)")
        
        let playbackStartTime = Date()
        do {
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📞 About to call audioService.playAudio()")
            try await audioService.playAudio(from: audioURL)
            let playbackDuration = Date().timeIntervalSince(playbackStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📞 audioService.playAudio() returned after \(String(format: "%.0fms", playbackDuration))")
            
            // 精确时间戳：准备调用startOptimizedRecording
            let preRecordingCallTime = Date()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: About to call startOptimizedRecording at [\(elapsedTime(from: appearTime))]")
            
            await startOptimizedRecording()
            
            let recordingCallDuration = Date().timeIntervalSince(preRecordingCallTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: startOptimizedRecording call completed in \(String(format: "%.0fms", recordingCallDuration))")
            
        } catch {
            let playbackDuration = Date().timeIntervalSince(playbackStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Audio playback failed in \(String(format: "%.0fms", playbackDuration)): \(error.localizedDescription)")
            await MainActor.run {
                showError("Failed to play audio: \(error.localizedDescription)")
            }
        }
    }
    
    private func startOptimizedRecording() async {
        let methodEntryTime = Date()
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 PRECISE: ENTERED startOptimizedRecording() at [\(elapsedTime(from: appearTime))]")
        
        // 精确测量MainActor调度延迟
        let preMainActorTime = Date()
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: About to call MainActor.run")
        
        await MainActor.run {
            let mainActorEntryTime = Date()
            let mainActorDelay = mainActorEntryTime.timeIntervalSince(preMainActorTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚡ PRECISE: MainActor.run entered after \(String(format: "%.0fms", mainActorDelay)) delay")
            
            practiceState = .recording
            recordingStartTime = Date()
            hasGoodSimilarity = false
            
            let mainActorExitTime = Date()
            let mainActorDuration = mainActorExitTime.timeIntervalSince(mainActorEntryTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚡ PRECISE: MainActor.run completed in \(String(format: "%.0fms", mainActorDuration))")
        }
        
        let postMainActorTime = Date()
        let totalMainActorOverhead = postMainActorTime.timeIntervalSince(preMainActorTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Total MainActor overhead: \(String(format: "%.0fms", totalMainActorOverhead))")
        
        let recordingSetupStartTime = Date()
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Recording setup phase started")
        
        do {
            // Since recording is pre-warmed, this should be much faster
            let recorderStartTime = Date()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🏃‍♂️ PRECISE: About to call audioService.startPreparedRecording()")
            
            try await audioService.startPreparedRecording()
            
            let recorderDuration = Date().timeIntervalSince(recorderStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Pre-warmed recorder started in \(String(format: "%.0fms", recorderDuration))")
            
            // Start real-time speech recognition with retry mechanism
            let speechStartTime = Date()
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🗣️ PRECISE: About to start speech recognition for text: '\(affirmation.text)'")
            
            do {
                try speechService.startRecognition(expectedText: affirmation.text)
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Speech recognition started in \(String(format: "%.0fms", speechDuration))")
            } catch {
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ PRECISE: Speech recognition failed in \(String(format: "%.0fms", speechDuration)), attempting retry with audio session reset...")
                
                // Try resetting audio session for Code 1101 recovery
                do {
                    try await AudioSessionManager.shared.resetAudioSession()
                    let retryStartTime = Date()
                    try speechService.startRecognition(expectedText: affirmation.text)
                    let retryDuration = Date().timeIntervalSince(retryStartTime) * 1000
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ PRECISE: Speech recognition retry succeeded in \(String(format: "%.0fms", retryDuration))")
                } catch {
                    let retryTotalDuration = Date().timeIntervalSince(speechStartTime) * 1000
                    print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ PRECISE: Speech recognition retry failed after \(String(format: "%.0fms", retryTotalDuration)): \(error.localizedDescription)")
                    throw error
                }
            }
            
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            let totalMethodDuration = Date().timeIntervalSince(methodEntryTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Recording setup completed in \(String(format: "%.0fms", setupDuration))")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Total startOptimizedRecording() duration: \(String(format: "%.0fms", totalMethodDuration))")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 PRECISE: Method overhead (total - setup): \(String(format: "%.0fms", totalMethodDuration - setupDuration))")
            
            // 优化：直接设置定时器，避免MainActor延迟
            maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                print("⏰ [PracticeView] [\(self.elapsedTime(from: self.appearTime))] ⏰ Maximum recording time reached - stopping recording")
                Task {
                    await self.stopRecording()
                }
            }
            
        } catch {
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            let totalMethodDuration = Date().timeIntervalSince(methodEntryTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ PRECISE: Failed to start optimized recording in \(String(format: "%.0fms", setupDuration)): \(error.localizedDescription)")
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ PRECISE: Total failed method duration: \(String(format: "%.0fms", totalMethodDuration))")
            // 优化：直接调用showError，避免MainActor延迟
            showError("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func startRecording() async {
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎤 ENTERED startRecording() method")
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎤 Starting recording stage")
        await MainActor.run {
            practiceState = .recording
            recordingStartTime = Date()
            hasGoodSimilarity = false
        }
        
        let recordingSetupStartTime = Date()
        do {
            // Try to use pre-prepared recorder first, fallback to regular recording
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🚀 Using pre-prepared recorder (prepared at app start)")
            let recorderStartTime = Date()
            do {
                try await audioService.startPreparedRecording()
                let recorderDuration = Date().timeIntervalSince(recorderStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Pre-prepared recorder started instantly in \(String(format: "%.0fms", recorderDuration))!")
            } catch {
                let recorderDuration = Date().timeIntervalSince(recorderStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Pre-prepared recorder unavailable in \(String(format: "%.0fms", recorderDuration)), falling back to regular recording")
                let fallbackStartTime = Date()
                try await audioService.startRecording(to: practiceURL)
                let fallbackDuration = Date().timeIntervalSince(fallbackStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Regular recording started successfully in \(String(format: "%.0fms", fallbackDuration))")
            }
            
            // Start real-time speech recognition with retry mechanism
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🗣️ Starting speech recognition for text: '\(affirmation.text)'")
            let speechStartTime = Date()
            do {
                try speechService.startRecognition(expectedText: affirmation.text)
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Speech recognition started in \(String(format: "%.0fms", speechDuration))")
            } catch {
                let speechDuration = Date().timeIntervalSince(speechStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ⚠️ Speech recognition failed in \(String(format: "%.0fms", speechDuration)), attempting retry...")
                // Brief delay before retry
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                let retryStartTime = Date()
                try speechService.startRecognition(expectedText: affirmation.text)
                let retryDuration = Date().timeIntervalSince(retryStartTime) * 1000
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Speech recognition retry succeeded in \(String(format: "%.0fms", retryDuration))")
            }
            
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 Recording setup completed in \(String(format: "%.0fms", setupDuration))")
            
            // Set up maximum recording timer (10 seconds)
            await MainActor.run {
                maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                    print("⏰ [PracticeView] [\(self.elapsedTime(from: self.appearTime))] ⏰ Maximum recording time reached - stopping recording")
                    Task {
                        await self.stopRecording()
                    }
                }
            }
            
        } catch {
            let setupDuration = Date().timeIntervalSince(recordingSetupStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ❌ Failed to start recording in \(String(format: "%.0fms", setupDuration)): \(error.localizedDescription)")
            await MainActor.run {
                showError("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }
    
    private func stopRecording() async {
        guard practiceState == .recording else { return }
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🛑 Stopping recording")
        await MainActor.run {
            practiceState = .analyzing
        }
        
        // Clean up smart recording timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Stop both audio recording and speech recognition
        let stopStartTime = Date()
        audioService.stopRecording()
        speechService.stopRecognition()
        let stopDuration = Date().timeIntervalSince(stopStartTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Recording services stopped in \(String(format: "%.0fms", stopDuration))")
        
        await analyzeRecording()
    }
    
    private func analyzeRecording() async {
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔍 Starting speech analysis stage")
        await MainActor.run {
            practiceState = .analyzing
        }
        
        let analysisStartTime = Date()
        
        // Use the real-time recognized text
        let recognizedText = speechService.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎯 Expected text: '\(affirmation.text)'")
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Recognized text: '\(recognizedText)'")
        
        if recognizedText.isEmpty {
            let analysisDuration = Date().timeIntervalSince(analysisStartTime) * 1000
            print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔇 No speech detected during recording (analyzed in \(String(format: "%.0fms", analysisDuration)))")
            await MainActor.run {
                silentRecordingDetected = true
                practiceState = .completed
            }
            return
        }
        
        // Calculate similarity using embedding-based comparison
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📊 Calculating similarity between expected and recognized text")
        let similarityStartTime = Date()
        similarity = speechService.calculateSimilarity(expected: affirmation.text, recognized: recognizedText)
        let similarityDuration = Date().timeIntervalSince(similarityStartTime) * 1000
        
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🔍 Calculated similarity: \(similarity) (threshold: 0.8) in \(String(format: "%.0fms", similarityDuration))")
        
        await MainActor.run {
            practiceState = .completed
            
            if similarity >= 0.8 {
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 🎉 Similarity above threshold - incrementing count")
                incrementCount()
            } else {
                print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] 📈 Similarity below threshold - encouraging retry")
            }
        }
        
        let totalAnalysisDuration = Date().timeIntervalSince(analysisStartTime) * 1000
        print("⏰ [PracticeView] [\(elapsedTime(from: appearTime))] ✅ Speech analysis completed in \(String(format: "%.0fms", totalAnalysisDuration))")
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
        audioService.cleanupPreparedRecording()
        speechService.stopRecognition()
        
        // Clean up timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
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
    
    private func monitorSilenceForSmartStop() {
        // Set up silence detection callback for smart stop
        speechService.onSilenceDetected = { isSilent in
            if isSilent && self.hasGoodSimilarity && self.practiceState == .recording {
                print("🤫 Silence detected with good similarity - stopping recording")
                Task {
                    await self.stopRecording()
                }
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
