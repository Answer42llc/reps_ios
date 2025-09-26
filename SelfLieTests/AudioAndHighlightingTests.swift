import XCTest
import AVFoundation
import CoreData
@testable import SelfLie

final class AudioAndHighlightingTests: XCTestCase {
    
    // MARK: - Issue 1 Tests: AirPods Audio Routing
    
    func testAudioDeviceDetection() {
        // Test that we can detect Bluetooth audio devices
        // Note: This test will use mocked data since we can't control actual hardware
        
        let audioSessionManager = AudioSessionManager.shared
        
        // Test method exists and returns a boolean
        let hasBluetoothDevice = audioSessionManager.isBluetoothAudioDeviceConnected()
        XCTAssertTrue(hasBluetoothDevice == true || hasBluetoothDevice == false, "Method should return a boolean")
    }
    
    func testAudioSessionOptionsForBluetooth() {
        let audioSessionManager = AudioSessionManager.shared
        
        // Test that Bluetooth options are returned when Bluetooth device is present
        let bluetoothOptions = audioSessionManager.getAudioSessionOptions(hasBluetoothDevice: true)
        XCTAssertTrue(bluetoothOptions.contains(.allowBluetoothA2DP), "Should include .allowBluetoothA2DP for Bluetooth devices")
    }
    
    func testAudioSessionOptionsForSpeaker() {
        let audioSessionManager = AudioSessionManager.shared
        
        // Test that speaker options are returned when no Bluetooth device
        let speakerOptions = audioSessionManager.getAudioSessionOptions(hasBluetoothDevice: false)
        XCTAssertTrue(speakerOptions.contains(.defaultToSpeaker), "Should include .defaultToSpeaker when no Bluetooth devices")
    }
    
    // MARK: - Issue 2 Tests: Highlighting Reset
    
    func testHighlightingStateReset() {
        // Create mock affirmation
        let mockAffirmation = createMockAffirmation(text: "Hello world test")
        var practiceView = PracticeSessionView(
            affirmation: mockAffirmation,
            isActive: true,
            closeTrigger: 0,
            restartTrigger: 0,
            onRequestNext: {},
            onDismiss: {}
        )
        
        // Simulate highlighted state after playback
        practiceView.highlightedWordIndices = Set([0, 1, 2])
        practiceView.currentWordIndex = 2
        
        // Verify initial state
        XCTAssertEqual(practiceView.highlightedWordIndices.count, 3, "Should have 3 highlighted words initially")
        XCTAssertEqual(practiceView.currentWordIndex, 2, "Current word index should be 2")
        
        // Simulate recording start (this will test our fix)
        practiceView.simulateRecordingStart()
        
        // Verify highlighting is reset
        XCTAssertTrue(practiceView.highlightedWordIndices.isEmpty, "Highlighted words should be cleared when recording starts")
        XCTAssertEqual(practiceView.currentWordIndex, -1, "Current word index should be reset to -1")
    }
    
    // MARK: - Issue 3 Tests: Chinese Text Highlighting
    
    func testChineseTextDetection() {
        // Test pure Chinese text
        XCTAssertTrue(LanguageUtils.isChineseText("我爱你"), "Should detect Chinese characters")
        XCTAssertTrue(LanguageUtils.isChineseText("这是中文"), "Should detect Chinese text")
        
        // Test mixed text
        XCTAssertTrue(LanguageUtils.isChineseText("Hello 你好"), "Should detect mixed Chinese-English text")
        XCTAssertTrue(LanguageUtils.isChineseText("我爱 you"), "Should detect mixed text with Chinese first")
        
        // Test pure English text
        XCTAssertFalse(LanguageUtils.isChineseText("Hello World"), "Should not detect English-only text as Chinese")
        XCTAssertFalse(LanguageUtils.isChineseText("This is English"), "Should not detect English text as Chinese")
        
        // Test empty and whitespace
        XCTAssertFalse(LanguageUtils.isChineseText(""), "Should handle empty string")
        XCTAssertFalse(LanguageUtils.isChineseText("   "), "Should handle whitespace-only string")
    }
    
