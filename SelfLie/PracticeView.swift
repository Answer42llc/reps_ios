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
    
    // Word highlighting states
    @State internal var highlightedWordIndices: Set<Int> = []
    @State internal var currentWordIndex: Int = -1
    @State private var wordTimings: [WordTiming] = []
    @State private var audioDuration: TimeInterval = 0
    
    // Replay functionality
    @State private var isReplaying = false
    
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
        ZStack {
            // Background color
            Color(red: 0.976, green: 0.976, blue: 0.976) // #f9f9f9
                .ignoresSafeArea()
            
            // Top section with close button
            VStack{
                HStack {
                    Button(action: {
                        cleanup()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.black)
                    }
                    .padding(.leading, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                }
                Spacer()
            }

            VStack(spacing: 0) {
                // Main card container with fixed top positioning
                cardView
                    .padding(.top, 88) // Fixed top padding

                Spacer()
                
                // External action area (outside card)
                externalActionArea
                    .padding(.bottom, 40)
            }

        }
        .onAppear {
            appearTime = Date()
            print("⏰ [PracticeView] View appeared at \(elapsedTime(from: appearTime))")
            setupServiceCallbacks()
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
    
    
    private var affirmationTextView: some View {
        WordHighlighter(
            text: affirmation.text,
            highlightedWordIndices: highlightedWordIndices,
            currentWordIndex: currentWordIndex
        )
        .padding(.horizontal)
    }
    
    
    
    
    private var cardView: some View {
        VStack(spacing: 0) {
            // Card content will go here
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
            
            // Action area (inside card)
            if practiceState == .completed && (silentRecordingDetected || similarity < 0.8) {
                cardActionArea
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)

    }
    
    private var statusArea: some View {
        VStack(spacing: 8) {
            if practiceState != .completed {
                // Show status during active states
                Text(currentStatusText)
                .fontDesign(.default)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.purple)
                .cornerRadius(20)
            } else if !silentRecordingDetected && similarity >= 0.8 {
                // Success state shows checkmark
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .font(.headline)
                .fontDesign(.default)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.purple)
                .cornerRadius(20)
            }else{
                Label{
                    Text("Try Again")
                } icon: {
                    Image(systemName: "xmark")
                }
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)
                .fontDesign(.default)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            }
            // For failure states, no status indicator is shown (matches design)
        }
        .fontDesign(.default)
    }
    
    private var contentArea: some View {
        VStack(spacing: 16) {
            // Main affirmation text
            affirmationTextView
            // Replay button (shown after recording ends) with modified visibility
            replayButton
                .opacity(practiceState == .completed ? 1 : 0)
                .allowsHitTesting(practiceState == .completed)
            // Hint text
            hintText
            
        }
    }
    
    private var cardActionArea: some View {
        Button(action: {
            Task {
                await restartPractice()
            }
        }, label: {
            Image(systemName: "gobackward")
            Text("Restart")
                .fontDesign(.default)
        })
        .padding()
        .background(Color(.secondarySystemBackground))
        .foregroundStyle(.purple)
        .clipShape(Capsule())

    }
    
    private var externalActionArea: some View {
        VStack {
            if practiceState != .completed {
                Button(action: {
                    cleanup()
                    dismiss()
                }) {
                    Text("Can't speak now")
                        .fontDesign(.default)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                }
            } else if !silentRecordingDetected && similarity >= 0.8 {
                Button(action: {
                    cleanup()
                    dismiss()

                }) {
                    Text("Done")
                        .fontDesign(.default)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: 50)
                        .background(Color.purple)
                        .cornerRadius(25)
                        .padding(.horizontal, 20)

                }
            }
        }
    }
    
    private var currentStatusText: String {
        switch practiceState {
        case .initial, .playing:
            return "Listen..."
        case .recording:
            return "Speak now..."
        case .analyzing:
            return "Processing..."
        case .completed:
            return ""
        }
    }
    
    private var hintText: some View {
        Text(practiceState == .playing ? "Your brain believes your own words most." : "Even a lie repeated a thousand times becomes the truth")
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
        // Reset highlighting for fresh playback
        highlightedWordIndices.removeAll()
        currentWordIndex = -1
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
            
            // Issue 2 Fix: Reset text highlighting when starting recording
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
            print("🎯 [PracticeView] Reset text highlighting for recording phase")
            
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
            
            // Issue 2 Fix: Reset text highlighting when starting recording
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
            print("🎯 [PracticeView] Reset text highlighting for recording phase")
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
            // Reset text highlighting to original colors
            resetTextHighlighting()
            isReplaying = false
        }
        await startPracticeFlow()
    }
    
    private func resetTextHighlighting() {
        // Reset all text colors to original state unless it's a successful completion
        if silentRecordingDetected || similarity < 0.8 {
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
        }
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
        
        // Deactivate audio session and notify other apps to resume (Apple Music, etc.)
        print("🎵 [PracticeView] Deactivating audio session to restore other apps' audio")
        Task {
            do {
                try await AudioSessionManager.shared.deactivateSession()
                print("✅ [PracticeView] Audio session deactivated, other apps can resume playback")
            } catch {
                print("⚠️ [PracticeView] Failed to deactivate audio session: \(error.localizedDescription)")
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
    
    private func setupServiceCallbacks() {
        // Audio service playback progress callback
        audioService.onPlaybackProgress = { currentTime, duration in
            
            Task { @MainActor in
                self.audioDuration = duration
                
                // Initialize word timings if not already done
                self.initializeWordTimings()
                
                // Update current word index based on playback progress
                let newWordIndex = WordHighlighter.getWordIndexForTime(currentTime, wordTimings: self.wordTimings)
                
                if newWordIndex != self.currentWordIndex {
                    print("🎯 [PracticeView] Updating word index from \(self.currentWordIndex) to \(newWordIndex) at time \(String(format: "%.2f", currentTime))s")
                    self.currentWordIndex = newWordIndex
                    
                    // Update highlighted words to include all words up to current
                    if newWordIndex >= 0 {
                        self.highlightedWordIndices = Set(0...newWordIndex)
                        print("🎯 [PracticeView] Highlighted words: \(self.highlightedWordIndices)")
                    } else {
                        self.highlightedWordIndices.removeAll()
                    }
                }
            }
        }
        
        // Speech service word recognition callback
        speechService.onWordRecognized = { recognizedText, recognizedWordIndices in
            
            Task { @MainActor in
                self.highlightedWordIndices = recognizedWordIndices
                // Set current word index to the highest recognized word
                if let maxIndex = recognizedWordIndices.max() {
                    self.currentWordIndex = maxIndex
                }
            }
        }
    }
    
    private func replayOriginalAudio() async {
        print("🔄 [PracticeView] Replaying original audio")
        guard let audioURL = affirmation.audioURL else {
            showError("Audio file not found")
            return
        }
        
        // Reset highlighting state and ensure callbacks are set up
        await MainActor.run {
            isReplaying = true
            highlightedWordIndices.removeAll()
            currentWordIndex = -1
            // Ensure service callbacks are properly set up for replay
            setupServiceCallbacks()
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
            // Keep highlighting state after replay so user can see final state
            // Don't reset highlighting after replay - let user see the complete highlighted text
        }
    }
    
    /// Initialize word timings using precise data from the affirmation
    private func initializeWordTimings() {
        // Load precise word timings from the affirmation
        wordTimings = affirmation.wordTimings
        
        // Check if we need to regenerate timings for Chinese text
        let needsRegeneration = shouldRegenerateTimings()
        
        if needsRegeneration {
            print("🔄 [PracticeView] Chinese text detected with incorrect timings, regenerating...")
            Task {
                await regenerateWordTimings()
            }
            return
        }
        
        // Skip if we already have proper timings
        if !wordTimings.isEmpty {
            print("✅ [PracticeView] Loaded precise word timings: \(wordTimings.count) words")
            
            // Log timing details for debugging
            for (index, timing) in wordTimings.enumerated() {
                print("📍 Word \(index): '\(timing.word)' at \(String(format: "%.2f", timing.startTime))s-\(String(format: "%.2f", timing.endTime))s")
            }
            return
        }
        
        // If no timings exist, create basic fallback
        print("⚠️ [PracticeView] No word timings available, using fallback")
        createFallbackTimings()
    }
    
    private func shouldRegenerateTimings() -> Bool {
        // Check if it's Chinese text with only 1 timing (indicates old English-style processing)
        let isChinese = LanguageUtils.isChineseText(affirmation.text)
        let hasOnlyOneWord = wordTimings.count == 1
        let expectedCharCount = LanguageUtils.splitTextForLanguage(affirmation.text).count
        
        if isChinese && hasOnlyOneWord && expectedCharCount > 1 {
            print("🀄 [PracticeView] Chinese text '\(affirmation.text)' has only 1 timing but should have \(expectedCharCount) characters")
            return true
        }
        
        return false
    }
    
    private func regenerateWordTimings() async {
        guard let audioURL = affirmation.audioURL,
              FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ [PracticeView] Cannot regenerate: audio file not found")
            return
        }
        
        do {
            print("🎯 [PracticeView] Starting background regeneration of word timings")
            let speechService = SpeechService()
            let newWordTimings = try await speechService.analyzeAudioFile(at: audioURL, expectedText: affirmation.text)
            
            await MainActor.run {
                // Update both memory and persistent storage
                self.wordTimings = newWordTimings
                self.affirmation.wordTimings = newWordTimings
                
                // Save to Core Data
                do {
                    try PersistenceController.shared.container.viewContext.save()
                    print("✅ [PracticeView] Regenerated and saved \(newWordTimings.count) word timings")
                    
                    // Log new timing details
                    for (index, timing) in newWordTimings.enumerated() {
                        print("📍 New Word \(index): '\(timing.word)' at \(String(format: "%.2f", timing.startTime))s-\(String(format: "%.2f", timing.endTime))s")
                    }
                } catch {
                    print("❌ [PracticeView] Failed to save regenerated timings: \(error)")
                }
            }
        } catch {
            print("❌ [PracticeView] Failed to regenerate word timings: \(error)")
            await MainActor.run {
                createFallbackTimings()
            }
        }
    }
    
    private func createFallbackTimings() {
        // Create simple fallback timings based on text length
        let words = LanguageUtils.splitTextForLanguage(affirmation.text)
        let timePerWord: TimeInterval = audioDuration > 0 ? audioDuration / Double(words.count) : 0.5
        
        wordTimings = words.enumerated().map { index, word in
            WordTiming(
                word: word,
                startTime: Double(index) * timePerWord,
                duration: timePerWord,
                confidence: 0.5
            )
        }
        
        print("📊 [PracticeView] Created \(wordTimings.count) fallback timings")
    }
}

// MARK: - Testing Extensions
#if DEBUG
extension PracticeView {
    func simulateRecordingStart() {
        // Reset highlighting state for testing
        highlightedWordIndices.removeAll()
        currentWordIndex = -1
    }
}
#endif

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
    sampleAffirmation.text = "I never compare to others, because that make no sense"
    sampleAffirmation.audioFileName = "sample.m4a"
    sampleAffirmation.repeatCount = 84
    sampleAffirmation.targetCount = 1000
    sampleAffirmation.dateCreated = Date()
    
    return PracticeView(affirmation: sampleAffirmation)
        .environment(\.managedObjectContext, context)
}


