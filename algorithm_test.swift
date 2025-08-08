#!/usr/bin/env swift

import Foundation

// Simplified UniversalTextProcessor for testing
struct TestTextProcessor {
    struct TextUnit {
        let text: String
        let originalText: String
    }
    
    static func smartSegmentText(_ text: String) -> [TextUnit] {
        // Simple character-based segmentation for testing
        return text.map { char in
            TextUnit(text: String(char).lowercased(), originalText: String(char))
        }
    }
}

// Test algorithm implementation
func isPunctuation(_ text: String) -> Bool {
    let chinesePunctuation = "，。！？；：（）【】「」『』〔〕《》〈〉"
    let leftChineseQuote = "\u{201C}"  // "
    let rightChineseQuote = "\u{201D}" // "
    let leftChineseSingleQuote = "\u{2018}"  // '
    let rightChineseSingleQuote = "\u{2019}" // '
    let chineseQuotes = leftChineseQuote + rightChineseQuote + leftChineseSingleQuote + rightChineseSingleQuote
    let englishPunctuation = ",.!?;:\"'()[]{}"
    let commonSymbols = "-_/\\|@#$%^&*+=<>~`"
    
    let allPunctuation = chinesePunctuation + chineseQuotes + englishPunctuation + commonSymbols
    
    return text.count == 1 && allPunctuation.contains(text)
}

func calculateHighlightIndices(expectedText: String, recognizedText: String) -> Set<Int> {
    let expectedUnits = TestTextProcessor.smartSegmentText(expectedText)
    let recognizedUnits = TestTextProcessor.smartSegmentText(recognizedText)
    
    var matchedIndices: Set<Int> = []
    var expectedIndex = 0
    
    print("🎯 Expected: \(expectedUnits.map { $0.originalText })")
    print("🎯 Recognized: \(recognizedUnits.map { $0.originalText })")
    
    // Fault-tolerant matching with punctuation skipping
    for (recognizedIdx, recognizedUnit) in recognizedUnits.enumerated() {
        print("🔍 Processing recognized[\(recognizedIdx)]: '\(recognizedUnit.originalText)'")
        
        // Skip any leading punctuation before trying to match
        while expectedIndex < expectedUnits.count && isPunctuation(expectedUnits[expectedIndex].text) {
            print("🔤 Skipping punctuation at expected[\(expectedIndex)]: '\(expectedUnits[expectedIndex].originalText)'")
            matchedIndices.insert(expectedIndex)
            expectedIndex += 1
        }
        
        // Look for a match within a reasonable range (allowing for small gaps)
        var found = false
        let maxSearchRange = min(3, expectedUnits.count - expectedIndex)
        
        for offset in 0..<maxSearchRange {
            let checkIndex = expectedIndex + offset
            
            guard checkIndex < expectedUnits.count else { break }
            
            let candidateUnit = expectedUnits[checkIndex]
            
            // Check if this position matches
            if recognizedUnit.text == candidateUnit.text {
                print("🎯 Found match at [\(checkIndex)] with offset \(offset): '\(recognizedUnit.originalText)' ✓")
                
                // Mark any skipped positions between expectedIndex and checkIndex
                for skipIndex in expectedIndex..<checkIndex {
                    if isPunctuation(expectedUnits[skipIndex].text) {
                        print("🔤 Marking skipped punctuation at [\(skipIndex)]: '\(expectedUnits[skipIndex].originalText)'")
                        matchedIndices.insert(skipIndex)
                    } else {
                        if offset > 1 {
                            print("🔍 Skipping non-punctuation at [\(skipIndex)]: '\(expectedUnits[skipIndex].originalText)' (offset too large)")
                            break
                        }
                        print("🔤 Allowing small skip of non-punctuation at [\(skipIndex)]: '\(expectedUnits[skipIndex].originalText)'")
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
            print("🔍 No match found for '\(recognizedUnit.originalText)' within range, continuing with next recognized character")
        }
    }
    
    // Handle any remaining punctuation at the end
    while expectedIndex < expectedUnits.count && isPunctuation(expectedUnits[expectedIndex].text) {
        print("🔤 Final punctuation at [\(expectedIndex)]: '\(expectedUnits[expectedIndex].originalText)'")
        matchedIndices.insert(expectedIndex)
        expectedIndex += 1
    }
    
    print("🎯 Final matched indices: \(matchedIndices.sorted())")
    return matchedIndices
}

// Test cases
struct TestCase {
    let name: String
    let expectedText: String
    let recognizedText: String
    let expectedResult: String
}

let testCases = [
    // Chinese text tests
    TestCase(name: "Chinese Perfect Match", 
             expectedText: "我从不怀疑自己", 
             recognizedText: "我从不怀疑自己", 
             expectedResult: "All characters should match"),
    
    TestCase(name: "Chinese With Comma", 
             expectedText: "我总是往好处想，因为积极", 
             recognizedText: "我总是往好处想因为积极", 
             expectedResult: "Should skip comma and match all"),
    
    TestCase(name: "Chinese Multiple Punctuation", 
             expectedText: "你好，世界！这是测试。", 
             recognizedText: "你好世界这是测试", 
             expectedResult: "Should skip all punctuation"),
    
    TestCase(name: "Chinese Partial Recognition", 
             expectedText: "我从不怀疑自己", 
             recognizedText: "我从不", 
             expectedResult: "Should match first 3 characters"),
    
    // English text tests
    TestCase(name: "English Perfect Match", 
             expectedText: "hello world", 
             recognizedText: "hello world", 
             expectedResult: "All characters should match"),
    
    TestCase(name: "English With Punctuation", 
             expectedText: "hello, world!", 
             recognizedText: "hello world", 
             expectedResult: "Should skip punctuation"),
    
    // Mixed language tests
    TestCase(name: "Mixed Chinese English", 
             expectedText: "hello，你好world！", 
             recognizedText: "hello你好world", 
             expectedResult: "Should handle mixed language"),
    
    // Edge cases
    TestCase(name: "Empty Texts", 
             expectedText: "", 
             recognizedText: "", 
             expectedResult: "Should return empty"),
    
    TestCase(name: "Only Punctuation", 
             expectedText: "，。！？", 
             recognizedText: "", 
             expectedResult: "Should mark all punctuation"),
]

// Run tests
print("🧪 Running Speech Matching Algorithm Tests\n")
print(String(repeating: "=", count: 60))

for (index, testCase) in testCases.enumerated() {
    print("\n🧪 Test \(index + 1): \(testCase.name)")
    print("Expected: '\(testCase.expectedText)'")
    print("Recognized: '\(testCase.recognizedText)'")
    print("Expected Result: \(testCase.expectedResult)")
    print(String(repeating: "-", count: 50))
    
    let result = calculateHighlightIndices(expectedText: testCase.expectedText, recognizedText: testCase.recognizedText)
    let expectedUnits = TestTextProcessor.smartSegmentText(testCase.expectedText)
    
    print("\n✅ Result: Matched \(result.count) out of \(expectedUnits.count) positions")
    if !result.isEmpty {
        let matchedChars = result.sorted().compactMap { index in
            index < expectedUnits.count ? expectedUnits[index].originalText : nil
        }.joined()
        print("✅ Matched characters: '\(matchedChars)'")
    }
    print(String(repeating: "=", count: 60))
}

print("\n🎉 All tests completed!")