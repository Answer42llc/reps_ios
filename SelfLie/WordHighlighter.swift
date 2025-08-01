import SwiftUI

struct WordHighlighter: View {
    let text: String
    let highlightedWordIndices: Set<Int>
    let currentWordIndex: Int
    
    @State private var words: [String] = []
    
    var body: some View {
        // Issue 3 Fix: Use LanguageUtils for proper text splitting (words for English, characters for Chinese)
        let wordArray = LanguageUtils.splitTextForLanguage(text)
        
        return VStack(alignment: .leading, spacing: 0) {
            wrappedText(words: wordArray)
        }
        .animation(.easeInOut(duration: 0.3), value: highlightedWordIndices)
        .animation(.easeInOut(duration: 0.3), value: currentWordIndex)
    }
    
    private func wrappedText(words: [String]) -> some View {
        let lines = createLines(from: words)
        
        return VStack(alignment: .center, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, lineWords in
                // Issue 3 Fix: Use different spacing for Chinese vs English
                let spacing: CGFloat = LanguageUtils.isChineseText(text) ? 0 : 4
                HStack(spacing: spacing) {
                    ForEach(Array(lineWords.enumerated()), id: \.offset) { wordIndexInLine, word in
                        let globalWordIndex = calculateGlobalIndex(lineIndex: lineIndex, wordIndexInLine: wordIndexInLine, lines: lines)
                        
                        Text(word)
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(getWordColor(for: globalWordIndex))
                            .animation(.easeInOut(duration: 0.2), value: getWordColor(for: globalWordIndex))
                    }
                }
            }
        }
    }
    
    private func createLines(from words: [String]) -> [[String]] {
        // Issue 3 Fix: Handle Chinese and English text differently for line wrapping
        if LanguageUtils.isChineseText(text) {
            return createChineseLines(from: words)
        } else {
            return createEnglishLines(from: words)
        }
    }
    
    /// Create lines for Chinese text (character-based, simpler wrapping)
    func createChineseLines(from words: [String]) -> [[String]] {
        var lines: [[String]] = []
        var currentLine: [String] = []
        let maxCharsPerLine = LanguageUtils.getRecommendedCharsPerLine(for: text)
        
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
    
    /// Create lines for English text (original logic with word-based measurement)
    private func createEnglishLines(from words: [String]) -> [[String]] {
        var lineWords: [String] = []
        var lines: [[String]] = []
        let maxLineWidth: CGFloat = 280 // Approximate max width for mobile
        let font = UIFont.preferredFont(forTextStyle: .title1) // Match SwiftUI .title font
        
        for word in words {
            // Create test line with new word
            let testLine = lineWords + [word]
            let testText = testLine.joined(separator: " ")
            
            // Calculate text width
            let attributes = [NSAttributedString.Key.font: font]
            let textSize = (testText as NSString).size(withAttributes: attributes)
            
            if textSize.width > maxLineWidth && !lineWords.isEmpty {
                // Current line would be too wide, start new line
                lines.append(lineWords)
                lineWords = [word]
            } else {
                // Add word to current line
                lineWords.append(word)
            }
        }
        
        if !lineWords.isEmpty {
            lines.append(lineWords)
        }
        
        return lines
    }
    
    private func calculateGlobalIndex(lineIndex: Int, wordIndexInLine: Int, lines: [[String]]) -> Int {
        var globalIndex = 0
        
        // Add words from previous lines
        for i in 0..<lineIndex {
            globalIndex += lines[i].count
        }
        
        // Add current word index in line
        globalIndex += wordIndexInLine
        
        return globalIndex
    }
    
    private func getWordColor(for wordIndex: Int) -> Color {
        if highlightedWordIndices.contains(wordIndex) || wordIndex <= currentWordIndex {
            return .purple
        } else {
            return .primary
        }
    }
}

// Helper extension for precise timing calculations
extension WordHighlighter {
    
    /// Get word index for current playback time using precise WordTiming data
    static func getWordIndexForTime(_ time: TimeInterval, wordTimings: [WordTiming]) -> Int {
        guard !wordTimings.isEmpty else { 
            print("🎯 [WordHighlighter] getWordIndexForTime: No word timings available")
            return -1 
        }
        
        // Find the word that should be currently highlighted
        for (index, wordTiming) in wordTimings.enumerated() {
            // Check if current time is within this word's time range
            if time >= wordTiming.startTime && time < wordTiming.endTime {
                print("🎯 [WordHighlighter] Time \(String(format: "%.2f", time))s -> word index \(index) ('\(wordTiming.word)')")
                return index
            }
            // If time is before this word starts
            else if time < wordTiming.startTime {
                // If this is the first word and time is before it starts, no highlighting
                if index == 0 {
                    print("🎯 [WordHighlighter] Time \(String(format: "%.2f", time))s -> no highlighting (before first word)")
                    return -1
                }
                // Otherwise, highlight the previous word
                let result = index - 1
                print("🎯 [WordHighlighter] Time \(String(format: "%.2f", time))s -> word index \(result) (before '\(wordTiming.word)')")
                return result
            }
        }
        
        // If time is after all words, highlight the last word
        let result = wordTimings.count - 1
        print("🎯 [WordHighlighter] Time \(String(format: "%.2f", time))s -> final word index \(result)")
        return result
    }
}

#Preview {
    VStack(spacing: 20) {
        WordHighlighter(
            text: "I never compare to others, because that make no sense",
            highlightedWordIndices: Set([0, 1, 2]),
            currentWordIndex: 2
        )
        
        WordHighlighter(
            text: "I never compare to others, because that make no sense",
            highlightedWordIndices: Set([0, 1, 2, 3, 4, 5]),
            currentWordIndex: 5
        )
    }
    .padding()
}
