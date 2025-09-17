import AVFoundation
import Foundation

// MARK: - Debug Configuration
private struct AudioDebugConfig {
    static let isDebugModeEnabled = false  // Set to true only for debugging
    static let enableDetailedTiming = false
    static let enableHardwarePropertyLogging = false
}

// MARK: - Debug Logging Functions
private func debugLog(_ message: String) {
    if AudioDebugConfig.isDebugModeEnabled {
        print(message)
    }
}

private func timingLog(_ message: String) {
    if AudioDebugConfig.enableDetailedTiming {
        print(message)
    }
}

private func hardwareLog(_ message: String) {
    if AudioDebugConfig.enableHardwarePropertyLogging {
        print(message)
    }
}

@Observable
class AudioService: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var preparedRecorder: AVAudioRecorder?
    private var preWarmedTimer: Timer?
    
    // Helper function to get hardware-compatible audio settings
    private func getAudioSettings() -> [String: Any] {
        let hardwareSampleRate = AudioSessionManager.shared.getCurrentSampleRate()
        
        hardwareLog("🎙️ [AudioService] Using hardware sample rate: \(hardwareSampleRate) Hz")
        
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
        setupPlaybackInterruptionHandler()
    }
    
    private func setupPlaybackInterruptionHandler() {
        AudioSessionManager.shared.playbackInterruptionHandler = { [weak self] reason in
            guard let self = self else { return }
            
            switch reason {
            case .oldDeviceUnavailable:
                // Switch audio route when device is disconnected - continue playback on speaker
                if self.isPlaying {
                    print("🎧 [AudioService] Audio device disconnected - switching to speaker")
                    self.restartPlaybackForDeviceChange()
                }
            default:
                break
            }
        }
        
        // 注册播放重启回调 - 当新设备连接时重新启动播放
        AudioSessionManager.shared.playbackRestartHandler = { [weak self] in
            guard let self = self else { return }
            self.restartPlaybackForDeviceChange()
        }
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
        
        timingLog("⏰ [AudioService] 🔧 prepareRecording() started")
        let prepareStartTime = Date()
        
        // Ensure directory exists
        let directoryStartTime = Date()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let directoryDuration = Date().timeIntervalSince(directoryStartTime) * 1000
        timingLog("⏰ [AudioService] 📁 Directory creation in \(String(format: "%.0fms", directoryDuration))")
        
        let settings = getAudioSettings()
        
        do {
            // Create recorder
            let recorderCreateStartTime = Date()
            preparedRecorder = try AVAudioRecorder(url: url, settings: settings)
            preparedRecorder?.delegate = self
            let recorderCreateDuration = Date().timeIntervalSince(recorderCreateStartTime) * 1000
            timingLog("⏰ [AudioService] 🎙️ AVAudioRecorder created in \(String(format: "%.0fms", recorderCreateDuration))")
            
            // Aggressively prepare recorder
            let prepareToRecordStartTime = Date()
            preparedRecorder?.prepareToRecord()
            let prepareToRecordDuration = Date().timeIntervalSince(prepareToRecordStartTime) * 1000
            timingLog("⏰ [AudioService] ⚡ prepareToRecord() completed in \(String(format: "%.0fms", prepareToRecordDuration))")
            
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
            timingLog("⏰ [AudioService] ⏱️ Timer warmup completed in \(String(format: "%.0fms", timerWarmupDuration))")
            
            let totalPrepareDuration = Date().timeIntervalSince(prepareStartTime) * 1000
            timingLog("⏰ [AudioService] ✅ prepareRecording() completed in \(String(format: "%.0fms", totalPrepareDuration))")
        } catch {
            preparedRecorder = nil
            debugLog("⏰ [AudioService] ❌ prepareRecording() failed: \(error.localizedDescription)")
            throw AudioServiceError.recordingFailed
        }
    }
    
    func startPreparedRecording() async throws {
        timingLog("⏰ [AudioService] 🚀 startPreparedRecording() entered")
        let startTime = Date()
        
        guard !isRecording else { 
            debugLog("⏰ [AudioService] ⚠️ Already recording, returning")
            return 
        }
        guard let preparedRecorder = preparedRecorder else {
            debugLog("⏰ [AudioService] ❌ No prepared recorder available")
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
        timingLog("⏰ [AudioService] ⚡ Ultra-fast record() completed in \(String(format: "%.0fms", recordDuration))")
        
        // Use pre-warmed timer if available, otherwise create new one
        if let existingTimer = preWarmedTimer {
            timingLog("⏰ [AudioService] 🔥 Using pre-warmed timer")
            recordingTimer = existingTimer
            preWarmedTimer = nil
        } else {
            let timerStartTime = Date()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }
            let timerDuration = Date().timeIntervalSince(timerStartTime) * 1000
            timingLog("⏰ [AudioService] ⏱️ New timer created in \(String(format: "%.0fms", timerDuration))")
        }
        
        let totalDuration = Date().timeIntervalSince(startTime) * 1000
        timingLog("⏰ [AudioService] ✅ startPreparedRecording() completed in \(String(format: "%.0fms", totalDuration))")
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
    
    func playAudio(from url: URL, volume: Float = 1.0) async throws {
        timingLog("⏰ [AudioService] 🎵 playAudio() method entered")
        guard !isPlaying else { 
            debugLog("⏰ [AudioService] ⚠️ Already playing, returning early")
            return 
        }
        
        // Audio session is already configured for .playAndRecord in AudioSessionManager.init()
        // No need to switch - just ensure it's active
        try await AudioSessionManager.shared.ensureSessionActive()
        
        do {
            timingLog("⏰ [AudioService] 🔧 Creating AVAudioPlayer")
            let playerCreateStartTime = Date()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            // 支持可选音量，用于隐私模式静音播放
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            let playerCreateDuration = Date().timeIntervalSince(playerCreateStartTime) * 1000
            timingLog("⏰ [AudioService] ✅ AVAudioPlayer created and prepared in \(String(format: "%.0fms", playerCreateDuration))")
            
            isPlaying = true
            
            // Start progress tracking timer
            startPlaybackProgressTracking()
            
            timingLog("⏰ [AudioService] ▶️ Calling audioPlayer.play()")
            let playStartTime = Date()
            audioPlayer?.play()
            let playCallDuration = Date().timeIntervalSince(playStartTime) * 1000
            timingLog("⏰ [AudioService] ✅ audioPlayer.play() call completed in \(String(format: "%.0fms", playCallDuration))")
            
            // 优化：使用Continuation等待播放完成，替代轮询
            timingLog("⏰ [AudioService] ⏳ Waiting for playback completion via delegate callback")
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
            timingLog("⏰ [AudioService] ✅ Playback completed via delegate callback after \(String(format: "%.0fms", totalWaitDuration))")
            
            // Stop progress tracking
            stopPlaybackProgressTracking()
            
            // Notify completion
            onPlaybackComplete?()
            
            // Keep audio session active for subsequent recording operations
            debugLog("⏰ [AudioService] 🎵 Playback completed, keeping audio session active for recording")
            
        } catch {
            let isCancellation = error is CancellationError
            if isCancellation {
                print("⏰ [AudioService] ⚠️ playAudio() cancelled: \(error.localizedDescription)")
            } else {
                print("⏰ [AudioService] ❌ playAudio() failed with error: \(error.localizedDescription)")
            }

            isPlaying = false
            stopPlaybackProgressTracking()

            if let continuation = playbackCompletionContinuation {
                playbackCompletionContinuation = nil
                continuation.resume(throwing: error)
            }

            if isCancellation {
                throw CancellationError()
            }

            // Keep audio session active even on failure, will be deactivated when PracticeView closes
            debugLog("⏰ [AudioService] ⚠️ Playback failed, keeping audio session active for cleanup by caller")

            if let audioError = error as? AudioServiceError {
                throw audioError
            }
            throw AudioServiceError.playbackFailed
        }

        timingLog("⏰ [AudioService] 🎵 playAudio() method exiting")
    }
    
    private func restartPlaybackForDeviceChange() {
        guard isPlaying else { return }
        
        Task { @MainActor in
            print("🎧 [AudioService] Restarting playback for audio device change")
            
            // 获取当前播放状态
            let currentTime = self.audioPlayer?.currentTime ?? 0
            let url = self.audioPlayer?.url
            
            if let audioURL = url {
                print("🎧 [AudioService] Recreating audio player for device routing")
                
                do {
                    // 直接停止当前播放器但不清理continuation
                    self.audioPlayer?.stop()
                    
                    // 重新创建播放器以使用新的音频路由
                    self.audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                    self.audioPlayer?.delegate = self
                    self.audioPlayer?.prepareToPlay()
                    self.audioPlayer?.currentTime = currentTime
                    self.audioPlayer?.play()
                    
                    print("🎧 [AudioService] Audio player recreated and resumed at \(String(format: "%.1f", currentTime))s")
                } catch {
                    print("🎧 [AudioService] Failed to recreate audio player: \(error.localizedDescription)")
                    // 如果重新创建失败，则完全停止播放
                    self.stopPlayback(reason: .error)
                }
            }
        }
    }
    
    func stopPlayback() {
        stopPlayback(reason: .userRequested)
    }
    
    func stopPlayback(reason: PlaybackStopReason) {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        stopPlaybackProgressTracking()
        
        // 清理播放完成continuation
        if let continuation = playbackCompletionContinuation {
            playbackCompletionContinuation = nil
            
            switch reason {
            case .deviceDisconnected:
                // 设备断开是正常情况，不应该抛出错误
                print("🎧 [AudioService] Playback stopped due to device disconnection - completing normally")
                continuation.resume()
            case .userRequested, .error:
                // 用户请求停止或出错时抛出取消错误
                continuation.resume(throwing: CancellationError())
            }
        }
    }
    
    enum PlaybackStopReason {
        case userRequested
        case deviceDisconnected  
        case error
    }
    
    private func startPlaybackProgressTracking() {
        stopPlaybackProgressTracking() // Stop any existing timer
        
        debugLog("🎵 [AudioService] Starting playback progress tracking")
        
        // Ensure timer runs on main queue for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self,
                      let player = self.audioPlayer else { 
                    debugLog("🎵 [AudioService] ⚠️ Progress tracking callback: no player available")
                    return 
                }
                
                let currentTime = player.currentTime
                let duration = player.duration
                
                // 每秒只打印一次进度日志，减少噪音
                if Int(currentTime) != Int(currentTime - 0.1) {
                    debugLog("🎵 [AudioService] Progress: \(String(format: "%.1f", currentTime))/\(String(format: "%.1f", duration))s")
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
            debugLog("🎵 [AudioService] Stopped playback progress tracking")
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
        debugLog("⏰ [AudioService] 🎵 AVAudioPlayerDelegate: playback finished successfully=\(flag)")
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
    
    // 统一的蓝牙设备检测函数
    private func isBluetoothOutput(_ portType: AVAudioSession.Port) -> Bool {
        return portType == .bluetoothA2DP || 
               portType == .bluetoothHFP || 
               portType == .bluetoothLE
    }
    
    /// 判断是否连接了耳机（包含有线耳机与蓝牙耳机）。
    /// 规则：
    /// - 有线耳机：输出包含 .headphones
    /// - 蓝牙耳机：输出为蓝牙端口，且输入也存在蓝牙（通常代表带麦克风的耳机）。
    /// - 蓝牙音箱：仅蓝牙输出而无蓝牙输入，则不视为耳机。
    func isHeadsetConnected() -> Bool {
        let route = audioSession.currentRoute
        let hasWiredHeadphones = route.outputs.contains { $0.portType == .headphones }
        let hasBluetoothOutput = route.outputs.contains { isBluetoothOutput($0.portType) }
        let hasBluetoothInput = route.inputs.contains { input in
            input.portType == .bluetoothHFP || input.portType == .bluetoothLE
        }
        let isBluetoothHeadset = hasBluetoothOutput && hasBluetoothInput
        return hasWiredHeadphones || isBluetoothHeadset
    }
    private var recordingWarmupRecorder: AVAudioRecorder?
    private var initializationError: Error?
    
    // Re-entry protection for audio session reconfiguration
    private var isReconfiguring = false
    private let reconfigurationQueue = DispatchQueue(label: "com.selflie.audio.reconfiguration", qos: .userInitiated)
    
    // Callback for notifying audio service of playback interruptions
    var playbackInterruptionHandler: ((AVAudioSession.RouteChangeReason) -> Void)?
    
    // Callback for notifying audio service to restart playback when new device becomes available
    var playbackRestartHandler: (() -> Void)?
    
    private init() {
        setupAudioSession()
        setupRouteChangeObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: audioSession)
        print("✅ [AudioSessionManager] Route change observer removed")
    }
    
    private func setupAudioSession() {
        do {
            // playAndRecord 场景使用正确的音频选项组合
            let audioOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
            
            try audioSession.setCategory(.playAndRecord, mode: .default, options: audioOptions)
            // Allow haptic feedback during recording (critical for PracticeView)
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audioSession.setActive(true)
            
            print("✅ [AudioSessionManager] Audio session initialized with .defaultToSpeaker and .allowBluetooth")
            initializationError = nil // 清除任何之前的错误
        } catch {
            initializationError = error
            print("❌ [AudioSessionManager] Failed to initialize audio session: \(error.localizedDescription)")
        }
    }
    
    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        print("✅ [AudioSessionManager] Route change observer registered for specific audio session")
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonRaw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
            print("⚠️ [AudioSessionManager] Route change notification received but could not parse reason")
            return
        }
        
        // Get previous route information for better decision making
        var previousRoute: AVAudioSessionRouteDescription?
        if let previousRouteObj = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
            previousRoute = previousRouteObj
        }
        
        let currentRoute = audioSession.currentRoute
        
        print("🎧 [AudioSessionManager] Audio route changed - reason: \(reason)")
        debugLog("🎧 [AudioSessionManager] Previous route: \(previousRoute?.outputs.map { "\($0.portName) (\($0.portType.rawValue))" } ?? ["None"])")
        debugLog("🎧 [AudioSessionManager] Current route: \(currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        
        switch reason {
        case .oldDeviceUnavailable:
            print("🎧 [AudioSessionManager] Device disconnected - handling playback and reconfiguring")
            // Notify audio service to handle playback interruption
            notifyPlaybackInterruption(reason: reason)
            // 重新配置音频会话以适应设备移除（从蓝牙切换回扬声器）
            Task { @MainActor in
                await reconfigureAudioSessionForCurrentRoute()
            }
            
        case .newDeviceAvailable, .routeConfigurationChange:
            print("🎧 [AudioSessionManager] Route change detected - checking for Bluetooth")
            
            // 使用统一的蓝牙检测函数检查当前路由
            let currentRoute = audioSession.currentRoute
            let hasBluetooth = currentRoute.outputs.contains { isBluetoothOutput($0.portType) }
            
            print("🎧 [AudioSessionManager] Current route outputs:")
            for output in currentRoute.outputs {
                print("🎧   - \(output.portName) (\(output.portType.rawValue))")
            }
            print("🎧 [AudioSessionManager] Has Bluetooth: \(hasBluetooth)")
            
            if hasBluetooth {
                // 关键：撤销扬声器强制，交给系统选AirPods
                do {
                    try audioSession.overrideOutputAudioPort(.none)
                    try audioSession.setActive(true)
                    print("🎧 [AudioSessionManager] ✅ Cleared audio port override, system routing to Bluetooth")
                    notifyPlaybackRestart()
                } catch {
                    print("🎧 [AudioSessionManager] ❌ Failed to clear override: \(error.localizedDescription)")
                }
            } else {
                print("🎧 [AudioSessionManager] No Bluetooth device in current route")
            }
            
        case .categoryChange:
            debugLog("🎧 [AudioSessionManager] Audio category changed - no action needed")
            // Skip reconfiguration to avoid routing conflicts
            
        case .override:
            debugLog("🎧 [AudioSessionManager] Route override - monitoring but not pausing playback")
            // Don't pause playback for override changes
            
        case .wakeFromSleep:
            debugLog("🎧 [AudioSessionManager] Wake from sleep - no action needed")
            // Skip reconfiguration to avoid routing conflicts
            
        case .noSuitableRouteForCategory:
            print("🎧 [AudioSessionManager] No suitable route for category - handling error")
            // This might need special error handling
            
        default:
            print("🎧 [AudioSessionManager] Route change reason '\(reason)' - no specific action needed")
        }
    }
    
    private func notifyPlaybackInterruption(reason: AVAudioSession.RouteChangeReason) {
        playbackInterruptionHandler?(reason)
    }
    
    private func notifyPlaybackRestart() {
        playbackRestartHandler?()
    }
    
    @MainActor
    private func reconfigureAudioSessionForCurrentRoute() async {
        // Re-entry protection: prevent multiple concurrent reconfigurations
        return await withCheckedContinuation { continuation in
            reconfigurationQueue.async {
                guard !self.isReconfiguring else {
                    debugLog("⚠️ [AudioSessionManager] Reconfiguration already in progress, skipping")
                    continuation.resume()
                    return
                }
                
                self.isReconfiguring = true
                defer { self.isReconfiguring = false }
                
                do {
                    // playAndRecord 场景使用固定的正确选项组合
                    let audioOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
                    
                    // Reconfigure the session with appropriate options
                    try self.audioSession.setCategory(.playAndRecord, mode: .default, options: audioOptions)
                    // 关键：重配置后也要保持录音期间允许触觉
                    try self.audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
                    
                    // Query updated hardware properties after route change (Apple best practice)
                    let newSampleRate = self.audioSession.sampleRate
                    let newIOBufferDuration = self.audioSession.ioBufferDuration
                    let newInputChannels = self.audioSession.inputNumberOfChannels
                    let newOutputChannels = self.audioSession.outputNumberOfChannels
                    
                    print("✅ [AudioSessionManager] Audio session reconfigured with .defaultToSpeaker and .allowBluetooth")
                    hardwareLog("🎛️ [AudioSessionManager] Updated hardware properties:")
                    hardwareLog("   Sample Rate: \(newSampleRate) Hz")
                    hardwareLog("   IO Buffer Duration: \(newIOBufferDuration) seconds")
                    hardwareLog("   Input Channels: \(newInputChannels)")
                    hardwareLog("   Output Channels: \(newOutputChannels)")
                    
                } catch {
                    print("❌ [AudioSessionManager] Failed to reconfigure audio session: \(error.localizedDescription)")
                }
                
                continuation.resume()
            }
        }
    }
    
    func getCurrentSampleRate() -> Double {
        return audioSession.sampleRate
    }
    
    // Issue 1 Fix: AirPods audio routing support
    func isBluetoothAudioDeviceConnected() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        let hasBluetoothOutput = route.outputs.contains { isBluetoothOutput($0.portType) }
        
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
        // playAndRecord 场景始终使用相同的选项组合
        return [.defaultToSpeaker, .allowBluetoothHFP]
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
    
    /// Safe reconfiguration without deactivating the session - prevents audio switching to other apps
    func reconfigureSessionSafely() async throws {
        print("⏰ [AudioSessionManager] 🔄 Safely reconfiguring audio session (no deactivation)")
        
        recordingWarmupRecorder?.stop()
        recordingWarmupRecorder = nil
        
        // Re-entry protection: prevent multiple concurrent reconfigurations
        return await withCheckedContinuation { continuation in
            reconfigurationQueue.async {
                guard !self.isReconfiguring else {
                    debugLog("⚠️ [AudioSessionManager] Safe reconfiguration already in progress, skipping")
                    continuation.resume()
                    return
                }
                
                self.isReconfiguring = true
                defer { self.isReconfiguring = false }
                
                do {
                    // Reconfigure without deactivating - maintains audio control
                    let audioOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
                    
                    try self.audioSession.setCategory(.playAndRecord, mode: .default, options: audioOptions)
                    // 关键：重配置后也要保持录音期间允许触觉
                    try self.audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
                    // Note: NOT calling setActive(false) - this prevents other apps from resuming
                    
                    // Query updated hardware properties
                    let newSampleRate = self.audioSession.sampleRate
                    let newIOBufferDuration = self.audioSession.ioBufferDuration
                    
                    print("✅ [AudioSessionManager] Audio session safely reconfigured")
                    print("🎛️ [AudioSessionManager] Hardware properties: \(newSampleRate)Hz, \(newIOBufferDuration)s buffer")
                    
                } catch {
                    print("❌ [AudioSessionManager] Failed to safely reconfigure audio session: \(error.localizedDescription)")
                }
                
                continuation.resume()
            }
        }
    }

    
    func deactivateSession() async throws {
        print("⏰ [AudioSessionManager] 🔄 Deactivating audio session and notifying other apps")
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        print("⏰ [AudioSessionManager] ✅ Audio session deactivated successfully")
    }
}
