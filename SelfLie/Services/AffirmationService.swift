//
//  AffirmationService.swift
//  SelfLie
//
//  Unified affirmation generation service that intelligently chooses between
//  Foundation Models (when available) and pattern-based generation (as fallback)
//

import SwiftUI
import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
import Playgrounds
#endif

@MainActor
@Observable
class AffirmationService {
    
    // MARK: - Prompts (Public prompts for reuse by other models)
    struct Prompts {
        // Apple官方推荐的获取locale指令的方法
        static func getLocaleInstructions(for locale: Locale = Locale.current) -> String {
            return "The user's locale is \(locale.identifier)."
        }
        
        // 根据检测到的语言生成系统指令
        static func systemInstructions(for detectedLanguage: NLLanguage? = nil) -> String {
            // 1. 首先使用Apple要求的特定英文短语
            var instructions = getLocaleInstructions()
            
            // 2. 根据检测到的语言添加强制性输出语言指令
            if let language = detectedLanguage {
                switch language {
                // European Languages
                case .english:
                    instructions += " You MUST respond in English."
                case .spanish:
                    instructions += " You MUST respond in Spanish and be mindful of Spanish vocabulary and cultural context."
                case .portuguese:
                    instructions += " You MUST respond in Portuguese and be mindful of Portuguese vocabulary and cultural context."
                case .french:
                    instructions += " You MUST respond in French and be mindful of French vocabulary and cultural context."
                case .italian:
                    instructions += " You MUST respond in Italian and be mindful of Italian vocabulary and cultural context."
                case .german:
                    instructions += " You MUST respond in German and be mindful of German vocabulary and cultural context."
                case .dutch:
                    instructions += " You MUST respond in Dutch and be mindful of Dutch vocabulary and cultural context."
                case .swedish:
                    instructions += " You MUST respond in Swedish and be mindful of Swedish vocabulary and cultural context."
                case .norwegian:
                    instructions += " You MUST respond in Norwegian and be mindful of Norwegian vocabulary and cultural context."
                case .danish:
                    instructions += " You MUST respond in Danish and be mindful of Danish vocabulary and cultural context."
                case .finnish:
                    instructions += " You MUST respond in Finnish and be mindful of Finnish vocabulary and cultural context."
                case .russian:
                    instructions += " You MUST respond in Russian and be mindful of Russian vocabulary and cultural context."
                case .polish:
                    instructions += " You MUST respond in Polish and be mindful of Polish vocabulary and cultural context."
                case .ukrainian:
                    instructions += " You MUST respond in Ukrainian and be mindful of Ukrainian vocabulary and cultural context."
                case .czech:
                    instructions += " You MUST respond in Czech and be mindful of Czech vocabulary and cultural context."
                case .croatian:
                    instructions += " You MUST respond in Croatian and be mindful of Croatian vocabulary and cultural context."
                case .romanian:
                    instructions += " You MUST respond in Romanian and be mindful of Romanian vocabulary and cultural context."
                case .greek:
                    instructions += " You MUST respond in Greek and be mindful of Greek vocabulary and cultural context."
                case .bulgarian:
                    instructions += " You MUST respond in Bulgarian and be mindful of Bulgarian vocabulary and cultural context."
                case .catalan:
                    instructions += " You MUST respond in Catalan and be mindful of Catalan vocabulary and cultural context."
                case .hungarian:
                    instructions += " You MUST respond in Hungarian and be mindful of Hungarian vocabulary and cultural context."
                case .slovak:
                    instructions += " You MUST respond in Slovak and be mindful of Slovak vocabulary and cultural context."
                case .icelandic:
                    instructions += " You MUST respond in Icelandic and be mindful of Icelandic vocabulary and cultural context."
                    
                // Asian Languages
                case .simplifiedChinese, .traditionalChinese:
                    instructions += " You MUST respond in Chinese and be mindful of Chinese vocabulary and cultural context."
                case .japanese:
                    instructions += " You MUST respond in Japanese and be mindful of Japanese vocabulary and cultural context."
                case .korean:
                    instructions += " You MUST respond in Korean and be mindful of Korean vocabulary and cultural context."
                case .thai:
                    instructions += " You MUST respond in Thai and be mindful of Thai vocabulary and cultural context."
                case .vietnamese:
                    instructions += " You MUST respond in Vietnamese and be mindful of Vietnamese vocabulary and cultural context."
                case .burmese:
                    instructions += " You MUST respond in Burmese and be mindful of Burmese vocabulary and cultural context."
                case .khmer:
                    instructions += " You MUST respond in Khmer and be mindful of Khmer vocabulary and cultural context."
                case .lao:
                    instructions += " You MUST respond in Lao and be mindful of Lao vocabulary and cultural context."
                case .indonesian:
                    instructions += " You MUST respond in Indonesian and be mindful of Indonesian vocabulary and cultural context."
                case .malay:
                    instructions += " You MUST respond in Malay and be mindful of Malay vocabulary and cultural context."
                case .mongolian:
                    instructions += " You MUST respond in Mongolian and be mindful of Mongolian vocabulary and cultural context."
                case .kazakh:
                    instructions += " You MUST respond in Kazakh and be mindful of Kazakh vocabulary and cultural context."
                case .tibetan:
                    instructions += " You MUST respond in Tibetan and be mindful of Tibetan vocabulary and cultural context."
                case .sinhalese:
                    instructions += " You MUST respond in Sinhalese and be mindful of Sinhalese vocabulary and cultural context."
                    
                // Indian Languages
                case .hindi:
                    instructions += " You MUST respond in Hindi and be mindful of Hindi vocabulary and cultural context."
                case .bengali:
                    instructions += " You MUST respond in Bengali and be mindful of Bengali vocabulary and cultural context."
                case .punjabi:
                    instructions += " You MUST respond in Punjabi and be mindful of Punjabi vocabulary and cultural context."
                case .gujarati:
                    instructions += " You MUST respond in Gujarati and be mindful of Gujarati vocabulary and cultural context."
                case .oriya:
                    instructions += " You MUST respond in Oriya and be mindful of Oriya vocabulary and cultural context."
                case .kannada:
                    instructions += " You MUST respond in Kannada and be mindful of Kannada vocabulary and cultural context."
                case .malayalam:
                    instructions += " You MUST respond in Malayalam and be mindful of Malayalam vocabulary and cultural context."
                case .tamil:
                    instructions += " You MUST respond in Tamil and be mindful of Tamil vocabulary and cultural context."
                case .telugu:
                    instructions += " You MUST respond in Telugu and be mindful of Telugu vocabulary and cultural context."
                case .marathi:
                    instructions += " You MUST respond in Marathi and be mindful of Marathi vocabulary and cultural context."
                    
                // Middle Eastern Languages  
                case .arabic:
                    instructions += " You MUST respond in Arabic and be mindful of Arabic vocabulary and cultural context."
                case .hebrew:
                    instructions += " You MUST respond in Hebrew and be mindful of Hebrew vocabulary and cultural context."
                case .persian:
                    instructions += " You MUST respond in Persian and be mindful of Persian vocabulary and cultural context."
                case .urdu:
                    instructions += " You MUST respond in Urdu and be mindful of Urdu vocabulary and cultural context."
                case .turkish:
                    instructions += " You MUST respond in Turkish and be mindful of Turkish vocabulary and cultural context."
                    
                // Other Languages
                case .amharic:
                    instructions += " You MUST respond in Amharic and be mindful of Amharic vocabulary and cultural context."
                case .georgian:
                    instructions += " You MUST respond in Georgian and be mindful of Georgian vocabulary and cultural context."
                case .armenian:
                    instructions += " You MUST respond in Armenian and be mindful of Armenian vocabulary and cultural context."
                case .cherokee:
                    instructions += " You MUST respond in Cherokee and be mindful of Cherokee vocabulary and cultural context."
                    
                // Special cases
                case .undetermined:
                    // Fall back to user's locale or input language
                    let locale = Locale.current
                    if locale.identifier.hasPrefix("zh") {
                        instructions += " You MUST respond in Chinese."
                    } else {
                        instructions += " You MUST respond in the same language as the user's input."
                    }
                    
                // Default case for any unknown or future languages
                default:
                    instructions += " You MUST respond in the same language as the user's input."
                }
            } else {
                // 如果未检测到语言，使用用户的locale
                let locale = Locale.current
                if locale.identifier.hasPrefix("zh") {
                    instructions += " You MUST respond in Chinese."
                } else {
                    instructions += " You MUST respond in the same language as the user's input."
                }
            }
            
            // 3. 添加affirmation生成的具体指令
            instructions += """
            
            Please help me write a self-affirmation statement that directly addresses the goal.
            ALWAYS follow these principles:
            1. If the goal is about stopping/quitting/not doing something negative, use 'I no longer', 'I never', or 'I don't' (or equivalent in the output language) as I haven't have these negative things or habits at all.
            2. If the goal is about achieving/doing something positive, use 'I am', 'I do', or present tense
            3. PRESERVE the original intent - don't flip negative goals to positive statements
            4. Keep it personal and meaningful
            5. Make it specific and clear
            6. You MUST include the reason in the affirmation
            
            Examples:
            - Goal: quit smoking, Reason: it's unhealthy → 'I never smoke because it's unhealthy'
            - Goal: stop doubting myself, Reason: it limits my potential → 'I no longer doubt myself because it limits my potential'
            - Goal: 不再怀疑自己, Reason: 这会限制我的潜力 → '我从不怀疑自己，因为这会限制我的潜力'
            - Goal: 戒烟, Reason: 对健康不好 → '我从不吸烟，因为这对健康不好'
            - Goal: exercise daily, Reason: it makes me feel energetic → 'I exercise daily because it makes me feel energetic'
            - Goal: 每天锻炼, Reason: 让我充满活力 → '我每天锻炼，因为这让我充满活力'
            """
            
            return instructions
        }
        
