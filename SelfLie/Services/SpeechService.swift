import Speech
import AVFoundation

// Word timing data structure
struct WordTiming: Codable {
    let word: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let confidence: Float
    
    var endTime: TimeInterval {
        return startTime + duration
    }
}

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
    
    // Universal text unit recognition callbacks
    var onWordRecognized: ((String, Set<Int>) -> Void)?
    var recognizedWords: Set<Int> = []
    private var expectedTextUnits: [UniversalTextProcessor.TextUnit] = []
    
    // Accumulated recognition text for sequential matching
    private var accumulatedRecognizedText: String = ""
    private var expectedFullText: String = ""
    
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
    
    func startRecognition(expectedText: String, localeIdentifier: String? = nil) throws {
        print("🎤 [SpeechService] Starting speech recognition")
        
        // Stop any existing recognition first
        if isRecognizing {
            print("⚠️ [SpeechService] Stopping existing recognition before starting new one")
            stopRecognition()
            
            // Give a brief moment for cleanup
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Prepare expected text units for tracking using universal processor
        expectedTextUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        recognizedWords.removeAll()
        
        // Initialize accumulated recognition tracking
        accumulatedRecognizedText = ""
        expectedFullText = expectedText
        
        print("🌍 [SpeechService] Using universal text processing for '\(expectedText)'")
        print("📊 [SpeechService] Expected units: \(UniversalTextProcessor.extractTexts(from: expectedTextUnits))")
        
        // Set up recognizer for the expected text language
        setupRecognizerForText(expectedText, localeIdentifier: localeIdentifier)
        
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
                
                // Process word-level recognition
                self.processWordRecognition(result: result)
                
                if result.isFinal {
                    print("✅ [SpeechService] Final recognition result: '\(self.recognizedText)'")
                    self.stopRecognition()
                }
            }
        }
        
        // Configure audio engine with proper format handling
        let inputNode = audioEngine.inputNode
        
        // Get the hardware input format
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("🎙️ [SpeechService] Input hardware format: \(inputFormat)")
        
        // Use the hardware input format for the tap to avoid format mismatch
        // This ensures we use the actual hardware sample rate (24kHz in this case)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
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
            print("🎙️ [SpeechService] Hardware format info:")
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            let outputFormat = inputNode.outputFormat(forBus: 0)
            print("   Input format: \(inputFormat)")
            print("   Output format: \(outputFormat)")
            
            // Clean up on failure
            recognitionTask?.cancel()
            recognitionTask = nil
            self.recognitionRequest?.endAudio()
            self.recognitionRequest = nil
            audioEngine.inputNode.removeTap(onBus: 0)
            
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
    
    /// Reset the speech recognizer to clear language settings
    func resetRecognizer() {
        print("🔄 [SpeechService] Resetting speech recognizer")
        
        // Stop any ongoing recognition
        if isRecognizing {
            stopRecognition()
        }
        
        // Clear the recognizer to force re-detection on next use
        speechRecognizer = nil
        recognizedText = ""
        recognizedWords.removeAll()
        expectedTextUnits.removeAll()
        accumulatedRecognizedText = ""
        
        print("✅ [SpeechService] Speech recognizer reset completed")
    }
    
    private func processWordRecognition(result: SFSpeechRecognitionResult) {
        guard !expectedTextUnits.isEmpty else { return }
        
        let recognizedText = result.bestTranscription.formattedString
        print("🎤 [SpeechService] Processing recognition: '\(recognizedText)'")
        
        // Update accumulated recognized text
        accumulatedRecognizedText = recognizedText
        
        // Calculate sequential highlight indices
        let highlightIndices = calculateHighlightIndices(
            expectedText: expectedFullText,
            recognizedText: accumulatedRecognizedText
        )
        
        print("🔍 [SpeechService] Accumulated text: '\(accumulatedRecognizedText)'")
        print("🎯 [SpeechService] Sequential highlight indices: \(highlightIndices)")
        
        // Notify about recognition updates with new sequential highlighting
        onWordRecognized?(accumulatedRecognizedText, highlightIndices)
    }
    
    /// Check if a character is a punctuation mark
    private func isPunctuation(_ text: String) -> Bool {
        // Chinese punctuation
        let chinesePunctuation = "，。！？；：（）【】「」『』〔〕《》〈〉"
        // Chinese quotes (using character literals to avoid syntax issues)
        let leftChineseQuote = String("\u{201C}")  // "
        let rightChineseQuote = String("\u{201D}") // "
        let leftChineseSingleQuote = String("\u{2018}")  // '
        let rightChineseSingleQuote = String("\u{2019}") // '
        let chineseQuotes = leftChineseQuote + rightChineseQuote + leftChineseSingleQuote + rightChineseSingleQuote
        // English punctuation  
        let englishPunctuation = ",.!?;:\"'()[]{}"
        // Common symbols
        let commonSymbols = "-_/\\|@#$%^&*+=<>~`"
        
        let allPunctuation = chinesePunctuation + chineseQuotes + englishPunctuation + commonSymbols
        
        return text.count == 1 && allPunctuation.contains(text)
    }
    
    /// Calculate highlight indices using fault-tolerant matching with punctuation skipping
    private func calculateHighlightIndices(expectedText: String, recognizedText: String) -> Set<Int> {
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        let recognizedUnits = UniversalTextProcessor.smartSegmentText(recognizedText)
        
        var matchedIndices: Set<Int> = []
        var expectedIndex = 0
        
        print("🎯 [SpeechService] Starting fault-tolerant matching:")
        print("🎯   Expected units: \(UniversalTextProcessor.extractTexts(from: expectedUnits))")
        print("🎯   Recognized units: \(UniversalTextProcessor.extractTexts(from: recognizedUnits))")
        
        // Fault-tolerant matching with punctuation skipping
        for (recognizedIdx, recognizedUnit) in recognizedUnits.enumerated() {
            print("🔍 [SpeechService] Processing recognized[\(recognizedIdx)]: '\(recognizedUnit.text)'")
            
            // Skip any leading punctuation before trying to match
            while expectedIndex < expectedUnits.count && isPunctuation(expectedUnits[expectedIndex].text) {
                print("🔤 [SpeechService] Skipping punctuation at expected[\(expectedIndex)]: '\(expectedUnits[expectedIndex].text)'")
                matchedIndices.insert(expectedIndex)
                expectedIndex += 1
            }
            
            // Look for a match within a reasonable range (allowing for small gaps)
            var found = false
            let maxSearchRange = min(10, expectedUnits.count - expectedIndex) // Search up to 10 positions ahead
            
            for offset in 0..<maxSearchRange {
                let checkIndex = expectedIndex + offset
                
                // Don't go beyond bounds
                guard checkIndex < expectedUnits.count else { break }
                
                let candidateUnit = expectedUnits[checkIndex]
                
                // Check if this position matches
                if recognizedUnit.text == candidateUnit.text {
                    print("🎯 [SpeechService] Found match at [\(checkIndex)] with offset \(offset): '\(recognizedUnit.text)' ✓")
                    
                    // Mark any skipped positions between expectedIndex and checkIndex
                    for skipIndex in expectedIndex..<checkIndex {
                        if isPunctuation(expectedUnits[skipIndex].text) {
                            print("🔤 [SpeechService] Marking skipped punctuation at [\(skipIndex)]: '\(expectedUnits[skipIndex].text)'")
                            matchedIndices.insert(skipIndex)
                        } else {
                            // Allow skipping non-punctuation words to improve fault tolerance
                            print("🔤 [SpeechService] Skipping non-punctuation at [\(skipIndex)]: '\(expectedUnits[skipIndex].text)' (offset: \(offset))")
                            // Don't mark non-punctuation as matched if we're skipping it
                        }
                    }
                    
                    // Mark the actual match
                    matchedIndices.insert(checkIndex)
                    expectedIndex = checkIndex + 1
                    found = true
                    break
                }
            }
            
            if !found {
                print("🔍 [SpeechService] No match found for '\(recognizedUnit.text)' within range, continuing with next recognized character")
                // Don't stop - continue with the next recognized character
                // This allows us to recover from recognition errors or missing characters
            }
        }
        
        // Handle any remaining punctuation at the end
        while expectedIndex < expectedUnits.count && isPunctuation(expectedUnits[expectedIndex].text) {
            print("🔤 [SpeechService] Final punctuation at [\(expectedIndex)]: '\(expectedUnits[expectedIndex].text)'")
            matchedIndices.insert(expectedIndex)
            expectedIndex += 1
        }
        
        print("🎯 [SpeechService] Final matched indices: \(matchedIndices.sorted())")
        return matchedIndices
    }
    
    private func calculateWordSimilarity(_ word1: String, _ word2: String) -> Float {
        // Simple Levenshtein distance-based similarity
        let distance = levenshteinDistance(word1, word2)
        let maxLength = max(word1.count, word2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - Float(distance) / Float(maxLength)
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count {
            matrix[i][0] = i
        }
        for j in 0...s2Count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[s1Count][s2Count]
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
        setupRecognizerForText(expectedText, localeIdentifier: nil)
        
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
    
    private func setupRecognizerForText(_ text: String, localeIdentifier: String? = nil) {
        let finalLocaleIdentifier: String
        
        if let cachedLocaleId = localeIdentifier {
            // Use provided cached language detection result
            finalLocaleIdentifier = cachedLocaleId
            print("🔍 Using cached language detection for text: '\(text)' -> \(cachedLocaleId)")
        } else {
            // Fallback to detecting language (for backward compatibility)
            print("🔍 Detecting language for text: '\(text)'")
            let detectionResult = LanguageDetector.detectLanguage(from: text)
            finalLocaleIdentifier = detectionResult.localeIdentifier
            print("🌍 Detected language: \(detectionResult.description)")
        }
        
        let localeIdentifier = finalLocaleIdentifier
        print("📍 Using locale: \(localeIdentifier)")
        
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

// MARK: - Audio File Analysis Extension
extension SpeechService {
    
    /// Analyze an audio file to extract precise word timings using Speech framework
    func analyzeAudioFile(at url: URL, expectedText: String) async throws -> [WordTiming] {
        print("🎯 [SpeechService] Starting audio file analysis for precise word timings")
        print("📄 Expected text: '\(expectedText)'")
        print("🎵 Audio file: \(url.lastPathComponent)")
        
        // Verify audio file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Audio file not found at: \(url.path)")
            throw SpeechServiceError.audioFileNotFound(path: url.path)
        }
        
        // Set up recognizer for the expected text language
        setupRecognizerForText(expectedText, localeIdentifier: nil)
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            throw SpeechServiceError.recognizerUnavailable(locale: "auto-detected")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false // We only want the final result
            
            var hasResumed = false // Track if continuation has been resumed
            
            _ = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                // Prevent multiple resume calls
                guard !hasResumed else { 
                    print("⚠️ Recognition callback called after continuation was already resumed")
                    return 
                }
                
                if let error = error {
                    print("❌ Audio analysis failed: \(error.localizedDescription)")
                    hasResumed = true
                    continuation.resume(throwing: SpeechServiceError.recognitionFailed)
                    return
                }
                
                guard let result = result else {
                    print("⚠️ No analysis result received")
                    return
                }
                
                if result.isFinal {
                    print("✅ Audio analysis complete")
                    let wordTimings = self?.extractWordTimings(from: result, expectedText: expectedText) ?? []
                    print("🎯 Extracted \(wordTimings.count) word timings")
                    hasResumed = true
                    continuation.resume(returning: wordTimings)
                }
            }
            
            // Don't store task reference - let it be managed by the continuation
            // This prevents conflict with real-time recognition task and avoids Error 1101
            // The task will be automatically cleaned up when the continuation completes
        }
    }
    
    /// Extract word timings from SFSpeechRecognitionResult
    private func extractWordTimings(from result: SFSpeechRecognitionResult, expectedText: String) -> [WordTiming] {
        let segments = result.bestTranscription.segments
        
        // Use UniversalTextProcessor to determine the best processing approach
        if UniversalTextProcessor.containsCJKCharacters(expectedText) {
            print("🀄 Processing CJK text with character-level timing")
            return extractChineseWordTimings(segments: segments, expectedText: expectedText)
        } else {
            print("🔤 Processing alphabetic text with word-level timing")
            return extractEnglishWordTimings(segments: segments, expectedText: expectedText)
        }
    }
    
    /// Extract word timings for English text (original logic)
    private func extractEnglishWordTimings(segments: [SFTranscriptionSegment], expectedText: String) -> [WordTiming] {
        let expectedWords = expectedText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        
        print("🔍 Processing \(segments.count) segments for \(expectedWords.count) expected words")
        
        var wordTimings: [WordTiming] = []
        var expectedWordIndex = 0
        
        for segment in segments {
            let segmentText = segment.substring.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let segmentWords = segmentText.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            
            // Calculate time per word in this segment
            let timePerWordInSegment = segmentWords.count > 0 ? segment.duration / Double(segmentWords.count) : 0
            
            for (wordIndexInSegment, segmentWord) in segmentWords.enumerated() {
                // Find matching expected word
                if expectedWordIndex < expectedWords.count {
                    let expectedWord = expectedWords[expectedWordIndex]
                    
                    // Check if this segment word matches the expected word
                    let similarity = calculateWordSimilarity(expectedWord, segmentWord)
                    
                    if similarity > 0.6 || segmentWord.contains(expectedWord) || expectedWord.contains(segmentWord) {
                        // Calculate precise timing for this word within the segment
                        let wordStartTime = segment.timestamp + (timePerWordInSegment * Double(wordIndexInSegment))
                        let wordDuration = timePerWordInSegment
                        
                        let wordTiming = WordTiming(
                            word: expectedWord,
                            startTime: wordStartTime,
                            duration: wordDuration,
                            confidence: segment.confidence
                        )
                        
                        wordTimings.append(wordTiming)
                        print("📍 Word '\(expectedWord)' -> \(String(format: "%.2f", wordStartTime))s-\(String(format: "%.2f", wordStartTime + wordDuration))s")
                        
                        expectedWordIndex += 1
                    }
                }
            }
        }
        
        // Fill in any missing words with estimated timings
        if wordTimings.count < expectedWords.count {
            print("⚠️ Only found \(wordTimings.count)/\(expectedWords.count) words, filling gaps with estimates")
            wordTimings = fillMissingWordTimings(wordTimings: wordTimings, expectedWords: expectedWords, totalDuration: segments.last?.timestamp ?? 0)
        }
        
        return wordTimings
    }
    
    /// Extract word timings for Chinese text (simplified segment-based approach)
    func extractChineseWordTimings(segments: [SFTranscriptionSegment], expectedText: String) -> [WordTiming] {
        let expectedTextUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        let expectedCharacters = UniversalTextProcessor.extractTexts(from: expectedTextUnits)
        
        print("🀄 Simplified approach: Processing \(segments.count) segments for \(expectedCharacters.count) expected characters")
        
        var wordTimings: [WordTiming] = []
        var characterIndex = 0
        
        // Sort segments by timestamp to ensure proper order
        let sortedSegments = segments.sorted { $0.timestamp < $1.timestamp }
        
        for segment in sortedSegments {
            let segmentText = segment.substring.filter { !$0.isWhitespace }
            let segmentLength = segmentText.count
            
            guard segmentLength > 0 else { 
                print("⚠️ Empty segment, skipping")
                continue 
            }
            
            print("📊 Segment '\(segmentText)' (\(segmentLength) chars) at \(String(format: "%.2f", segment.timestamp))s")
            
            // Calculate how many characters this segment should highlight
            let charactersToHighlight = min(segmentLength, expectedCharacters.count - characterIndex)
            
            // Calculate time interval between characters in this segment
            let timePerCharacter = segment.duration / Double(max(charactersToHighlight, 1))
            
            // Create timing for each character that should be highlighted by this segment
            for i in 0..<charactersToHighlight {
                let currentCharacterIndex = characterIndex + i
                if currentCharacterIndex < expectedCharacters.count {
                    let expectedChar = expectedCharacters[currentCharacterIndex]
                    
                    // Give each character a slightly different timestamp within the segment
                    let characterTimestamp = segment.timestamp + (timePerCharacter * Double(i))
                    
                    let wordTiming = WordTiming(
                        word: expectedChar,
                        startTime: characterTimestamp,
                        duration: timePerCharacter, // Use calculated duration
                        confidence: segment.confidence
                    )
                    
                    wordTimings.append(wordTiming)
                    print("📍 Char '\(expectedChar)' -> \(String(format: "%.2f", characterTimestamp))s (progressive within segment)")
                }
            }
            
            characterIndex += charactersToHighlight
            
            // If we've processed all expected characters, break
            if characterIndex >= expectedCharacters.count {
                break
            }
        }
        
        // If there are remaining characters, add them with progressive timestamps
        if characterIndex < expectedCharacters.count {
            let lastSegment = sortedSegments.last
            let lastTimestamp = lastSegment?.timestamp ?? 0
            let lastDuration = lastSegment?.duration ?? 0.5
            let remainingCount = expectedCharacters.count - characterIndex
            let timePerRemainingChar = lastDuration / Double(max(remainingCount, 1))
            
            print("⚠️ Adding remaining \(remainingCount) characters with progressive timestamps")
            
            for i in characterIndex..<expectedCharacters.count {
                let expectedChar = expectedCharacters[i]
                let charIndex = i - characterIndex
                let characterTimestamp = lastTimestamp + lastDuration + (timePerRemainingChar * Double(charIndex))
                
                let wordTiming = WordTiming(
                    word: expectedChar,
                    startTime: characterTimestamp,
                    duration: timePerRemainingChar,
                    confidence: 0.5
                )
                wordTimings.append(wordTiming)
                print("📍 Remaining char '\(expectedChar)' -> \(String(format: "%.2f", characterTimestamp))s")
            }
        }
        
        print("✅ Created \(wordTimings.count) character timings using simplified segment-based approach")
        return wordTimings
    }
    
    /// Fill missing Chinese character timings with reasonable estimates
    private func fillMissingChineseCharacters(wordTimings: [WordTiming], expectedCharacters: [String], totalDuration: TimeInterval) -> [WordTiming] {
        var completeTimings: [WordTiming] = []
        
        if !wordTimings.isEmpty {
            // Use existing timings as anchors and fill gaps
            var currentTimingIndex = 0
            
            for (_, expectedChar) in expectedCharacters.enumerated() {
                if currentTimingIndex < wordTimings.count && 
                   wordTimings[currentTimingIndex].word == expectedChar {
                    // Use actual timing
                    completeTimings.append(wordTimings[currentTimingIndex])
                    currentTimingIndex += 1
                } else {
                    // Estimate timing based on previous character
                    let estimatedStartTime: TimeInterval
                    let estimatedDuration: TimeInterval = 0.3 // Shorter for Chinese characters
                    
                    if completeTimings.isEmpty {
                        estimatedStartTime = 0
                    } else {
                        let lastTiming = completeTimings.last!
                        estimatedStartTime = lastTiming.endTime
                    }
                    
                    let estimatedTiming = WordTiming(
                        word: expectedChar,
                        startTime: estimatedStartTime,
                        duration: estimatedDuration,
                        confidence: 0.5 // Lower confidence for estimated
                    )
                    
                    completeTimings.append(estimatedTiming)
                    print("📊 Estimated timing for '\(expectedChar)' at \(String(format: "%.2f", estimatedStartTime))s")
                }
            }
        } else {
            // No timings found, use simple even distribution
            print("⚠️ No character timings found, using even distribution fallback")
            let timePerChar = totalDuration > 0 ? totalDuration / Double(expectedCharacters.count) : 0.3
            
            for (index, expectedChar) in expectedCharacters.enumerated() {
                let timing = WordTiming(
                    word: expectedChar,
                    startTime: Double(index) * timePerChar,
                    duration: timePerChar,
                    confidence: 0.3 // Low confidence for fallback
                )
                completeTimings.append(timing)
            }
        }
        
        return completeTimings
    }
    
    /// Fill missing word timings with reasonable estimates
    private func fillMissingWordTimings(wordTimings: [WordTiming], expectedWords: [String], totalDuration: TimeInterval) -> [WordTiming] {
        var completeTimings: [WordTiming] = []
        
        // If we have some timings, use them as anchors
        if !wordTimings.isEmpty {
            var currentTimingIndex = 0
            
            for (_, expectedWord) in expectedWords.enumerated() {
                if currentTimingIndex < wordTimings.count && 
                   wordTimings[currentTimingIndex].word.lowercased() == expectedWord.lowercased() {
                    // Use actual timing
                    completeTimings.append(wordTimings[currentTimingIndex])
                    currentTimingIndex += 1
                } else {
                    // Estimate timing based on surrounding words
                    let estimatedStartTime: TimeInterval
                    let estimatedDuration: TimeInterval = 0.5 // Default duration
                    
                    if completeTimings.isEmpty {
                        estimatedStartTime = 0
                    } else {
                        let lastTiming = completeTimings.last!
                        estimatedStartTime = lastTiming.endTime
                    }
                    
                    let estimatedTiming = WordTiming(
                        word: expectedWord,
                        startTime: estimatedStartTime,
                        duration: estimatedDuration,
                        confidence: 0.5 // Lower confidence for estimated
                    )
                    
                    completeTimings.append(estimatedTiming)
                    print("📊 Estimated timing for '\(expectedWord)' at \(String(format: "%.2f", estimatedStartTime))s")
                }
            }
        } else {
            // No timings found, use simple even distribution
            print("⚠️ No word timings found, using even distribution fallback")
            let timePerWord = totalDuration > 0 ? totalDuration / Double(expectedWords.count) : 0.5
            
            for (index, expectedWord) in expectedWords.enumerated() {
                let timing = WordTiming(
                    word: expectedWord,
                    startTime: Double(index) * timePerWord,
                    duration: timePerWord,
                    confidence: 0.3 // Low confidence for fallback
                )
                completeTimings.append(timing)
            }
        }
        
        return completeTimings
    }
}
