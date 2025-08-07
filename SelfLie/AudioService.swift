import AVFoundation
import Foundation

@Observable
class AudioService: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var preparedRecorder: AVAudioRecorder?
    private var preWarmedTimer: Timer?
    
    var isRecording = false
    var isPlaying = false
    var recordingDuration: TimeInterval = 0
    
    private var recordingTimer: Timer?
    private var playbackProgressTimer: Timer?
    
    // 播放完成检测优化：使用Continuation替代轮询
    private var playbackCompletionContinuation: CheckedContinuation<Void, Error>?
    
    // Playback progress callbacks
    var onPlaybackProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onPlaybackComplete: (() -> Void)?
    
    override init() {
        super.init()
        // Audio session is now managed by AudioSessionManager
    }
    
    deinit {
        recordingTimer?.invalidate()
        preWarmedTimer?.invalidate()
        playbackProgressTimer?.invalidate()
        cleanupPreparedRecording()
        
        // 清理播放完成continuation
        playbackCompletionContinuation?.resume(throwing: CancellationError())
        playbackCompletionContinuation = nil
    }
    
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func prepareRecording(to url: URL) async throws {
        guard preparedRecorder == nil else { return }
        
        print("⏰ [AudioService] 🔧 prepareRecording() started")
        let prepareStartTime = Date()
        
        // Ensure directory exists
        let directoryStartTime = Date()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let directoryDuration = Date().timeIntervalSince(directoryStartTime) * 1000
        print("⏰ [AudioService] 📁 Directory creation in \(String(format: "%.0fms", directoryDuration))")
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            // Create recorder
            let recorderCreateStartTime = Date()
            preparedRecorder = try AVAudioRecorder(url: url, settings: settings)
            preparedRecorder?.delegate = self
            let recorderCreateDuration = Date().timeIntervalSince(recorderCreateStartTime) * 1000
            print("⏰ [AudioService] 🎙️ AVAudioRecorder created in \(String(format: "%.0fms", recorderCreateDuration))")
            
            // Aggressively prepare recorder
            let prepareToRecordStartTime = Date()
            preparedRecorder?.prepareToRecord()
            let prepareToRecordDuration = Date().timeIntervalSince(prepareToRecordStartTime) * 1000
            print("⏰ [AudioService] ⚡ prepareToRecord() completed in \(String(format: "%.0fms", prepareToRecordDuration))")
            
            // Pre-warm the timer to eliminate timer creation delay later
            let timerWarmupStartTime = Date()
            preWarmedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                // This timer will be transferred to recordingTimer when recording starts
                // For now, it does nothing but stays warm
            }
            // Immediately invalidate and keep it ready for transfer
            preWarmedTimer?.invalidate()
            preWarmedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }
            // Keep it paused until we need it
            preWarmedTimer?.invalidate()
            preWarmedTimer = nil // Will recreate when needed
            let timerWarmupDuration = Date().timeIntervalSince(timerWarmupStartTime) * 1000
            print("⏰ [AudioService] ⏱️ Timer warmup completed in \(String(format: "%.0fms", timerWarmupDuration))")
            
            let totalPrepareDuration = Date().timeIntervalSince(prepareStartTime) * 1000
            print("⏰ [AudioService] ✅ prepareRecording() completed in \(String(format: "%.0fms", totalPrepareDuration))")
        } catch {
            preparedRecorder = nil
            print("⏰ [AudioService] ❌ prepareRecording() failed: \(error.localizedDescription)")
            throw AudioServiceError.recordingFailed
        }
    }
    
    func startPreparedRecording() async throws {
        print("⏰ [AudioService] 🚀 startPreparedRecording() entered")
        let startTime = Date()
        
        guard !isRecording else { 
            print("⏰ [AudioService] ⚠️ Already recording, returning")
            return 
        }
        guard let preparedRecorder = preparedRecorder else {
            print("⏰ [AudioService] ❌ No prepared recorder available")
            throw AudioServiceError.recordingFailed
        }
        
        // Ultra-fast recording start: minimize operations
        let recordStartTime = Date()
        
        // Atomic state update and recorder transfer
        isRecording = true
        recordingDuration = 0
        audioRecorder = preparedRecorder
        self.preparedRecorder = nil
        
        // Start recording immediately - this should be instantaneous since recorder is fully prepared
        audioRecorder?.record()
        
        let recordDuration = Date().timeIntervalSince(recordStartTime) * 1000
        print("⏰ [AudioService] ⚡ Ultra-fast record() completed in \(String(format: "%.0fms", recordDuration))")
        
        // Use pre-warmed timer if available, otherwise create new one
        if let existingTimer = preWarmedTimer {
            print("⏰ [AudioService] 🔥 Using pre-warmed timer")
            recordingTimer = existingTimer
            preWarmedTimer = nil
        } else {
            let timerStartTime = Date()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }
            let timerDuration = Date().timeIntervalSince(timerStartTime) * 1000
            print("⏰ [AudioService] ⏱️ New timer created in \(String(format: "%.0fms", timerDuration))")
        }
        
        let totalDuration = Date().timeIntervalSince(startTime) * 1000
        print("⏰ [AudioService] ✅ startPreparedRecording() completed in \(String(format: "%.0fms", totalDuration))")
    }
    
    func startRecording(to url: URL) async throws {
        guard !isRecording else { return }
        
        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            isRecording = true
            recordingDuration = 0
            
            // Start timer for duration tracking
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }
        } catch {
            throw AudioServiceError.recordingFailed
        }
    }
    
    func cleanupPreparedRecording() {
        preparedRecorder = nil
        preWarmedTimer?.invalidate()
        preWarmedTimer = nil
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func playAudio(from url: URL) async throws {
        print("⏰ [AudioService] 🎵 playAudio() method entered")
        guard !isPlaying else { 
            print("⏰ [AudioService] ⚠️ Already playing, returning early")
            return 
        }
        
        // CRITICAL FIX: Setup audio session for playback before creating AVAudioPlayer
        print("⏰ [AudioService] 🔧 Setting up audio session for playback")
        try await AudioSessionManager.shared.setupForPlayAndRecord()
        
        do {
            print("⏰ [AudioService] 🔧 Creating AVAudioPlayer")
            let playerCreateStartTime = Date()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            let playerCreateDuration = Date().timeIntervalSince(playerCreateStartTime) * 1000
            print("⏰ [AudioService] ✅ AVAudioPlayer created and prepared in \(String(format: "%.0fms", playerCreateDuration))")
            
            isPlaying = true
            
            // Start progress tracking timer
            startPlaybackProgressTracking()
            
            print("⏰ [AudioService] ▶️ Calling audioPlayer.play()")
            let playStartTime = Date()
            audioPlayer?.play()
            let playCallDuration = Date().timeIntervalSince(playStartTime) * 1000
            print("⏰ [AudioService] ✅ audioPlayer.play() call completed in \(String(format: "%.0fms", playCallDuration))")
            
            // 优化：使用Continuation等待播放完成，替代轮询
            print("⏰ [AudioService] ⏳ Waiting for playback completion via delegate callback")
            let waitStartTime = Date()
            
            // 使用continuation等待AVAudioPlayerDelegate回调
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // 确保没有之前的continuation残留
                if let oldContinuation = playbackCompletionContinuation {
                    oldContinuation.resume(throwing: CancellationError())
                }
                playbackCompletionContinuation = continuation
                
                // 立即检查是否已经播放完成（防止竞态条件）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    if self.audioPlayer?.isPlaying == false {
                        // 已经完成播放，立即触发
                        if let cont = self.playbackCompletionContinuation {
                            self.playbackCompletionContinuation = nil
                            cont.resume()
                        }
                    }
                }
            }
            
            let totalWaitDuration = Date().timeIntervalSince(waitStartTime) * 1000
            print("⏰ [AudioService] ✅ Playback completed via delegate callback after \(String(format: "%.0fms", totalWaitDuration))")
            
            // Stop progress tracking
            stopPlaybackProgressTracking()
            
            // Notify completion
            onPlaybackComplete?()
            
            // Keep audio session active for subsequent recording operations
            print("⏰ [AudioService] 🎵 Playback completed, keeping audio session active for recording")
            
        } catch {
            print("⏰ [AudioService] ❌ playAudio() failed with error: \(error.localizedDescription)")
            isPlaying = false
            stopPlaybackProgressTracking()
            
            // 清理播放完成continuation
            if let continuation = playbackCompletionContinuation {
                playbackCompletionContinuation = nil
                continuation.resume(throwing: error)
            }
            
            // Keep audio session active even on failure, will be deactivated when PracticeView closes
            print("⏰ [AudioService] ⚠️ Playback failed, keeping audio session active for cleanup by caller")
            
            throw AudioServiceError.playbackFailed
        }
        
        print("⏰ [AudioService] 🎵 playAudio() method exiting")
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        stopPlaybackProgressTracking()
        
        // 清理播放完成continuation
        if let continuation = playbackCompletionContinuation {
            playbackCompletionContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }
    
    private func startPlaybackProgressTracking() {
        stopPlaybackProgressTracking() // Stop any existing timer
        
        print("🎵 [AudioService] Starting playback progress tracking")
        
        // Ensure timer runs on main queue for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self,
                      let player = self.audioPlayer else { 
                    print("🎵 [AudioService] ⚠️ Progress tracking callback: no player available")
                    return 
                }
                
                let currentTime = player.currentTime
                let duration = player.duration
                
                print("🎵 [AudioService] Progress: \(String(format: "%.2f", currentTime))/\(String(format: "%.2f", duration))s")
                
                if let callback = self.onPlaybackProgress {
                    callback(currentTime, duration)
                    print("🎵 [AudioService] ✅ Called onPlaybackProgress callback")
                } else {
                    print("🎵 [AudioService] ⚠️ No onPlaybackProgress callback set!")
                }
            }
            
            // Add timer to main run loop
            RunLoop.main.add(self.playbackProgressTimer!, forMode: .common)
        }
    }
    
    private func stopPlaybackProgressTracking() {
        DispatchQueue.main.async { [weak self] in
            self?.playbackProgressTimer?.invalidate()
            self?.playbackProgressTimer = nil
            print("🎵 [AudioService] Stopped playback progress tracking")
        }
    }
}

