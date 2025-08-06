# Phase 2: Integrate SpeechAnalyzer API and Architecture Simplification

## Phase 2 Tasks

### 1. Integrate SpeechAnalyzer API for More Accurate Real-time Highlighting (iOS 18+)
- Replace `SFSpeechRecognizer` with the new `SpeechAnalyzer` API
- Leverage `CMTimeRange` for precise word-level timing synchronization
- Support progressive display with volatile and finalized results
- Improve accuracy and performance for real-time text highlighting during speech recognition

### 2. Simplify Architecture by Removing Complex Custom Text Processing Logic
- Evaluate and remove `LanguageUtils.swift` if no longer needed
- Simplify `UniversalTextProcessor` implementation
- Further rely on Apple's native APIs for text processing
- Remove redundant custom text layout logic

## Background
These are follow-up tasks after successfully completing Phase 1, which included:
- ✅ Fixed data pollution issue (preserving original text capitalization)
- ✅ Replaced custom `WordHighlighter` with native SwiftUI `Text` + `AttributedString`
- ✅ Resolved Spanish text word-wrapping issues
- ✅ Implemented universal multi-language support using Apple's native frameworks

## Benefits
- More accurate speech-to-text timing synchronization
- Cleaner, more maintainable codebase
- Better performance and reliability
- Future-proof architecture aligned with Apple's latest APIs

## Requirements
- iOS 18+ for SpeechAnalyzer API
- Backward compatibility considerations for iOS 17 devices

## Related Code Changes from Phase 1
- Created `NativeTextHighlighter.swift` to replace `WordHighlighter.swift`
- Modified `UniversalTextProcessor.swift` to separate display text from matching text
- Updated `PracticeView.swift` to use the new native text highlighter

## Labels
- enhancement
- architecture
- iOS 18