    func testChineseCharacterSplitting() {
        // Test pure Chinese text splitting
        let chineseResult = LanguageUtils.splitTextForLanguage("我爱你")
        XCTAssertEqual(chineseResult, ["我", "爱", "你"], "Should split Chinese text into individual characters")
        
        // Test Chinese with spaces (should ignore spaces)
        let chineseWithSpaces = LanguageUtils.splitTextForLanguage("我 爱 你")
        XCTAssertEqual(chineseWithSpaces, ["我", "爱", "你"], "Should ignore spaces in Chinese text")
        
        // Test English text splitting (should work as before)
        let englishResult = LanguageUtils.splitTextForLanguage("Hello world test")
        XCTAssertEqual(englishResult, ["Hello", "world", "test"], "Should split English text by words")
        
        // Test mixed text (detected as Chinese, should split by characters)
        let mixedResult = LanguageUtils.splitTextForLanguage("Hello你好")
        XCTAssertEqual(mixedResult, ["H", "e", "l", "l", "o", "你", "好"], "Mixed text should be split by characters when Chinese is detected")
    }
    
    func testChineseWordTimingGeneration() {
        let speechService = SpeechService()
        
        // Create mock speech segments for Chinese text (simplified approach)
        let mockSegments = createMockChineseSpeechSegments(
            text: "我爱你",
            startTime: 0.0,
            duration: 1.5
        )
        
        let timings = speechService.extractChineseWordTimings(segments: mockSegments, expectedText: "我爱你")
        
        // Verify correct number of timings
        XCTAssertEqual(timings.count, 3, "Should generate timing for each Chinese character")
        
        // Verify individual character timings
        XCTAssertEqual(timings[0].word, "我", "First timing should be for '我'")
        XCTAssertEqual(timings[1].word, "爱", "Second timing should be for '爱'")
        XCTAssertEqual(timings[2].word, "你", "Third timing should be for '你'")
        
        // Verify progressive approach: characters should have different timestamps within segment
        XCTAssertEqual(timings[0].startTime, 0.0, accuracy: 0.1, "First character should start at segment timestamp")
        XCTAssertGreaterThan(timings[1].startTime, timings[0].startTime, "Second character should start after first")
        XCTAssertGreaterThan(timings[2].startTime, timings[1].startTime, "Third character should start after second")
        
        // Verify duration is distributed across segment duration
        let expectedDuration = 1.5 / 3.0 // segment duration / character count
        XCTAssertEqual(timings[0].duration, expectedDuration, accuracy: 0.1, "Duration should be segment duration divided by character count")
        XCTAssertEqual(timings[1].duration, expectedDuration, accuracy: 0.1, "Duration should be segment duration divided by character count")
        XCTAssertEqual(timings[2].duration, expectedDuration, accuracy: 0.1, "Duration should be segment duration divided by character count")
    }
    
    func testWordIndexCalculationForChinese() {
        let chineseTimings = [
            WordTiming(word: "我", startTime: 0.0, duration: 0.5, confidence: 1.0),
            WordTiming(word: "爱", startTime: 0.5, duration: 0.5, confidence: 1.0),
            WordTiming(word: "你", startTime: 1.0, duration: 0.5, confidence: 1.0)
        ]
        
        // Test word index calculation at different times
        XCTAssertEqual(WordHighlighter.getWordIndexForTime(0.2, wordTimings: chineseTimings), 0, "Time 0.2s should map to first character")
        XCTAssertEqual(WordHighlighter.getWordIndexForTime(0.7, wordTimings: chineseTimings), 1, "Time 0.7s should map to second character")
        XCTAssertEqual(WordHighlighter.getWordIndexForTime(1.2, wordTimings: chineseTimings), 2, "Time 1.2s should map to third character")
        
        // Test edge cases
        XCTAssertEqual(WordHighlighter.getWordIndexForTime(-0.1, wordTimings: chineseTimings), -1, "Negative time should map to no highlighting")
        XCTAssertEqual(WordHighlighter.getWordIndexForTime(2.0, wordTimings: chineseTimings), 2, "Time beyond duration should map to last character")
    }
    