extension AudioService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("⏰ [AudioService] 🎵 AVAudioPlayerDelegate: playback finished successfully=\(flag)")
        isPlaying = false
        audioPlayer = nil
        
        // 立即通过continuation触发播放完成
        if let continuation = playbackCompletionContinuation {
            playbackCompletionContinuation = nil
            if flag {
                continuation.resume()
            } else {
                continuation.resume(throwing: AudioServiceError.playbackFailed)
            }
        }
    }
}

enum AudioServiceError: LocalizedError {
    case recordingFailed
    case playbackFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .recordingFailed:
            return "Failed to start recording"
        case .playbackFailed:
            return "Failed to play audio"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}

// MARK: - Audio Session Manager

@Observable
class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var isConfiguredForPlayAndRecord = false
    private var recordingWarmupRecorder: AVAudioRecorder?
    
    private init() {}
    
    // Issue 1 Fix: AirPods audio routing support
    func isBluetoothAudioDeviceConnected() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        let hasBluetoothOutput = route.outputs.contains { output in
            output.portType == .bluetoothA2DP || 
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE
        }
        
        let hasBluetoothInput = route.inputs.contains { input in
            input.portType == .bluetoothHFP ||
            input.portType == .bluetoothLE
        }
        
        let result = hasBluetoothOutput || hasBluetoothInput
        
        // Enhanced logging for debugging
        print("🎧 [AudioSessionManager] Bluetooth detection:")
        print("   Current route: \(route)")
        print("   Outputs: \(route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        print("   Inputs: \(route.inputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        print("   Has Bluetooth Output: \(hasBluetoothOutput)")
        print("   Has Bluetooth Input: \(hasBluetoothInput)")
        print("   Final Result: \(result)")
        
        return result
    }
    
    func getAudioSessionOptions(hasBluetoothDevice: Bool) -> AVAudioSession.CategoryOptions {
        if hasBluetoothDevice {
            // For AirPods and Bluetooth devices: allow Bluetooth A2DP, interrupt other audio apps
            return [.allowBluetoothA2DP]
        } else {
            // For phone speaker: default to speaker, interrupt other audio apps
            return [.defaultToSpeaker]
        }
    }
    
    func setupForPlayAndRecord() async throws {
        guard !isConfiguredForPlayAndRecord else { 
            // Even if already configured, check if we need to update routing
            try await updateAudioRouting()
            return 
        }
        
        print("⏰ [AudioSessionManager] 🔧 Setting up audio session for play and record")
        let setupStartTime = Date()
        
        // Issue 1 Fix: Detect connected audio devices and choose appropriate routing
        let hasBluetoothDevice = isBluetoothAudioDeviceConnected()
        let options = getAudioSessionOptions(hasBluetoothDevice: hasBluetoothDevice)
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: options)
            try audioSession.setActive(true)
            
            // Force audio routing to preferred output
            try await forceAudioRouting(hasBluetoothDevice: hasBluetoothDevice)
            
            isConfiguredForPlayAndRecord = true
            
            let setupDuration = Date().timeIntervalSince(setupStartTime) * 1000
            let deviceType = hasBluetoothDevice ? "Bluetooth (AirPods/Headphones)" : "Phone Speaker"
            print("⏰ [AudioSessionManager] ✅ Audio session configured for \(deviceType) in \(String(format: "%.0fms", setupDuration))")
        } catch {
            print("⏰ [AudioSessionManager] ❌ Failed to setup audio session: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func updateAudioRouting() async throws {
        let hasBluetoothDevice = isBluetoothAudioDeviceConnected()
        try await forceAudioRouting(hasBluetoothDevice: hasBluetoothDevice)
    }
    
    private func forceAudioRouting(hasBluetoothDevice: Bool) async throws {
        if hasBluetoothDevice {
            print("🎧 [AudioSessionManager] Forcing audio routing to Bluetooth device")
            
            // iOS 17+ AirPods Pro 2 routing fix: Multiple attempts with verification
            var routingSuccess = false
            let maxRetries = 3
            
            for attempt in 1...maxRetries {
                print("🎧 [AudioSessionManager] Routing attempt \(attempt)/\(maxRetries)")
                
                // Override the output port to preferred Bluetooth device
                do {
                    try audioSession.overrideOutputAudioPort(.none) // Clear any speaker override
                    print("🎧 [AudioSessionManager] ✅ Cleared speaker override (attempt \(attempt))")
                    
                    // Short delay to allow routing to settle
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    
                    // Verify the routing worked
                    let route = audioSession.currentRoute
                    let hasBluetoothOutput = route.outputs.contains { $0.portType == .bluetoothA2DP }
                    let currentOutputs = route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }
                    
                    print("🎧 [AudioSessionManager] Post-routing check (attempt \(attempt)) - Current outputs: \(currentOutputs)")
                    print("🎧 [AudioSessionManager] Bluetooth output active: \(hasBluetoothOutput)")
                    
                    if hasBluetoothOutput {
                        routingSuccess = true
                        print("🎧 [AudioSessionManager] ✅ Bluetooth routing successful on attempt \(attempt)")
                        break
                    } else if attempt < maxRetries {
                        print("🎧 [AudioSessionManager] ⚠️ Bluetooth routing failed on attempt \(attempt), retrying...")
                        // Force session reconfiguration for iOS 17+ AirPods Pro 2 fix
                        try audioSession.setActive(false)
                        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                        try audioSession.setActive(true)
                    }
                    
                } catch {
                    print("🎧 [AudioSessionManager] ⚠️ Failed to clear speaker override (attempt \(attempt)): \(error.localizedDescription)")
                    if attempt == maxRetries {
                        throw error
                    }
                }
            }
            
            if !routingSuccess {
                print("🎧 [AudioSessionManager] ⚠️ Failed to route to Bluetooth after \(maxRetries) attempts - iOS 17+ AirPods Pro 2 issue detected")
                // Log device info for debugging
                let route = audioSession.currentRoute
                print("🎧 [AudioSessionManager] Final route - Inputs: \(route.inputs.map { $0.portName }), Outputs: \(route.outputs.map { $0.portName })")
            }
            
        } else {
            print("📱 [AudioSessionManager] Forcing audio routing to speaker")
            try audioSession.overrideOutputAudioPort(.speaker)
        }
    }
    
    func preWarmRecording(to url: URL) async throws {
        print("⏰ [AudioSessionManager] 🔥 Pre-warming recording (optimized)")
        let warmupStartTime = Date()
        
        // Ensure audio session is properly configured
        let sessionSetupStartTime = Date()
        try await setupForPlayAndRecord()
        let sessionSetupDuration = Date().timeIntervalSince(sessionSetupStartTime) * 1000
        print("⏰ [AudioSessionManager] 🔊 Audio session setup in \(String(format: "%.0fms", sessionSetupDuration))")
        
        // Optimized warmup: skip actual file recording, just prepare the audio system
        let systemWarmupStartTime = Date()
        
        // Create minimal warmup without file I/O
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            // Use in-memory URL for super-fast warmup
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("warmup_\(UUID().uuidString).m4a")
            
            recordingWarmupRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            recordingWarmupRecorder?.prepareToRecord()
            
            // Micro-burst recording to warm up audio stack without file overhead
            recordingWarmupRecorder?.record()
            
            // Use Task.sleep for precise timing control
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms micro-burst
            
            recordingWarmupRecorder?.stop()
            recordingWarmupRecorder = nil
            
            // Clean up warmup file immediately
            try? FileManager.default.removeItem(at: tempURL)
            
            let systemWarmupDuration = Date().timeIntervalSince(systemWarmupStartTime) * 1000
            print("⏰ [AudioSessionManager] ⚡ Audio system warmed in \(String(format: "%.0fms", systemWarmupDuration))")
            
        } catch {
            let systemWarmupDuration = Date().timeIntervalSince(systemWarmupStartTime) * 1000
            print("⏰ [AudioSessionManager] ⚠️ Audio system warmup failed in \(String(format: "%.0fms", systemWarmupDuration)): \(error.localizedDescription)")
            // Don't throw - warmup failure shouldn't block the main flow
        }
        
        let totalWarmupDuration = Date().timeIntervalSince(warmupStartTime) * 1000
        print("⏰ [AudioSessionManager] ✅ Complete recording pre-warmup in \(String(format: "%.0fms", totalWarmupDuration))")
    }
    
    func resetAudioSession() async throws {
        print("⏰ [AudioSessionManager] 🔄 Resetting audio session")
        
        isConfiguredForPlayAndRecord = false
        recordingWarmupRecorder?.stop()
        recordingWarmupRecorder = nil
        
        try audioSession.setActive(false)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
        try await setupForPlayAndRecord()
        
        print("⏰ [AudioSessionManager] ✅ Audio session reset completed")
    }
    
    func deactivateSession() async throws {
        print("⏰ [AudioSessionManager] 🔄 Deactivating audio session and notifying other apps")
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        print("⏰ [AudioSessionManager] ✅ Audio session deactivated successfully")
    }
}