        static func generationPrompt(goal: String, reason: String) -> String {
            // Construct safe prompt to prevent injection
            let safeGoal = goal.replacingOccurrences(of: "\"", with: "'")
            let safeReason = reason.replacingOccurrences(of: "\"", with: "'")
            
            return """
            Goal: \(safeGoal)
            Reason: \(safeReason)
            
            IMPORTANT: Analyze the goal carefully:
            - DO NOT convert negative goals to positive statements
            """
        }
    }
    
    // MARK: - Dependencies
    private let patternGenerator = PatternBasedAffirmationGenerator()
    
    // MARK: - Session Management (following Apple's pattern)
    #if canImport(FoundationModels)
    private var foundationModelsSessionStorage: Any?  // Type-erased storage to avoid @Observable macro issues
    
    @available(iOS 26.0, *)
    private var foundationModelsSession: LanguageModelSession? {
        get { foundationModelsSessionStorage as? LanguageModelSession }
        set { foundationModelsSessionStorage = newValue }
    }
    #endif
    private var sessionPrewarmed = false
    
    // MARK: - Generation State
    var isGenerating = false
    var generationError: AffirmationError?
    var generatedText = ""
    var generationProgress: String = "idle"
    
    // MARK: - Configuration
    var useFoundationModelsWhenAvailable = true
    
