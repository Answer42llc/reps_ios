import SwiftUI

/// Native SwiftUI text highlighter using AttributedString
/// Replaces WordHighlighter with Apple's built-in multi-language support
struct NativeTextHighlighter: View {
    let text: String
    let highlightedWordIndices: Set<Int>
    let currentWordIndex: Int
    
    var body: some View {
        Text(createAttributedText())
            .font(.title)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
    }
    
    /// Creates AttributedString with highlighted words using Apple's universal text processing
    private func createAttributedText() -> AttributedString {
        // Use UniversalTextProcessor to get proper text segmentation for any language
        let textUnits = UniversalTextProcessor.smartSegmentText(text)
        
        var attributedString = AttributedString()
        
        for (index, unit) in textUnits.enumerated() {
            var unitAttributedString = AttributedString(unit.originalText)
            
            // Apply highlighting based on highlightedWordIndices only (unified logic)
            if highlightedWordIndices.contains(index) {
                unitAttributedString.foregroundColor = .purple
            } else {
                unitAttributedString.foregroundColor = .primary
            }
            
            // Add the unit to the attributed string
            attributedString.append(unitAttributedString)
            
            // Add space between units for non-CJK languages
            if !UniversalTextProcessor.containsCJKCharacters(text) && index < textUnits.count - 1 {
                attributedString.append(AttributedString(" "))
            }
        }
        
        return attributedString
    }
}

// MARK: - Helper extension for precise timing calculations (same as WordHighlighter)
extension NativeTextHighlighter {
    
    /// Get word index for current playback time using precise WordTiming data
    static func getWordIndexForTime(_ time: TimeInterval, wordTimings: [WordTiming]) -> Int {
        guard !wordTimings.isEmpty else { 
            print("🎯 [NativeTextHighlighter] getWordIndexForTime: No word timings available")
            return -1 
        }
        
        // Find the word that should be currently highlighted
        for (index, wordTiming) in wordTimings.enumerated() {
            // Check if current time is within this word's time range
            if time >= wordTiming.startTime && time < wordTiming.endTime {
                print("🎯 [NativeTextHighlighter] Time \(String(format: "%.2f", time))s -> word index \(index) ('\(wordTiming.word)')")
                return index
            }
            // If time is before this word starts
            else if time < wordTiming.startTime {
                // If this is the first word and time is before it starts, no highlighting
                if index == 0 {
                    print("🎯 [NativeTextHighlighter] Time \(String(format: "%.2f", time))s -> no highlighting (before first word)")
                    return -1
                }
                // Otherwise, highlight the previous word
                let result = index - 1
                print("🎯 [NativeTextHighlighter] Time \(String(format: "%.2f", time))s -> word index \(result) (before '\(wordTiming.word)')")
                return result
            }
        }
        
        // If time is after all words, highlight the last word
        let result = wordTimings.count - 1
        print("🎯 [NativeTextHighlighter] Time \(String(format: "%.2f", time))s -> final word index \(result)")
        return result
    }
}

#Preview {
    VStack(spacing: 20) {
        NativeTextHighlighter(
            text: "I never compare to others, because that make no sense",
            highlightedWordIndices: Set([0, 1, 2]),
            currentWordIndex: 2
        )
        
        NativeTextHighlighter(
            text: "我爱你",
            highlightedWordIndices: Set([0, 1]),
            currentWordIndex: 1
        )
        
        NativeTextHighlighter(
            text: "Mucho gusto mi amor y tu eres",
            highlightedWordIndices: Set([0, 1, 2]),
            currentWordIndex: 2
        )
    }
    .padding()
}
