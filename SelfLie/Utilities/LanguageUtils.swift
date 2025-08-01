import Foundation
import UIKit

/// Utility class for language detection and text processing
/// Supports both English (word-based) and Chinese (character-based) text handling
struct LanguageUtils {
    
    /// Detects if the given text contains Chinese characters
    /// - Parameter text: The text to analyze
    /// - Returns: True if Chinese characters are detected, false otherwise
    static func isChineseText(_ text: String) -> Bool {
        // Check for Chinese characters in the Unicode ranges:
        // U+4E00-U+9FFF: CJK Unified Ideographs (main Chinese characters)
        let chineseRange = text.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression)
        return chineseRange != nil
    }
    
    /// Splits text into appropriate units based on language detection
    /// - Chinese text: Split into individual characters
    /// - English text: Split into words by whitespace
    /// - Parameter text: The text to split
    /// - Returns: Array of text units (characters for Chinese, words for English)
    static func splitTextForLanguage(_ text: String) -> [String] {
        if isChineseText(text) {
            // For Chinese text, split into individual characters (excluding whitespace)
            return text.compactMap { char in
                char.isWhitespace ? nil : String(char)
            }
        } else {
            // For English text, split by whitespace into words
            return text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
        }
    }
    
    /// Gets appropriate character count per line based on language
    /// - Parameter text: The text to analyze
    /// - Returns: Recommended number of units per line
    static func getRecommendedCharsPerLine(for text: String) -> Int {
        if isChineseText(text) {
            // Chinese characters are wider, fewer per line
            return 12
        } else {
            // English words vary in length, use flexible approach
            return 8 // words per line
        }
    }
    
    /// Estimates the visual width of text for line wrapping
    /// - Parameters:
    ///   - text: The text to measure
    ///   - fontSize: The font size being used
    /// - Returns: Estimated width in points
    static func estimateTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        if isChineseText(text) {
            // Chinese characters have roughly uniform width
            let characterCount = text.filter { !$0.isWhitespace }.count
            let averageChineseCharWidth = fontSize * 1.2 // Approximate ratio
            return CGFloat(characterCount) * averageChineseCharWidth
        } else {
            // English text width varies more, use system measurement
            let nsString = text as NSString
            let font = UIFont.systemFont(ofSize: fontSize)
            let attributes = [NSAttributedString.Key.font: font]
            return nsString.size(withAttributes: attributes).width
        }
    }
    
    /// Debug method to analyze text characteristics
    /// - Parameter text: The text to analyze
    /// - Returns: Dictionary with analysis results
    static func analyzeText(_ text: String) -> [String: Any] {
        let isChinese = isChineseText(text)
        let units = splitTextForLanguage(text)
        let charsPerLine = getRecommendedCharsPerLine(for: text)
        
        return [
            "isChinese": isChinese,
            "originalLength": text.count,
            "unitCount": units.count,
            "units": units,
            "recommendedCharsPerLine": charsPerLine,
            "estimatedLines": (units.count + charsPerLine - 1) / charsPerLine
        ]
    }
}

// MARK: - Testing Extensions
#if DEBUG
extension LanguageUtils {
    /// Test helper to validate Chinese text detection
    static func testChineseDetection() {
        let testCases = [
            ("我爱你", true),
            ("Hello World", false),
            ("Hello 你好", true),
            ("", false),
            ("   ", false),
            ("123 你好 456", true),
            ("English only text", false)
        ]
        
        for (text, expected) in testCases {
            let result = isChineseText(text)
            print("Text: '\(text)' -> Expected: \(expected), Got: \(result), ✅: \(result == expected)")
        }
    }
    
    /// Test helper to validate text splitting
    static func testTextSplitting() {
        let testCases = [
            ("我爱你", ["我", "爱", "你"]),
            ("Hello World", ["Hello", "World"]),
            ("我 爱 你", ["我", "爱", "你"]),
            ("", [])
        ]
        
        for (text, expected) in testCases {
            let result = splitTextForLanguage(text)
            let matches = result == expected
            print("Text: '\(text)' -> Expected: \(expected), Got: \(result), ✅: \(matches)")
        }
    }
}
#endif