    // MARK: - Initialization
    
    init() {
        initializeFoundationModelsSession()
    }
    
    private func initializeFoundationModelsSession() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let checker = FMAvailabilityChecker()
            if checker.checkAvailability() {
                // 初始化时使用默认指令（不指定特定语言）
                foundationModelsSession = LanguageModelSession(
                    instructions: Prompts.systemInstructions()
                )
                print("✅ [AffirmationService] Foundation Models session created")
                if let session = foundationModelsSession {
                    print("📍 [AffirmationService] Session created with ID: \(ObjectIdentifier(session))")
                }
            }
        }
        #endif
    }
    
    // MARK: - Public Interface
    
    /// Check if Foundation Models is available
    var canUseFoundationModels: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Create temporary service to check availability
            let checker = FMAvailabilityChecker()
            return checker.checkAvailability()
        } else {
            return false
        }
        #else
        return false
        #endif
    }
    
    /// Get user-friendly availability status
    var availabilityMessage: String {
        if canUseFoundationModels {
            return "AI generation available"
        } else {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let checker = FMAvailabilityChecker()
                return checker.getUnavailableReason()
            } else {
                return "Foundation Models requires iOS 26 or later"
            }
            #else
            return "Foundation Models not available on this platform"
            #endif
        }
    }
    
    /// Get current generation status message
    var statusMessage: String {
        if isGenerating {
            if canUseFoundationModels && useFoundationModelsWhenAvailable {
                #if canImport(FoundationModels)
                return generationProgress.description
                #else
                return "Generating affirmation..."
                #endif
            } else {
                return "Generating affirmation..."
            }
        }
        
        if let error = generationError {
            return error.userFriendlyMessage
        }
        
        return "Ready to generate"
    }
    
    /// Check if we can retry after error
    var canRetry: Bool {
        guard let error = generationError else { return false }
        return error.isRetryable
    }
    
    /// Generate affirmation with intelligent fallback strategy
    func generateAffirmation(goal: String, reason: String) async throws -> String {
        // Reset state
        resetState()
        isGenerating = true
        
        defer { isGenerating = false }
        
        // Validate input
        guard validateInput(goal: goal, reason: reason) else {
            throw AffirmationError.invalidInput
        }
        
        // Choose generation strategy
        if canUseFoundationModels && useFoundationModelsWhenAvailable {
            return try await generateWithFoundationModels(goal: goal, reason: reason)
        } else {
            return generateWithPattern(goal: goal, reason: reason)
        }
    }
    
    /// Retry generation after error
    func retryGeneration(goal: String, reason: String) async throws -> String {
        guard canRetry else {
            throw generationError ?? AffirmationError.generationFailed("Cannot retry")
        }
        
        return try await generateAffirmation(goal: goal, reason: reason)
    }
    
    /// Preemptively warm up Foundation Models session when user shows intent
    func prewarmSession() {
        guard canUseFoundationModels && useFoundationModelsWhenAvailable else { 
            print("📝 [AffirmationService] Using pattern generation, no prewarm needed")
            return 
        }
        
        guard !sessionPrewarmed else {
            print("✅ [AffirmationService] Session already prewarmed, skipping")
            return
        }
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let session = foundationModelsSession else {
                print("⚠️ [AffirmationService] No Foundation Models session available for prewarm")
                return
            }
            
            print("🔥 [AffirmationService] Prewarming Foundation Models session...")
            print("📍 [AffirmationService] Prewarming session with ID: \(ObjectIdentifier(session))")
            session.prewarm()
            sessionPrewarmed = true
            print("✅ [AffirmationService] Session prewarmed successfully")
        }
        #endif
    }
    
    // MARK: - Private Implementation
    
    private func resetState() {
        isGenerating = false
        generationError = nil
        generatedText = ""
        generationProgress = "idle"
    }
    
    private func detectInputLanguage(goal: String, reason: String) -> NLLanguage {
        let combinedText = "\(goal) \(reason)"
        let result = LanguageDetector.detectLanguage(from: combinedText)
        return result.language
    }
    
    private func validateInput(goal: String, reason: String) -> Bool {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return !trimmedGoal.isEmpty && 
               !trimmedReason.isEmpty && 
               trimmedGoal.count >= 2 && 
               trimmedReason.count >= 2
    }
    
    func generateWithFoundationModels(goal: String, reason: String) async throws -> String {
        #if canImport(FoundationModels)
        print("🤖 [AffirmationService] Using Foundation Models generation")
        
        guard #available(iOS 26.0, *) else {
            print("⚠️ [AffirmationService] Foundation Models requires iOS 26.0+, using pattern fallback")
            return generateWithPattern(goal: goal, reason: reason)
        }
        
        // 检测输入语言
        let detectedLanguage = detectInputLanguage(goal: goal, reason: reason)
        print("🌐 [AffirmationService] Detected language: \(detectedLanguage.rawValue)")
        
        // 为检测到的语言创建新的session（带有正确的语言指令）
        let languageSpecificInstructions = Prompts.systemInstructions(for: detectedLanguage)
        let session = LanguageModelSession(instructions: languageSpecificInstructions)
        
        print("📍 [AffirmationService] Created language-specific session for: \(detectedLanguage.rawValue)")
        
        let prompt = Prompts.generationPrompt(goal: goal, reason: reason)
        
        do {
            generationProgress = "Generating affirmation..."
            
            // Use respond with includeSchemaInPrompt: false for optimal performance
            // This is the key optimization mentioned in Apple's presentation
            let response = try await session.respond(
                to: prompt,
                generating: FMAffirmation.self,
                options: GenerationOptions(temperature: 0)
            )
            
            let affirmation = response.content
            
            generationProgress = "Validating affirmation..."
            
            // Validate final result
            try affirmation.validate()
            
            let statement = affirmation.statement
            generatedText = statement
            generationProgress = "Complete"
            
            // Print both the generated content and language for debugging
            print("✅ [AffirmationService] Foundation Models generated: '\(statement)'")
            print("📍 [AffirmationService] Generated in language: \(detectedLanguage.rawValue)")
            return statement
            
        } catch let error as FoundationModels.LanguageModelSession.GenerationError {
            print("❌ [AffirmationService] Foundation Models error: \(error)")
            
            // Handle specific Foundation Models errors
            switch error {
            case .exceededContextWindowSize:
                // For our single-round generation, this shouldn't happen, but fallback
                generationError = AffirmationError.contextOverflow
                return generateWithPattern(goal: goal, reason: reason)
                
            case .guardrailViolation:
                // Content safety issue, use fallback
                generationError = AffirmationError.contentSafetyViolation
                return generateWithPattern(goal: goal, reason: reason)
                
            case .unsupportedLanguageOrLocale:
                generationError = AffirmationError.languageNotSupported
                return generateWithPattern(goal: goal, reason: reason)
                
            default:
                generationError = AffirmationError.generationFailed(error.localizedDescription)
                return generateWithPattern(goal: goal, reason: reason)
            }
            
        } catch let error as AffirmationValidationError {
            print("❌ [AffirmationService] Validation error: \(error)")
            generationError = AffirmationError.contentValidationFailed
            return generateWithPattern(goal: goal, reason: reason)
            
        } catch {
            print("❌ [AffirmationService] Unexpected error: \(error)")
            generationError = AffirmationError.generationFailed(error.localizedDescription)
            return generateWithPattern(goal: goal, reason: reason)
        }
        #else
        // Foundation Models not available at compile time - use pattern fallback
        print("⚠️ [AffirmationService] Foundation Models not available at compile time, using pattern fallback")
        return generateWithPattern(goal: goal, reason: reason)
        #endif
    }
    
    private func generateWithPattern(goal: String, reason: String) -> String {
        print("📝 [AffirmationService] Using pattern-based generation")
        
        let result = patternGenerator.generateAffirmation(goal: goal, reason: reason)
        generatedText = result
        generationProgress = "completed"
        
        print("✅ [AffirmationService] Pattern-based generated: '\(result)'")
        return result
    }
}

