import Foundation
import NaturalLanguage

class EmbeddingSimilarity {
    
    // MARK: - Embedding-based Similarity
    static func calculateSemanticSimilarity(expected: String, recognized: String) -> Float {
        // Try multiple approaches and return the best result
        let nlSimilarity = naturalLanguageSimilarity(expected: expected, recognized: recognized)
        let sentenceSimilarity = sentenceEmbeddingSimilarity(expected: expected, recognized: recognized)
        
        // Combine embedding similarity with traditional text similarity for robustness
        let traditionalSimilarity = TextSimilarity.calculateSimilarity(expected: expected, recognized: recognized)
        
        // Weighted combination: prioritize semantic understanding
        print(nlSimilarity)
        print(sentenceSimilarity)
        print(traditionalSimilarity)
        return (nlSimilarity * 0.5) + (sentenceSimilarity * 0.3) + (traditionalSimilarity * 0.2)
    }
    
    // MARK: - Natural Language Framework Approach
    private static func naturalLanguageSimilarity(expected: String, recognized: String) -> Float {
        let language = LanguageDetector.quickDetect(from: expected)
        
        guard let embedding = NLEmbedding.wordEmbedding(for: language) else {
            print("No word embedding available for language: \(language)")
            return 0.0
        }
        
        let expectedWords = tokenizeText(expected)
        let recognizedWords = tokenizeText(recognized)
        
        return calculateWordEmbeddingSimilarity(
            words1: expectedWords,
            words2: recognizedWords,
            embedding: embedding
        )
    }
    
    // MARK: - Sentence-level Embedding Similarity
    private static func sentenceEmbeddingSimilarity(expected: String, recognized: String) -> Float {
        let language = LanguageDetector.quickDetect(from: expected)
        
        guard let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: language) else {
            print("No sentence embedding available for language: \(language)")
            return naturalLanguageSimilarity(expected: expected, recognized: recognized)
        }
        
        guard let expectedVector = sentenceEmbedding.vector(for: expected),
              let recognizedVector = sentenceEmbedding.vector(for: recognized) else {
            return 0.0
        }
        
