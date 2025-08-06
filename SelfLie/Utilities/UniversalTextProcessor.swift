import Foundation

/// Universal text processing utility using Apple's NSString.enumerateSubstrings
/// Automatically handles all languages without manual language detection
/// Replaces LanguageUtils with system-level multi-language support
struct UniversalTextProcessor {
    
    /// Text unit representation for universal text processing
    struct TextUnit {
        let originalText: String  // Original text for display (preserves capitalization)
        let text: String         // Normalized text for matching (lowercased)
        let range: NSRange
        let index: Int
    }
    
    /// Segments text into appropriate units using Apple's language-aware APIs
    /// Automatically handles Chinese characters, English words, Arabic RTL, Japanese compounds, etc.
    /// - Parameter text: The text to segment
    /// - Returns: Array of text units (characters for CJK, words for others)
    static func segmentText(_ text: String) -> [TextUnit] {
        var textUnits: [TextUnit] = []
        let nsString = text as NSString
        
        // Use Apple's language-aware text enumeration
        // This automatically handles all languages without manual detection
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byComposedCharacterSequences, .localized]
        ) { substring, range, _, _ in
            guard let substring = substring else { return }
            
            // Skip whitespace-only units
            if !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let textUnit = TextUnit(
                    originalText: substring,       // Preserve original case for display
                    text: substring.lowercased(), // Normalize for matching
                    range: range,
                    index: textUnits.count
                )
                textUnits.append(textUnit)
            }
        }
        
        print("🌍 [UniversalTextProcessor] Segmented '\(text)' into \(textUnits.count) units")
        for (index, unit) in textUnits.enumerated() {
            print("   Unit \(index): '\(unit.originalText)' (normalized: '\(unit.text)') at range \(unit.range)")
        }
        
        return textUnits
    }
    
    /// Alternative segmentation for word-level processing (for languages that support it)
    /// Automatically detects word boundaries for all supported languages
    /// - Parameter text: The text to segment
    /// - Returns: Array of word-level text units
    static func segmentTextByWords(_ text: String) -> [TextUnit] {
        var textUnits: [TextUnit] = []
        let nsString = text as NSString
        
        // Use word-level enumeration with localization
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byWords, .localized]
        ) { substring, range, _, _ in
            guard let substring = substring else { return }
            
            let textUnit = TextUnit(
                originalText: substring,       // Preserve original case for display
                text: substring.lowercased(), // Normalize for matching
                range: range,
                index: textUnits.count
            )
            textUnits.append(textUnit)
        }
        
        print("🔤 [UniversalTextProcessor] Word-segmented '\(text)' into \(textUnits.count) words")
        return textUnits
    }
    
    /// Intelligently chooses the best segmentation method based on text characteristics
    /// Uses system-level language detection to determine optimal processing
    /// - Parameter text: The text to process
    /// - Returns: Array of appropriately segmented text units
    static func smartSegmentText(_ text: String) -> [TextUnit] {
        // Determine the best segmentation approach based on language characteristics
        // For simplicity and reliability, use CJK detection approach
        if containsCJKCharacters(text) {
            // CJK languages work better with character-level segmentation
            print("🔍 [UniversalTextProcessor] Using character-level segmentation for CJK text: '\(text)'")
            return segmentText(text)
        } else {
            // Non-CJK languages work better with word-level segmentation
            print("🔍 [UniversalTextProcessor] Using word-level segmentation for non-CJK text: '\(text)'")
            return segmentTextByWords(text)
        }
    }
    
    /// Convert TextUnit array to simple string array for display
    /// - Parameter textUnits: Array of TextUnit objects
    /// - Returns: Array of original text strings (preserves capitalization)
    static func extractTexts(from textUnits: [TextUnit]) -> [String] {
        return textUnits.map { $0.originalText }
    }
    
    /// Find matching text units between expected and recognized text
    /// Uses fuzzy matching to handle speech recognition variations
    /// - Parameters:
    ///   - expectedUnits: The expected text units
    ///   - recognizedUnits: The recognized text units  
    ///   - similarityThreshold: Minimum similarity score for matching (0.0-1.0)
    /// - Returns: Set of indices of matched expected units
    static func findMatchingUnits(
        expectedUnits: [TextUnit],
        recognizedUnits: [TextUnit],
        similarityThreshold: Float = 0.7
    ) -> Set<Int> {
        var matchedIndices: Set<Int> = []
        
        for (expectedIndex, expectedUnit) in expectedUnits.enumerated() {
            let expectedText = expectedUnit.text  // Already normalized (lowercased)
            
            for recognizedUnit in recognizedUnits {
                let recognizedText = recognizedUnit.text  // Already normalized (lowercased)
                
                // Check for exact match or containment
                if recognizedText == expectedText || 
                   recognizedText.contains(expectedText) || 
                   expectedText.contains(recognizedText) {
                    matchedIndices.insert(expectedIndex)
                    break
                }
                
                // Check for fuzzy similarity
                let similarity = calculateSimilarity(expectedText, recognizedText)
                if similarity >= similarityThreshold {
                    matchedIndices.insert(expectedIndex)
                    break
                }
            }
        }
        
        print("🎯 [UniversalTextProcessor] Matched \(matchedIndices.count)/\(expectedUnits.count) units")
        return matchedIndices
    }
    
    /// Calculate text similarity using Levenshtein distance
    /// - Parameters:
    ///   - text1: First text to compare
    ///   - text2: Second text to compare
    /// - Returns: Similarity score (0.0-1.0)
    private static func calculateSimilarity(_ text1: String, _ text2: String) -> Float {
        let distance = levenshteinDistance(text1, text2)
        let maxLength = max(text1.count, text2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - Float(distance) / Float(maxLength)
    }
    
    /// Calculate Levenshtein distance between two strings
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: Edit distance
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count { matrix[i][0] = i }
        for j in 0...s2Count { matrix[0][j] = j }
        
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
}