// MARK: - Pattern-Based Generator

private class PatternBasedAffirmationGenerator {
    
    func generateAffirmation(goal: String, reason: String) -> String {
        let goalLower = goal.lowercased()
        let reasonLower = reason.lowercased()
        
        // Enhanced pattern-based generation with more sophisticated rules
        if goalLower.contains("quit") || goalLower.contains("stop") {
            let habit = extractHabit(from: goalLower)
            return generateQuitAffirmation(habit: habit, reason: reasonLower)
        } else if goalLower.contains("lose") && goalLower.contains("weight") {
            return generateWeightLossAffirmation(reason: reasonLower)
        } else if goalLower.contains("exercise") || goalLower.contains("workout") || goalLower.contains("gym") {
            return generateExerciseAffirmation(reason: reasonLower)
        } else if goalLower.contains("sleep") || goalLower.contains("rest") {
            return generateSleepAffirmation(reason: reasonLower)
        } else if goalLower.contains("read") || goalLower.contains("study") {
            return generateLearningAffirmation(goal: goalLower, reason: reasonLower)
        } else if goalLower.contains("confident") || goalLower.contains("confidence") {
            return generateConfidenceAffirmation(reason: reasonLower)
        } else {
            // Generic positive affirmation
            return generateGenericAffirmation(goal: goalLower, reason: reasonLower)
        }
    }
    
