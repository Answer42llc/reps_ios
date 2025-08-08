import AVFoundation
import Foundation

@Observable
class AudioService: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var preparedRecorder: AVAudioRecorder?
    private var preWarmedTimer: Timer?
    
    // Helper function to get hardware-compatible audio settings
    private func getAudioSettings() -> [String: Any] {
        let audioSession = AVAudioSession.sharedInstance()
        let hardwareSampleRate = audioSession.sampleRate
        
        print("🎙️ [AudioService] Using hardware sample rate: \(hardwareSampleRate) Hz")
        
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: hardwareSampleRate, // Use hardware sample rate
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }
    
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
        
        let settings = getAudioSettings()
        
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
        
        // Audio session is already configured for .playAndRecord in AudioSessionManager.init()
        // No need to switch - just ensure it's active
        try await AudioSessionManager.shared.ensureSessionActive()
        
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
        
        let settings = getAudioSettings()
        
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
        
        // Audio session is already configured for .playAndRecord in AudioSessionManager.init()
        // No need to switch - just ensure it's active
        try await AudioSessionManager.shared.ensureSessionActive()
        
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
                
                // 每秒只打印一次进度日志，减少噪音
                if Int(currentTime) != Int(currentTime - 0.1) {
                    print("🎵 [AudioService] Progress: \(String(format: "%.1f", currentTime))/\(String(format: "%.1f", duration))s")
                }
                
                if let callback = self.onPlaybackProgress {
                    callback(currentTime, duration)
                    // Note: Removed frequent callback success log to reduce noise
                }
                // Note: Removed missing callback warning as it may occur normally during replay
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
    private var recordingWarmupRecorder: AVAudioRecorder?
    private var initializationError: Error?
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            // 检测蓝牙设备连接状态，动态选择音频选项以避免冲突
            let hasBluetoothDevice = isBluetoothAudioDeviceConnected()
            let audioOptions: AVAudioSession.CategoryOptions = hasBluetoothDevice 
                ? [.allowBluetoothA2DP] // 蓝牙设备：仅允许A2DP高质量音频
                : [.defaultToSpeaker]   // 无蓝牙设备：默认使用扬声器
            
            try audioSession.setCategory(.playAndRecord, mode: .default, options: audioOptions)
            try audioSession.setActive(true)
            
            let deviceType = hasBluetoothDevice ? "Bluetooth A2DP" : "Phone Speaker"
            print("✅ [AudioSessionManager] Audio session initialized for \(deviceType)")
            initializationError = nil // 清除任何之前的错误
        } catch {
            initializationError = error
            print("❌ [AudioSessionManager] Failed to initialize audio session: \(error.localizedDescription)")
        }
    }
    
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
    
    /// Ensure the audio session is active (session is already configured in init)
    func ensureSessionActive() async throws {

        // 首先检查初始化是否成功
        if let initError = initializationError {
            print("❌ [AudioSessionManager] Cannot ensure session active due to initialization failure")
            throw initError
        }
        
        // 检查会话是否已经激活，避免重复操作
        if audioSession.isOtherAudioPlaying == false && audioSession.secondaryAudioShouldBeSilencedHint == false {
            // 会话可能已经激活，先检查状态
            do {
                // 只在需要时才重新激活
                try audioSession.setActive(true)
                print("✅ [AudioSessionManager] Audio session activated successfully")
            } catch {
                print("❌ [AudioSessionManager] Failed to activate audio session: \(error.localizedDescription)")
                throw error
            }
        } else {
            print("✅ [AudioSessionManager] Audio session already active")
        }
    }
    
    
    
    
    // forceAudioRouting方法已移除 - 系统会自动处理音频路由
    
    func preWarmRecording(to url: URL) async throws {
        print("⏰ [AudioSessionManager] 🔥 Pre-warming recording (optimized)")
        let warmupStartTime = Date()
        
        // Verify current audio session compatibility with recording
        let currentCategory = audioSession.category
        if currentCategory != .playAndRecord && currentCategory != .record {
            print("⏰ [AudioSessionManager] ⚠️ Current session (\(currentCategory)) may not support recording warmup")
            print("⏰ [AudioSessionManager] 📝 Warmup will proceed but may have limited effectiveness")
        }
        
        // Optimized warmup: skip actual file recording, just prepare the audio system
        // Note: No audio session change needed during warmup - keep current session
        let systemWarmupStartTime = Date()
        
        // Create minimal warmup without file I/O
        // Use hardware-compatible sample rate
        let audioSession = AVAudioSession.sharedInstance()
        let hardwareSampleRate = audioSession.sampleRate
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: hardwareSampleRate, // Use hardware sample rate
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        print("🎙️ [AudioSessionManager] Using hardware sample rate: \(hardwareSampleRate) Hz")
        
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
    
    enum AudioMode {
        case playback
        case recording
        case playAndRecord
    }
    
    func resetAudioSession(to mode: AudioMode = .playback) async throws {
        print("⏰ [AudioSessionManager] 🔄 Resetting audio session to \(mode)")
        
        recordingWarmupRecorder?.stop()
        recordingWarmupRecorder = nil
        
        try audioSession.setActive(false)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
        
        // 重新设置为.playAndRecord（与初始化相同）
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try audioSession.setActive(true)
            print("✅ [AudioSessionManager] Audio session reset to .playAndRecord")
        } catch {
            print("❌ [AudioSessionManager] Failed to reset audio session: \(error.localizedDescription)")
            throw error
        }
        
        print("⏰ [AudioSessionManager] ✅ Audio session reset to \(mode) completed")
    }
    
    func deactivateSession() async throws {
        print("⏰ [AudioSessionManager] 🔄 Deactivating audio session and notifying other apps")
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        print("⏰ [AudioSessionManager] ✅ Audio session deactivated successfully")
    }
}
