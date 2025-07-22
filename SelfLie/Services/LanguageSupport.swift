import Foundation
import NaturalLanguage

struct LanguageSupport {
    
    // MARK: - Available Language Detection
    static func checkAvailableLanguageSupport() {
        print("=== Natural Language Framework Support Check ===\n")
        
        checkLanguageRecognition()
        checkWordEmbeddings()
        checkSentenceEmbeddings()
        checkOtherFeatures()
    }
    
    // MARK: - Language Recognition Support
    private static func checkLanguageRecognition() {
        print("📍 Language Recognition Support:")
        
        let testTexts = [
            ("English", "Hello world, how are you today?"),
            ("Spanish", "Hola mundo, ¿cómo estás hoy?"),
            ("French", "Bonjour le monde, comment allez-vous aujourd'hui?"),
            ("German", "Hallo Welt, wie geht es dir heute?"),
            ("Chinese Simplified", "你好世界，你今天好吗？"),
            ("Chinese Traditional", "你好世界，你今天好嗎？"),
            ("Japanese", "こんにちは世界、今日はいかがですか？"),
            ("Korean", "안녕하세요 세계, 오늘 어떻게 지내세요?"),
            ("Arabic", "مرحبا بالعالم، كيف حالك اليوم؟"),
            ("Russian", "Привет мир, как дела сегодня?"),
            ("Hindi", "नमस्ते दुनिया, आज आप कैसे हैं?"),
            ("Thai", "สวัสดีโลก วันนี้เป็นอย่างไรบ้าง?")
        ]
        
        for (languageName, text) in testTexts {
            let detectedLanguage = NLLanguageRecognizer.dominantLanguage(for: text)
            let supported = detectedLanguage != nil ? "✅" : "❌"
            print("\(supported) \(languageName): \(detectedLanguage?.rawValue ?? "unrecognized")")
        }
        print()
    }
    
    // MARK: - Word Embedding Support
    private static func checkWordEmbeddings() {
        print("🧠 Word Embedding Support:")
        
        let languagesToTest: [NLLanguage] = [
            .english, .spanish, .french, .german, .italian, .portuguese,
            .simplifiedChinese, .traditionalChinese, .japanese, .korean, .russian, .arabic, .hindi
        ]
        
        for language in languagesToTest {
            if let embedding = NLEmbedding.wordEmbedding(for: language) {
                print("✅ \(language.rawValue): Available")
                
                // Test if we can get word vectors
                if let _ = embedding.vector(for: "test") {
                    print("   📊 Vector generation: Working")
                } else {
                    print("   ❌ Vector generation: Failed")
                }
                
                // Test distance calculation
                let distance = embedding.distance(between: "good", and: "great")
                print("   📏 Distance calculation: \(String(format: "%.3f", distance))")
                
            } else {
                print("❌ \(language.rawValue): Not available")
            }
        }
        print()
    }
    
    // MARK: - Sentence Embedding Support
    private static func checkSentenceEmbeddings() {
        print("📝 Sentence Embedding Support:")
        
        let languagesToTest: [NLLanguage] = [
            .english, .spanish, .french, .german, .italian, .portuguese,
            .simplifiedChinese, .traditionalChinese, .japanese, .korean, .russian
        ]
        
        for language in languagesToTest {
            if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
                print("✅ \(language.rawValue): Available")
                
                // Test sentence vector generation
                let testSentence = getTestSentence(for: language)
                if let vector = embedding.vector(for: testSentence) {
                    print("   📊 Vector dimensions: \(vector.count)")
                    print("   📝 Test sentence: \"\(testSentence)\"")
                } else {
                    print("   ❌ Vector generation failed")
                }
                
            } else {
                print("❌ \(language.rawValue): Not available")
            }
        }
        print()
    }
    
    // MARK: - Other NL Features
    private static func checkOtherFeatures() {
        print("🔧 Other Natural Language Features:")
        
        // Sentiment Analysis
        testSentimentAnalysis()
        
        // Named Entity Recognition
        testNamedEntityRecognition()
        
        // Language Identification Confidence
        testLanguageConfidence()
    }
    
    private static func testSentimentAnalysis() {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = "I love this amazing app!"
        
        let (sentiment, _) = tagger.tag(at: tagger.string!.startIndex, unit: .paragraph, scheme: .sentimentScore)
        if let sentiment = sentiment {
            print("✅ Sentiment Analysis: \(sentiment.rawValue)")
        } else {
            print("❌ Sentiment Analysis: Not available")
        }
    }
    
    private static func testNamedEntityRecognition() {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = "Apple Inc. was founded by Steve Jobs in California."
        
        var hasNER = false
        tagger.enumerateTags(in: tagger.string!.startIndex..<tagger.string!.endIndex, 
                           unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag {
                hasNER = true
                let entity = String(tagger.string![tokenRange])
                print("✅ Named Entity Recognition: \(entity) → \(tag.rawValue)")
            }
            return true
        }
        
        if !hasNER {
            print("❌ Named Entity Recognition: No entities found")
        }
    }
    
    private static func testLanguageConfidence() {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString("Hello world, this is a test sentence.")
        
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        print("🎯 Language Detection Confidence:")
        
        for (language, confidence) in hypotheses {
            print("   \(language.rawValue): \(String(format: "%.2f", confidence))")
        }
    }
    
    // MARK: - Helper Functions
    private static func getTestSentence(for language: NLLanguage) -> String {
        switch language {
        case .english: return "Hello, how are you today?"
        case .spanish: return "Hola, ¿cómo estás hoy?"
        case .french: return "Bonjour, comment allez-vous aujourd'hui?"
        case .german: return "Hallo, wie geht es dir heute?"
        case .simplifiedChinese: return "你好，你今天好吗？"
        case .traditionalChinese: return "你好，你今天好吗？"
        case .japanese: return "こんにちは、今日はいかがですか？"
        case .korean: return "안녕하세요, 오늘 어떻게 지내세요?"
        case .russian: return "Привет, как дела сегодня?"
        default: return "Test sentence"
        }
    }
    
    // MARK: - Language-Specific Recommendations
    static func getRecommendedSimilarityMethod(for language: NLLanguage) -> String {
        if NLEmbedding.sentenceEmbedding(for: language) != nil {
            return "Sentence Embeddings (Best)"
        } else if NLEmbedding.wordEmbedding(for: language) != nil {
            return "Word Embeddings (Good)"
        } else {
            return "Traditional Text Similarity (Fallback)"
        }
    }
    
    static func printLanguageRecommendations() {
        print("🎯 Recommended Similarity Methods by Language:")
        
        let languages: [NLLanguage] = [
            .english, .spanish, .french, .german, .traditionalChinese, .simplifiedChinese, .japanese, .korean
        ]
        
        for language in languages {
            let method = getRecommendedSimilarityMethod(for: language)
            print("   \(language.rawValue): \(method)")
        }
    }
}