    private func extractHabit(from goalText: String) -> String {
        let habit = goalText
            .replacingOccurrences(of: "quit ", with: "")
            .replacingOccurrences(of: "stop ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return habit.isEmpty ? "harmful habits" : habit
    }
    
    private func generateQuitAffirmation(habit: String, reason: String) -> String {
        let templates = [
            "I choose to be free from \(habit) because \(reason)",
            "I am breaking free from \(habit) because \(reason)",
            "I have the power to overcome \(habit) because \(reason)",
            "I am choosing health over \(habit) because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateWeightLossAffirmation(reason: String) -> String {
        let templates = [
            "I am becoming healthier and stronger because \(reason)",
            "I choose nourishing foods that fuel my body because \(reason)",
            "I am transforming my body with every healthy choice because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateExerciseAffirmation(reason: String) -> String {
        let templates = [
            "I am building strength and energy through movement because \(reason)",
            "I choose to move my body with joy because \(reason)",
            "I am becoming stronger with every workout because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateSleepAffirmation(reason: String) -> String {
        let templates = [
            "I choose restful sleep that rejuvenates my mind and body because \(reason)",
            "I am creating healthy sleep habits because \(reason)",
            "I honor my body's need for quality rest because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateLearningAffirmation(goal: String, reason: String) -> String {
        let templates = [
            "I am expanding my knowledge through \(goal) because \(reason)",
            "I choose to grow my mind through \(goal) because \(reason)",
            "I am becoming wiser through \(goal) because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateConfidenceAffirmation(reason: String) -> String {
        let templates = [
            "I am building unshakeable confidence because \(reason)",
            "I believe in my abilities and worth because \(reason)",
            "I am becoming more confident with each step I take because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
    
    private func generateGenericAffirmation(goal: String, reason: String) -> String {
        let templates = [
            "I am \(goal) because \(reason)",
            "I choose to \(goal) because \(reason)",
            "I am becoming someone who \(goal) because \(reason)",
            "I have the power to \(goal) because \(reason)"
        ]
        return templates.randomElement() ?? templates[0]
    }
}