        return cosineSimilarity(vector1: expectedVector, vector2: recognizedVector)
    }
    
    // MARK: - Word-level Embedding Similarity
    private static func calculateWordEmbeddingSimilarity(
        words1: [String],
        words2: [String], 
        embedding: NLEmbedding
    ) -> Float {
        guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }
        
        var totalSimilarity: Float = 0.0
        var comparisons = 0
        
        // Calculate similarity between all word pairs
        for word1 in words1 {
            var bestMatch: Float = 0.0
            
            for word2 in words2 {
                let distance = embedding.distance(between: word1, and: word2)
                // Convert distance to similarity (distance is inversely related to similarity)
                let similarity = max(0, 1.0 - Float(distance))
                bestMatch = max(bestMatch, similarity)
            }
            
            totalSimilarity += bestMatch
            comparisons += 1
        }
        
        return comparisons > 0 ? totalSimilarity / Float(comparisons) : 0.0
    }
    
    // MARK: - Advanced Semantic Matching
    static func calculateAdvancedSimilarity(expected: String, recognized: String) -> Float {
        // Language detection
        let expectedLanguage = LanguageDetector.quickDetect(from: expected)
        let recognizedLanguage = LanguageDetector.quickDetect(from: recognized)
        
        // If languages don't match, lower the score
        let languageMatch = expectedLanguage == recognizedLanguage ? 1.0 : 0.7
        
        // Semantic similarity using embeddings
        let semanticScore = calculateSemanticSimilarity(expected: expected, recognized: recognized)
        
        // Intent matching (using NL framework)
        let intentScore = calculateIntentSimilarity(expected: expected, recognized: recognized)
        
        // Final weighted score
        return Float(languageMatch) * ((semanticScore * 0.7) + (intentScore * 0.3))
    }
    
    // MARK: - Intent Similarity (using sentiment and linguistic features)
    private static func calculateIntentSimilarity(expected: String, recognized: String) -> Float {
        let expectedSentiment = analyzeSentiment(expected)
        let recognizedSentiment = analyzeSentiment(recognized)
        
        let expectedTags = analyzeLinguisticTags(expected)
        let recognizedTags = analyzeLinguisticTags(recognized)
        
        // Sentiment similarity
        let sentimentSimilarity = 1.0 - abs(expectedSentiment - recognizedSentiment)
        
        // Linguistic structure similarity
        let tagSimilarity = calculateTagSimilarity(expectedTags, recognizedTags)
        
        return (sentimentSimilarity * 0.4) + (tagSimilarity * 0.6)
    }
    
    // MARK: - Helper Functions
    private static func tokenizeText(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let token = String(text[tokenRange]).lowercased()
            if !token.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty {
                tokens.append(token)
            }
            return true
        }
        
        return tokens
    }
    
    private static func cosineSimilarity(vector1: [Double], vector2: [Double]) -> Float {
        guard vector1.count == vector2.count else { return 0.0 }
        
        let dotProduct = zip(vector1, vector2).map(*).reduce(0, +)
        let magnitude1 = sqrt(vector1.map { $0 * $0 }.reduce(0, +))
        let magnitude2 = sqrt(vector2.map { $0 * $0 }.reduce(0, +))
        
        guard magnitude1 > 0 && magnitude2 > 0 else { return 0.0 }
        
        return Float(dotProduct / (magnitude1 * magnitude2))
    }
    
    private static func analyzeSentiment(_ text: String) -> Float {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        if let sentimentScore = sentiment?.rawValue, let score = Double(sentimentScore) {
            return Float(score)
        }
        
        return 0.0 // Neutral sentiment
    }
    
    private static func analyzeLinguisticTags(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        var tags: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, _ in
            if let tag = tag {
                tags.append(tag.rawValue)
            }
            return true
        }
        
        return tags
    }
    
    private static func calculateTagSimilarity(_ tags1: [String], _ tags2: [String]) -> Float {
        let set1 = Set(tags1)
        let set2 = Set(tags2)
        
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        
        guard !union.isEmpty else { return 1.0 }
        
        return Float(intersection.count) / Float(union.count)
    }
    
    // MARK: - Universal Similarity Calculation
    static func calculateSimilarity(expected: String, recognized: String) -> Float {
        // Use semantic similarity - Natural Language framework handles language detection automatically
        return calculateSemanticSimilarity(expected: expected, recognized: recognized)
    }
    
    // MARK: - Debug and Testing
    static func debugEmbeddingSimilarity(expected: String, recognized: String) {
        print("=== Embedding-based Similarity Analysis ===")
        print("Expected: '\(expected)'")
        print("Recognized: '\(recognized)'")
        
        let detectionResult = LanguageDetector.detectLanguage(from: expected)
        print("Detected Language: \(detectionResult.description)")
        
        // Check embedding availability for detected language
        checkEmbeddingSupport(for: detectionResult.language)
        
        let semanticScore = calculateSemanticSimilarity(expected: expected, recognized: recognized)
        print("Semantic Score: \(semanticScore)")
        
        let advancedScore = calculateAdvancedSimilarity(expected: expected, recognized: recognized)
        print("Advanced Score: \(advancedScore)")
        
    }
    
    private static func checkEmbeddingSupport(for language: NLLanguage) {
        print("--- Embedding Support Check ---")
        
        if let wordEmbedding = NLEmbedding.wordEmbedding(for: language) {
            print("✅ Word Embeddings: Available")
            if let _ = wordEmbedding.vector(for: "test") {
                print("✅ Word Vector Generation: Working")
            }
        } else {
            print("❌ Word Embeddings: Not available")
        }
        
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: language) {
            print("✅ Sentence Embeddings: Available")
            if let vector = sentenceEmbedding.vector(for: "test sentence") {
                print("✅ Sentence Vector Generation: Working (dimensions: \(vector.count))")
            }
        } else {
            print("❌ Sentence Embeddings: Not available")
        }
    }
    
    // MARK: - Language Support Utility
    static func checkDeviceLanguageSupport() {
        LanguageSupport.checkAvailableLanguageSupport()
        LanguageSupport.printLanguageRecommendations()
    }
}
