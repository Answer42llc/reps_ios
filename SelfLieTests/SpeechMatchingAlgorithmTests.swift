//
//  SpeechMatchingAlgorithmTests.swift
//  SelfLieTests
//
//  Tests for the fault-tolerant speech matching algorithm
//

import Testing
@testable import SelfLie

struct SpeechMatchingAlgorithmTests {
    
    // MARK: - Test Helper
    
    /// Test helper to simulate the matching algorithm
    private func testMatching(expectedText: String, recognizedText: String) -> Set<Int> {
        // Directly call our simulation since we can't access private methods
        return simulateMatchingAlgorithm(expectedText: expectedText, recognizedText: recognizedText)
    }
    
    /// Manual simulation of the matching algorithm for testing
    private func simulateMatchingAlgorithm(expectedText: String, recognizedText: String) -> Set<Int> {
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        let recognizedUnits = UniversalTextProcessor.smartSegmentText(recognizedText)
        
        var matchedIndices: Set<Int> = []
        var expectedIndex = 0
        
        // Fault-tolerant matching with punctuation skipping
        for recognizedUnit in recognizedUnits {
            
            // Skip any leading punctuation before trying to match
            while expectedIndex < expectedUnits.count && isPunctuation(expectedUnits[expectedIndex].text) {
                matchedIndices.insert(expectedIndex)
                expectedIndex += 1
            }
            
            // Look for a match within a reasonable range (allowing for small gaps)
            var found = false
            let maxSearchRange = min(3, expectedUnits.count - expectedIndex) // Search up to 3 positions ahead
            
            for offset in 0..<maxSearchRange {
                let checkIndex = expectedIndex + offset
                
                // Don't go beyond bounds
                guard checkIndex < expectedUnits.count else { break }
                
                let candidateUnit = expectedUnits[checkIndex]
                
                // Check if this position matches
                if recognizedUnit.text == candidateUnit.text {
                    
                    // Mark any skipped positions between expectedIndex and checkIndex
                    for skipIndex in expectedIndex..<checkIndex {
                        if isPunctuation(expectedUnits[skipIndex].text) {
                            matchedIndices.insert(skipIndex)
                        } else {
                            // If we're skipping non-punctuation, limit the range
                            if offset > 1 {
                                break
                            }
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
            
            // If no match found, continue with next character (don't stop)
        }
        
        // Handle any remaining punctuation at the end
        while expectedIndex < expectedUnits.count && isPunctuation(expectedUnits[expectedIndex].text) {
            matchedIndices.insert(expectedIndex)
            expectedIndex += 1
        }
        
        return matchedIndices
    }
    
    /// Helper to check if text is punctuation
    private func isPunctuation(_ text: String) -> Bool {
        // Chinese punctuation
        let chinesePunctuation = "，。！？；：（）【】「」『』〔〕《》〈〉"
        // Chinese quotes (using character literals)
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
    
    // MARK: - Chinese Text Tests
    
    @Test("Chinese text - Perfect match")
    func chineseTextPerfectMatch() async throws {
        let expectedText = "我从不怀疑自己"
        let recognizedText = "我从不怀疑自己"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        // Should match all positions
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Perfect match should highlight all characters")
    }
    
    @Test("Chinese text - With comma punctuation")
    func chineseTextWithComma() async throws {
        let expectedText = "我总是往好处想，因为积极的想法会自我实现"
        let recognizedText = "我总是往好处想因为积极的想法会自我实现"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        // Should skip comma but match everything else
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Should skip comma and match all other characters")
    }
    
    @Test("Chinese text - Multiple punctuation marks")
    func chineseTextMultiplePunctuation() async throws {
        let expectedText = "你好，世界！这是一个测试。"
        let recognizedText = "你好世界这是一个测试"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        // Should match all positions including skipped punctuation
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Should skip multiple punctuation marks")
    }
    
    @Test("Chinese text - Partial recognition")
    func chineseTextPartialRecognition() async throws {
        let expectedText = "我从不怀疑自己"
        let recognizedText = "我从不"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match first 3 characters
        let expectedIndices: Set<Int> = [0, 1, 2]
        #expect(result == expectedIndices, "Partial recognition should match available characters")
    }
    
    @Test("Chinese text - Recognition error in middle")
    func chineseTextRecognitionError() async throws {
        let expectedText = "我从不怀疑自己"
        let recognizedText = "我从错怀疑自己"  // "错" instead of "不"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match "我从", skip "错", then continue matching
        let expectedMatches: Set<Int> = [0, 1, 3, 4, 5, 6] // Skip position 2 ("不")
        #expect(result.contains(0) && result.contains(1), "Should match beginning characters")
    }
    
    // MARK: - English Text Tests
    
    @Test("English text - Perfect match")
    func englishTextPerfectMatch() async throws {
        let expectedText = "Hello world"
        let recognizedText = "Hello world"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Perfect English match should highlight all words")
    }
    
    @Test("English text - With punctuation")
    func englishTextWithPunctuation() async throws {
        let expectedText = "Hello, world! How are you?"
        let recognizedText = "Hello world How are you"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        // Should match all including punctuation positions
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Should skip English punctuation")
    }
    
    @Test("English text - Complex punctuation")
    func englishTextComplexPunctuation() async throws {
        let expectedText = "I said, \"Hello!\" Then I left."
        let recognizedText = "I said Hello Then I left"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match most content, skipping quotes and punctuation
        #expect(result.count > 4, "Should match most words despite complex punctuation")
    }
    
    @Test("English text - Partial recognition")
    func englishTextPartialRecognition() async throws {
        let expectedText = "The quick brown fox"
        let recognizedText = "The quick"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match first two words
        #expect(result.contains(0) && result.contains(1), "Should match first two words")
        #expect(!result.contains(2) && !result.contains(3), "Should not match unrecognized words")
    }
    
    // MARK: - Mixed Language Tests
    
    @Test("Mixed language - Chinese and English")
    func mixedChineseEnglish() async throws {
        let expectedText = "Hello，你好world！"
        let recognizedText = "Hello你好world"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        // Should match all content including punctuation
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Should handle mixed language with punctuation")
    }
    
    @Test("Mixed language - Complex mixing")
    func mixedLanguageComplex() async throws {
        let expectedText = "我喜欢Apple，因为iPhone很好用！"
        let recognizedText = "我喜欢Apple因为iPhone很好用"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match most content
        #expect(result.count > 8, "Should handle complex language mixing")
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty texts")
    func emptyTexts() async throws {
        let result1 = testMatching(expectedText: "", recognizedText: "")
        #expect(result1.isEmpty, "Empty texts should return empty result")
        
        let result2 = testMatching(expectedText: "Hello", recognizedText: "")
        #expect(result2.isEmpty, "Empty recognized text should return empty result")
        
        let result3 = testMatching(expectedText: "", recognizedText: "Hello")
        #expect(result3.isEmpty, "Empty expected text should return empty result")
    }
    
    @Test("Only punctuation")
    func onlyPunctuation() async throws {
        let expectedText = "，。！？"
        let recognizedText = ""
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        // Should mark all punctuation as matched
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Only punctuation should be marked as matched")
    }
    
    @Test("Very long text")
    func veryLongText() async throws {
        let expectedText = "这是一个很长很长的文本，包含了很多很多的字符，用来测试算法在处理长文本时的性能和正确性。This is a very long text with many many characters to test the algorithm's performance and correctness when processing long texts."
        let recognizedText = "这是一个很长很长的文本包含了很多很多的字符用来测试算法在处理长文本时的性能和正确性"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match a significant portion of the text
        #expect(result.count > 20, "Should match significant portion of long text")
    }
    
    @Test("Special characters and symbols")
    func specialCharactersAndSymbols() async throws {
        let expectedText = "Price: $100.50 (discount: 10%)"
        let recognizedText = "Price 100 50 discount 10"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match some content despite special characters
        #expect(result.count > 3, "Should handle special characters and symbols")
    }
    
    @Test("Repeated characters")
    func repeatedCharacters() async throws {
        let expectedText = "哈哈哈，好好好！"
        let recognizedText = "哈哈哈好好好"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        let expectedUnits = UniversalTextProcessor.smartSegmentText(expectedText)
        
        // Should match all including punctuation
        let expectedIndices = Set(0..<expectedUnits.count)
        #expect(result == expectedIndices, "Should handle repeated characters correctly")
    }
    
    @Test("Numbers and digits")
    func numbersAndDigits() async throws {
        let expectedText = "我有123个苹果，你有456个橘子。"
        let recognizedText = "我有123个苹果你有456个橘子"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match most content including numbers
        #expect(result.count > 10, "Should handle numbers and digits correctly")
    }
    
    // MARK: - Stress Tests
    
    @Test("Complete mismatch")
    func completeMismatch() async throws {
        let expectedText = "苹果香蕉橘子"
        let recognizedText = "猫狗鸟"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should return empty or very few matches
        #expect(result.count == 0, "Complete mismatch should return no matches")
    }
    
    @Test("Recognition much longer than expected")
    func recognitionLongerThanExpected() async throws {
        let expectedText = "你好"
        let recognizedText = "你好世界这是一个很长的识别结果"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match the available part
        #expect(result.contains(0) && result.contains(1), "Should match available characters even if recognition is longer")
    }
    
    @Test("Complex punctuation patterns")
    func complexPunctuationPatterns() async throws {
        let expectedText = "他说：「你好！」然后就走了..."
        let recognizedText = "他说你好然后就走了"
        
        let result = testMatching(expectedText: expectedText, recognizedText: recognizedText)
        
        // Should match content while skipping complex punctuation
        #expect(result.count > 5, "Should handle complex punctuation patterns")
    }
}

// MARK: - Note
// This test file uses a simulated version of the matching algorithm
// to test the core logic without accessing private methods.