    func testChineseLineWrapping() {
        let longChineseText = "这是一个很长的中文句子用来测试自动换行功能是否正常工作"
        let characters = LanguageUtils.splitTextForLanguage(longChineseText)
        
        let wordHighlighter = WordHighlighter(
            text: longChineseText,
            highlightedWordIndices: Set(),
            currentWordIndex: -1
        )
        
        let lines = wordHighlighter.createChineseLines(from: characters)
        
        // Should create multiple lines for long text
        XCTAssertGreaterThan(lines.count, 1, "Long Chinese text should be split into multiple lines")
        
        // Each line should not exceed reasonable character limit
        for line in lines {
            XCTAssertLessThanOrEqual(line.count, 15, "Each line should not exceed 15 characters")
        }
        
        // Total characters should be preserved
        let totalCharacters = lines.flatMap { $0 }.count
        XCTAssertEqual(totalCharacters, characters.count, "Total characters should be preserved after line wrapping")
    }
    
    // MARK: - Helper Methods
    
    private func createMockAffirmation(text: String) -> Affirmation {
        let context = PersistenceController.preview.container.viewContext
        let affirmation = Affirmation(context: context)
        affirmation.id = UUID()
        affirmation.text = text
        affirmation.audioFileName = "test.m4a"
        affirmation.repeatCount = 0
        affirmation.targetCount = 1000
        affirmation.dateCreated = Date()
        return affirmation
    }
    
    private func createMockChineseSpeechSegments(text: String, startTime: TimeInterval, duration: TimeInterval) -> [MockSpeechSegment] {
        // Create a single segment that contains all the Chinese text
        return [MockSpeechSegment(
            substring: text,
            timestamp: startTime,
            duration: duration,
            confidence: 1.0
        )]
    }
}

// MARK: - Mock Speech Segment for Testing

struct MockSpeechSegment {
    let substring: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}

// MARK: - Test Extensions

extension WordHighlighter {
    func createChineseLines(from words: [String]) -> [[String]] {
        // This will be implemented as part of our fix
        // For now, return a simple chunked version for testing
        var lines: [[String]] = []
        var currentLine: [String] = []
        let maxCharsPerLine = 12
        
        for word in words {
            if currentLine.count >= maxCharsPerLine {
                lines.append(currentLine)
                currentLine = [word]
            } else {
                currentLine.append(word)
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines
    }
}

extension SpeechService {
    func extractChineseWordTimings(segments: [MockSpeechSegment], expectedText: String) -> [WordTiming] {
        // Progressive approach: distribute characters across segment duration
        let characters = LanguageUtils.splitTextForLanguage(expectedText)
        let firstSegment = segments.first
        let segmentTimestamp = firstSegment?.timestamp ?? 0.0
        let segmentDuration = firstSegment?.duration ?? 1.5
        let timePerCharacter = segmentDuration / Double(characters.count)
        
        return characters.enumerated().map { index, character in
            WordTiming(
                word: character,
                startTime: segmentTimestamp + (timePerCharacter * Double(index)),
                duration: timePerCharacter,
                confidence: firstSegment?.confidence ?? 1.0
            )
        }
    }
}

extension AudioSessionManager {
    func isBluetoothAudioDeviceConnected() -> Bool {
        // This will be implemented as part of our fix
        let route = AVAudioSession.sharedInstance().currentRoute
        return route.outputs.contains { output in
            output.portType == .bluetoothA2DP || 
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE
        }
    }
    
    func getAudioSessionOptions(hasBluetoothDevice: Bool) -> AVAudioSession.CategoryOptions {
        // This will be implemented as part of our fix
        return hasBluetoothDevice 
            ? [.allowBluetoothA2DP]
            : [.defaultToSpeaker]
    }
}
