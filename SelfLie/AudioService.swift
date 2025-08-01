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
            
            // Wait for playback to complete
            print("⏰ [AudioService] ⏳ Entering while loop to wait for playback completion")
            let waitStartTime = Date()
            var loopCount = 0
            while audioPlayer?.isPlaying == true {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                loopCount += 1
                if loopCount % 10 == 0 { // Log every 1 second
                    let waitDuration = Date().timeIntervalSince(waitStartTime) * 1000
                    print("⏰ [AudioService] 🔄 Still playing after \(String(format: "%.0fms", waitDuration)) (loop: \(loopCount))")
                }
            }
            let totalWaitDuration = Date().timeIntervalSince(waitStartTime) * 1000
            print("⏰ [AudioService] ✅ Playback completed, exited while loop after \(String(format: "%.0fms", totalWaitDuration)) (\(loopCount) loops)")
            
            // Stop progress tracking
            stopPlaybackProgressTracking()
            
            // Notify completion
            onPlaybackComplete?()
            
        } catch {
            print("⏰ [AudioService] ❌ playAudio() failed with error: \(error.localizedDescription)")
            isPlaying = false
            stopPlaybackProgressTracking()
            throw AudioServiceError.playbackFailed
        }
        
        print("⏰ [AudioService] 🎵 playAudio() method exiting")
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        stopPlaybackProgressTracking()
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
        isPlaying = false
        audioPlayer = nil
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
            // For AirPods and Bluetooth devices: allow Bluetooth A2DP and mix with others
            return [.allowBluetoothA2DP, .mixWithOthers]
        } else {
            // For phone speaker: default to speaker with mix capability
            return [.defaultToSpeaker, .mixWithOthers]
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
            
            // Override the output port to preferred Bluetooth device
            do {
                try audioSession.overrideOutputAudioPort(.none) // Clear any speaker override
                print("🎧 [AudioSessionManager] ✅ Cleared speaker override, should route to Bluetooth")
            } catch {
                print("🎧 [AudioSessionManager] ⚠️ Failed to clear speaker override: \(error.localizedDescription)")
            }
            
            // Additional check: verify the routing worked
            let route = audioSession.currentRoute
            let hasBluetoothOutput = route.outputs.contains { $0.portType == .bluetoothA2DP }
            print("🎧 [AudioSessionManager] Post-routing check - Bluetooth output active: \(hasBluetoothOutput)")
            
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
}