// MARK: - Backward Compatibility Extensions
extension UniversalTextProcessor {
    
    /// Legacy compatibility: Check if text contains CJK characters
    /// - Parameter text: Text to analyze
    /// - Returns: True if text contains Chinese, Japanese, or Korean characters
    static func containsCJKCharacters(_ text: String) -> Bool {
        return text.range(of: "[\\u4e00-\\u9fff\\u3040-\\u309f\\u30a0-\\u30ff\\uac00-\\ud7af]", 
                         options: .regularExpression) != nil
    }
    
    /// Legacy compatibility: Get recommended units per line for display
    /// - Parameter text: Text to analyze
    /// - Returns: Recommended number of units per line
    static func getRecommendedUnitsPerLine(for text: String) -> Int {
        if containsCJKCharacters(text) {
            return 12 // CJK characters are wider
        } else {
            return 8 // Western languages
        }
    }
}

// MARK: - Debug and Testing Extensions
#if DEBUG
extension UniversalTextProcessor {
    
    /// Test the universal text processor with various languages
    static func runTests() {
        print("🧪 [UniversalTextProcessor] Running multi-language tests...")
        
        let testCases = [
            ("Hello World", "English"),
            ("我爱你", "Chinese"),
            ("こんにちは世界", "Japanese"),
            ("안녕하세요 세계", "Korean"),
            ("مرحبا بالعالم", "Arabic"),
            ("שלום עולם", "Hebrew"),
            ("Hola Mundo", "Spanish"),
            ("Hello 你好 مرحبا", "Mixed Languages")
        ]
        
        for (text, language) in testCases {
            print("\n--- Testing \(language): '\(text)' ---")
            let units = smartSegmentText(text)
            let texts = extractTexts(from: units)
            print("Result: \(texts)")
        }
        
        print("\n✅ [UniversalTextProcessor] Multi-language tests completed")
    }
}
#endif