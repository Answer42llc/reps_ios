import Foundation

struct TextSimilarity {
    
    // MARK: - Main Similarity Function
    static func calculateSimilarity(expected: String, recognized: String) -> Float {
        let expectedCleaned = cleanText(expected)
        let recognizedCleaned = cleanText(recognized)
        
        guard !expectedCleaned.isEmpty && !recognizedCleaned.isEmpty else { return 0.0 }
        
        // Use weighted combination of different similarity measures
        let jaccardScore = jaccardSimilarity(expectedCleaned, recognizedCleaned)
        let levenshteinScore = levenshteinSimilarity(expectedCleaned, recognizedCleaned)
        let wordOrderScore = wordOrderSimilarity(expectedCleaned, recognizedCleaned)
        
        // Weighted average (adjust weights based on importance)
        let finalScore = (jaccardScore * 0.4) + (levenshteinScore * 0.4) + (wordOrderScore * 0.2)
        
        return finalScore
    }
    
    // MARK: - Text Preprocessing
    private static func cleanText(_ text: String) -> String {
        return text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}\\s]", with: "", options: .regularExpression)
    }
    
    // MARK: - Similarity Algorithms
    
    /// Method 1: Jaccard Similarity (Word Set Overlap)
    private static func jaccardSimilarity(_ text1: String, _ text2: String) -> Float {
        let words1 = Set(text1.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let words2 = Set(text2.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        guard !union.isEmpty else { return 0.0 }
        
        return Float(intersection.count) / Float(union.count)
    }
    
    /// Method 2: Levenshtein Distance (Edit Distance)
    private static func levenshteinSimilarity(_ text1: String, _ text2: String) -> Float {
        let distance = levenshteinDistance(text1, text2)
        let maxLength = max(text1.count, text2.count)
        
        guard maxLength > 0 else { return 1.0 }
        
        return 1.0 - (Float(distance) / Float(maxLength))
    }
    
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[a.count][b.count]
    }
    
    /// Method 3: Word Order Similarity (Considers sequence)
    private static func wordOrderSimilarity(_ text1: String, _ text2: String) -> Float {
        let words1 = text1.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let words2 = text2.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }
        
        let minLength = min(words1.count, words2.count)
        let maxLength = max(words1.count, words2.count)
        
        var matches = 0
        for i in 0..<minLength {
            if words1[i] == words2[i] {
                matches += 1
            }
        }
        
        // Penalty for different lengths
        let lengthPenalty = Float(maxLength - minLength) / Float(maxLength)
        let orderScore = Float(matches) / Float(minLength)
        
        return orderScore * (1.0 - lengthPenalty)
    }
    
    // MARK: - Language-Specific Similarity (for Chinese, etc.)
    static func calculateChineseSimilarity(expected: String, recognized: String) -> Float {
        // For Chinese text, character-level comparison might be more appropriate
        let expectedChars = Array(expected.replacingOccurrences(of: " ", with: ""))
        let recognizedChars = Array(recognized.replacingOccurrences(of: " ", with: ""))
        
        let expectedSet = Set(expectedChars)
        let recognizedSet = Set(recognizedChars)
        
        let intersection = expectedSet.intersection(recognizedSet)
        let union = expectedSet.union(recognizedSet)
        
        guard !union.isEmpty else { return 0.0 }
        
        return Float(intersection.count) / Float(union.count)
    }
    
    // MARK: - Phonetic Similarity (for speech recognition)
    static func calculatePhoneticSimilarity(expected: String, recognized: String) -> Float {
        // Simple phonetic matching - could be enhanced with Soundex or Metaphone
        let expectedPhonetic = phoneticCode(expected)
        let recognizedPhonetic = phoneticCode(recognized)
        
        return expectedPhonetic == recognizedPhonetic ? 1.0 : 0.0
    }
    
    private static func phoneticCode(_ text: String) -> String {
        // Simplified phonetic encoding
        return text
            .lowercased()
            .replacingOccurrences(of: "ph", with: "f")
            .replacingOccurrences(of: "ck", with: "k")
            .replacingOccurrences(of: "c", with: "k")
            .replacingOccurrences(of: "[aeiou]", with: "", options: .regularExpression)
    }
}

// MARK: - Usage Examples
extension TextSimilarity {
    static func debugSimilarity(expected: String, recognized: String) {
        print("=== Text Similarity Analysis ===")
        print("Expected: '\(expected)'")
        print("Recognized: '\(recognized)'")
        print("Jaccard: \(jaccardSimilarity(cleanText(expected), cleanText(recognized)))")
        print("Levenshtein: \(levenshteinSimilarity(cleanText(expected), cleanText(recognized)))")
        print("Word Order: \(wordOrderSimilarity(cleanText(expected), cleanText(recognized)))")
        print("Final Score: \(calculateSimilarity(expected: expected, recognized: recognized))")
        print("Chinese Score: \(calculateChineseSimilarity(expected: expected, recognized: recognized))")
    }
}