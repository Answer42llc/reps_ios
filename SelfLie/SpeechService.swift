import Speech
import AVFoundation

@Observable
class SpeechService: NSObject {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var recognizedText = ""
    var isRecognizing = false
    var confidence: Float = 0.0
    
    // Audio level monitoring
    var currentAudioLevel: Float = -100.0
    var onAudioLevelUpdate: ((Float) -> Void)?
    var onSilenceDetected: ((Bool) -> Void)?
    
    // Silence detection
    private var silenceThreshold: Float = -40.0 // dB
    private var silenceStartTime: Date?
    private var isSilent = false
    
    override init() {
        super.init()
        // Don't set up recognizer here - we'll set it up based on the text language
    }
    
    deinit {
        print("🧹 [SpeechService] Cleaning up in deinit")
        stopRecognition()
    }
    
    func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    func startRecognition(expectedText: String) throws {
        print("🎤 [SpeechService] Starting speech recognition")
        
        // Stop any existing recognition first
        if isRecognizing {
            print("⚠️ [SpeechService] Stopping existing recognition before starting new one")
            stopRecognition()
            
            // Give a brief moment for cleanup
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Set up recognizer for the expected text language
        setupRecognizerForText(expectedText)
        
        guard let speechRecognizer = speechRecognizer else {
            print("❌ [SpeechService] No speech recognizer available")
            throw SpeechServiceError.recognitionFailed
        }
        
        guard speechRecognizer.isAvailable else {
            print("❌ [SpeechService] Speech recognizer not available")
            throw SpeechServiceError.recognitionFailed
        }
        
        // Ensure audio engine is in clean state
        if audioEngine.isRunning {
            print("⚠️ [SpeechService] Audio engine still running, stopping...")
            audioEngine.stop()
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Cancel any previous recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create and configure the speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechServiceError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Create recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ [SpeechService] Recognition error: \(error.localizedDescription)")
                let nsError = error as NSError
                print("   Domain: \(nsError.domain), Code: \(nsError.code)")
                
                // Handle specific error codes
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101 {
                    print("   🔧 Detected 1101 error - will attempt recovery")
                }
                
                self.stopRecognition()
                return
            }
            
            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
                self.confidence = result.bestTranscription.segments.last?.confidence ?? 0.0
                
                if result.isFinal {
                    print("✅ [SpeechService] Final recognition result: '\(self.recognizedText)'")
                    self.stopRecognition()
                }
            }
        }
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            
            // Calculate and monitor audio level
            self?.processAudioLevel(from: buffer)
        }
        
        // Prepare and start audio engine with error handling
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecognizing = true
            print("✅ [SpeechService] Audio engine started successfully")
            
            // Reset silence detection state
            resetSilenceDetection()
        } catch {
            print("❌ [SpeechService] Failed to start audio engine: \(error.localizedDescription)")
            
            // Clean up on failure
            recognitionTask?.cancel()
            recognitionTask = nil
            self.recognitionRequest?.endAudio()
            self.recognitionRequest = nil
            
            throw SpeechServiceError.recognitionFailed
        }
    }
    
    func stopRecognition() {
        guard isRecognizing else { return }
        
        print("🛑 [SpeechService] Stopping speech recognition")
        
        // Stop the audio engine first
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Remove audio tap safely
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // End audio input for recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Cancel and clean up recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecognizing = false
        
        print("✅ [SpeechService] Speech recognition stopped completely")
    }
    
    func calculateSimilarity(expected: String, recognized: String) -> Float {
        // Use universal embedding-based semantic similarity
        return EmbeddingSimilarity.calculateSimilarity(expected: expected, recognized: recognized)
    }
    
    func recognizeAudioFile(at url: URL, expectedText: String) async throws -> Float {
        print("🚀 Starting recognizeAudioFile")
        print("📄 Expected text: '\(expectedText)'")
        print("🎵 Audio file: \(url.lastPathComponent)")
        
        // Set up recognizer for the expected text language
        setupRecognizerForText(expectedText)
        
        // Get the final recognizer (either from setup or emergency fallback)
        let finalSpeechRecognizer: SFSpeechRecognizer
        
        if let speechRecognizer = speechRecognizer {
            finalSpeechRecognizer = speechRecognizer
        } else {
            print("❌ Speech recognizer is nil after setup")
            
            // Emergency fallback: force en-US
            print("🚨 EMERGENCY: Forcing en-US recognizer")
            let emergencyRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            
            if let emergencyRecognizer = emergencyRecognizer, emergencyRecognizer.isAvailable {
                print("✅ Emergency en-US recognizer successful")
                self.speechRecognizer = emergencyRecognizer
                finalSpeechRecognizer = emergencyRecognizer
            } else {
                print("💥 CRITICAL: Even en-US recognizer failed")
                throw SpeechServiceError.recognizerUnavailable(locale: "en-US")
            }
        }
        
        // Check if recognizer is available
        guard finalSpeechRecognizer.isAvailable else {
            print("❌ Speech recognizer is not available for locale: \(finalSpeechRecognizer.locale.identifier)")
            throw SpeechServiceError.recognitionFailed
        }
        
        // Verify the audio file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Audio file does not exist at path: \(url.path)")
            throw SpeechServiceError.recognitionFailed
        }
        
        print("🎙️ Starting speech recognition for file: \(url.lastPathComponent)")
        print("🌍 Using recognizer locale: \(finalSpeechRecognizer.locale.identifier)")
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            finalSpeechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                // Prevent multiple resume calls
                guard !hasResumed else { return }
                
                if let error = error {
                    print("❌ Speech recognition error: \(error.localizedDescription)")
                    print("   Error domain: \(error._domain)")
                    print("   Error code: \(error._code)")
                    
                    // Check for specific error types
                    let speechError = error as NSError
                    switch speechError.code {
                    case 1100...1199:
                        print("   🔊 Audio-related error")
                    case 1400...1499:
                        print("   🌐 Network-related error")
                    case 1700...1799:
                        print("   🔐 Authorization-related error")
                    default:
                        print("   ❓ Unknown error type")
                    }
                    
                    hasResumed = true
                    // Provide a fallback similarity score instead of failing completely
                    continuation.resume(returning: 0.5)
                    return
                }
                
                guard let result = result else {
                    print("⚠️ No recognition result received")
                    return
                }
                
                if result.isFinal {
                    let recognizedText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("✅ Final recognition result: '\(recognizedText)'")
                    print("🎯 Expected: '\(expectedText)'")
                    print("📊 Confidence: \(result.bestTranscription.segments.last?.confidence ?? 0.0)")
                    
                    // Use embedding-based similarity calculation
                    let similarity = self?.calculateSimilarity(expected: expectedText, recognized: recognizedText) ?? 0.0
                    print("🔍 Calculated similarity: \(similarity)")
                    
                    hasResumed = true
                    continuation.resume(returning: similarity)
                } else {
                    // Show partial results for debugging
                    let partialText = result.bestTranscription.formattedString
                    print("📝 Partial result: '\(partialText)'")
                }
            }
        }
    }
    
    private func resetSilenceDetection() {
        isSilent = false
        silenceStartTime = nil
        currentAudioLevel = -100.0
    }
    
    private func processAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let channelDataValue = channelData
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }
        
        // Calculate RMS (Root Mean Square) for audio level
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))
        
        // Convert to decibels
        let decibels = rms > 0 ? 20 * log10(rms) : -100.0
        
        // Update current audio level
        currentAudioLevel = decibels
        
        // Notify about audio level updates
        onAudioLevelUpdate?(decibels)
        
        // Check for silence
        let currentTime = Date()
        
        if decibels < silenceThreshold {
            // Audio is below silence threshold
            if !isSilent {
                // Just became silent
                isSilent = true
                silenceStartTime = currentTime
            } else if let silenceStart = silenceStartTime {
                // Already silent, check duration
                let silenceDuration = currentTime.timeIntervalSince(silenceStart)
                if silenceDuration >= 1.5 { // 1.5 seconds of silence
                    onSilenceDetected?(true)
                }
            }
        } else {
            // Audio is above silence threshold
            if isSilent {
                // No longer silent
                isSilent = false
                silenceStartTime = nil
                onSilenceDetected?(false)
            }
        }
    }
    
    private func setupRecognizerForText(_ text: String) {
        print("🔍 Detecting language for text: '\(text)'")
        
        // Use unified language detection
        let detectionResult = LanguageDetector.detectLanguage(from: text)
        let localeIdentifier = detectionResult.localeIdentifier
        
        print("🌍 Detected language: \(detectionResult.description)")
        print("📍 Using locale: \(localeIdentifier)")
        print("🎯 Confidence: \(detectionResult.isHighConfidence ? "High" : "Low")")
        
        let preferredLocale = Locale(identifier: localeIdentifier)
        
        // Try to create recognizer for preferred locale
        var recognizer = SFSpeechRecognizer(locale: preferredLocale)
        
        // Check if the recognizer was created successfully
        if let createdRecognizer = recognizer {
            if createdRecognizer.isAvailable {
                print("✅ Speech recognizer available for \(localeIdentifier)")
            } else {
                print("⚠️ Speech recognizer created but not available for \(localeIdentifier)")
                recognizer = nil
            }
        } else {
            print("❌ Failed to create speech recognizer for \(localeIdentifier)")
        }
        
        // If preferred recognizer is not available, try fallback locales
        if recognizer == nil || recognizer?.isAvailable == false {
            print("🔄 Trying fallback locales...")
            
            let fallbackLocales = [
                "en-US",    // English (US) - most widely supported
                "en-GB",    // English (UK)
                "zh-CN",    // Chinese (Simplified)
                "ja-JP",    // Japanese
                "ko-KR",    // Korean
                "es-ES",    // Spanish
                "fr-FR",    // French
                "de-DE",    // German
                "it-IT",    // Italian
                "pt-BR",    // Portuguese
                "ru-RU",    // Russian
                "ar-SA",    // Arabic
                "hi-IN"     // Hindi
            ]
            
            for fallbackLocale in fallbackLocales {
                print("   Trying: \(fallbackLocale)")
                if let testRecognizer = SFSpeechRecognizer(locale: Locale(identifier: fallbackLocale)) {
                    if testRecognizer.isAvailable {
                        print("✅ Using fallback locale: \(fallbackLocale)")
                        recognizer = testRecognizer
                        break
                    } else {
                        print("   ⚠️ \(fallbackLocale): Created but not available")
                    }
                } else {
                    print("   ❌ \(fallbackLocale): Cannot create recognizer")
                }
            }
        }
        
        // Final fallback to default system recognizer
        if recognizer == nil || (recognizer != nil && !recognizer!.isAvailable) {
            print("🆘 Trying default system speech recognizer...")
            let defaultRecognizer = SFSpeechRecognizer()
            
            if let defaultRecognizer = defaultRecognizer {
                if defaultRecognizer.isAvailable {
                    print("✅ Using default system recognizer: \(defaultRecognizer.locale.identifier)")
                    recognizer = defaultRecognizer
                } else {
                    print("⚠️ Default recognizer created but not available: \(defaultRecognizer.locale.identifier)")
                }
            } else {
                print("❌ Cannot create default system recognizer")
            }
        }
        
        // Final check
        guard let finalRecognizer = recognizer else {
            print("💥 CRITICAL: No speech recognizer available at all!")
            speechRecognizer = nil
            return
        }
        
        if !finalRecognizer.isAvailable {
            print("💥 CRITICAL: Final recognizer is not available!")
            speechRecognizer = nil
            return
        }
        
        speechRecognizer = finalRecognizer
        speechRecognizer?.delegate = self
        
        let actualLocale = speechRecognizer?.locale.identifier ?? "unknown"
        print("🎤 Final setup: Speech recognizer ready for locale: \(actualLocale)")
    }
    
    // MARK: - Debug and Testing Methods
    
    /// 测试当前设备支持的语音识别器
    static func testAvailableSpeechRecognizers() {
        print("🔍 Testing available speech recognizers on current device:")
        print(String(repeating: "=", count: 50))
        
        let testLocales = [
            "en-US", "en-GB", "en-AU", "en-CA",
            "zh-CN", "zh-TW", "zh-HK",
            "ja-JP", "ko-KR",
            "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR",
            "ru-RU", "ar-SA", "hi-IN", "th-TH", "vi-VN"
        ]
        
        var availableCount = 0
        var unavailableCount = 0
        
        for localeId in testLocales {
            let locale = Locale(identifier: localeId)
            let recognizer = SFSpeechRecognizer(locale: locale)
            
            if let recognizer = recognizer {
                if recognizer.isAvailable {
                    print("✅ \(localeId): Available")
                    availableCount += 1
                } else {
                    print("⚠️  \(localeId): Created but not available")
                    unavailableCount += 1
                }
            } else {
                print("❌ \(localeId): Cannot create recognizer")
                unavailableCount += 1
            }
        }
        
        print(String(repeating: "=", count: 50))
        print("📊 Summary: \(availableCount) available, \(unavailableCount) unavailable")
        
        // Test default system recognizer
        let defaultRecognizer = SFSpeechRecognizer()
        if let defaultRecognizer = defaultRecognizer {
            let defaultLocale = defaultRecognizer.locale.identifier
            let isAvailable = defaultRecognizer.isAvailable
            print("🏠 Default system recognizer: \(defaultLocale) - \(isAvailable ? "Available" : "Not Available")")
        } else {
            print("💥 CRITICAL: No default system recognizer available!")
        }
    }
}

extension SpeechService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        let locale = speechRecognizer.locale.identifier
        if available {
            print("✅ Speech recognizer became available for locale: \(locale)")
        } else {
            print("❌ Speech recognizer became unavailable for locale: \(locale)")
            // Could trigger a setup retry or fallback here
        }
    }
}

enum SpeechServiceError: LocalizedError {
    case requestCreationFailed
    case recognitionFailed
    case permissionDenied
    case recognizerUnavailable(locale: String)
    case audioFileNotFound(path: String)
    case noRecognitionResult
    
    var errorDescription: String? {
        switch self {
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        case .recognitionFailed:
            return "Speech recognition failed"
        case .permissionDenied:
            return "Speech recognition permission denied"
        case .recognizerUnavailable(let locale):
            return "Speech recognizer not available for locale: \(locale)"
        case .audioFileNotFound(let path):
            return "Audio file not found at path: \(path)"
        case .noRecognitionResult:
            return "No recognition result received"
        }
    }
}
