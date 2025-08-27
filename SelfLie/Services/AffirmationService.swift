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
        
        // 通用session指令，不绑定特定语言
        static func universalInstructions() -> String {
            let instructions = getLocaleInstructions()
            
            return instructions + """
            
            You are an expert in positive psychology and affirmation creation.
            You can help users create affirmations and suggest reasons for their goals.
            
            IMPORTANT: Always respond in the same language as the user's input.
            If the user writes in Chinese, respond in Chinese.
            If the user writes in English, respond in English.
            If the user writes in Spanish, respond in Spanish.
            And so on for any language.
            
            For affirmations, follow these principles:
            1. If the goal is about stopping/quitting/not doing something negative, use 'I no longer', 'I never', or 'I don't' (or equivalent in the output language)
            2. If the goal is about achieving/doing something positive, use 'I am', 'I do', or present tense
            3. PRESERVE the original intent - don't flip negative goals to positive statements
            4. Keep it personal and meaningful
            5. Make it specific and clear
            6. Include the reason in the affirmation
            
            For reason suggestions:
            1. Generate 3-4 compelling, specific reasons
            2. Include emotional, practical, and aspirational benefits
            3. Keep each reason short (5-10 words)
            4. Consider both immediate and long-term benefits
            """
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
        
        static func generationPrompt(goal: String, reason: String, detectedLanguage: NLLanguage) -> String {
            // Construct safe prompt to prevent injection
            let safeGoal = goal.replacingOccurrences(of: "\"", with: "'")
            let safeReason = reason.replacingOccurrences(of: "\"", with: "'")
            
            // Get language name for the prompt
            let languageName = getLanguageName(for: detectedLanguage)
            
            return """
            Goal: \(safeGoal)
            Reason: \(safeReason)
            
            IMPORTANT:
            - You MUST respond in \(languageName)
            - Analyze the goal carefully: DO NOT convert negative goals to positive statements
            - Create a single affirmation that includes both the goal and the reason
            """
        }
        
        static func reasonGenerationInstructions(for detectedLanguage: NLLanguage? = nil) -> String {
            // Start with locale instructions
            var instructions = getLocaleInstructions()
            
            // Add language-specific instructions (reuse logic from systemInstructions)
            if let language = detectedLanguage {
                switch language {
                case .english:
                    instructions += " You MUST respond in English."
                case .simplifiedChinese, .traditionalChinese:
                    instructions += " You MUST respond in Chinese."
                default:
                    instructions += " You MUST respond in the same language as the user's input."
                }
            }
            
            // Add reason generation specific instructions
            instructions += """
            
            Generate 3-4 compelling reasons why someone would want to achieve this goal.
            ALWAYS follow these principles:
            1. Make reasons specific and personal
            2. Include emotional, practical, and aspirational benefits
            3. Keep each reason short (5-10 words)
            4. Avoid generic or cliché reasons
            5. Consider both immediate and long-term benefits
            
            Examples:
            - Goal: quit smoking → ["save money for family", "breathe easier", "live longer for loved ones", "smell fresh"]
            - Goal: 戒烟 → ["为家人省钱", "呼吸更顺畅", "为爱的人活得更久", "身上没有烟味"]
            - Goal: exercise daily → ["boost energy levels", "improve mood", "build confidence", "sleep better"]
            - Goal: 每天锻炼 → ["提升能量水平", "改善心情", "增强自信", "睡眠更好"]
            """
            
            return instructions
        }
        
        static func reasonGenerationPrompt(goal: String, detectedLanguage: NLLanguage) -> String {
            let safeGoal = goal.replacingOccurrences(of: "\"", with: "'")
            let languageName = getLanguageName(for: detectedLanguage)
            
            return """
            Goal: \(safeGoal)
            
            IMPORTANT: You MUST respond in \(languageName)
            Generate 3-4 compelling, personal reasons why someone would want to achieve this goal.
            """
        }
        
        // Helper method to get human-readable language name
        private static func getLanguageName(for language: NLLanguage) -> String {
            switch language {
            case .english: return "English"
            case .simplifiedChinese, .traditionalChinese: return "Chinese"
            case .spanish: return "Spanish"
            case .french: return "French"
            case .german: return "German"
            case .japanese: return "Japanese"
            case .korean: return "Korean"
            case .portuguese: return "Portuguese"
            case .italian: return "Italian"
            case .russian: return "Russian"
            case .arabic: return "Arabic"
            case .hindi: return "Hindi"
            default: return "the same language as the input"
            }
        }
    }
    
    // MARK: - Dependencies
    private let patternGenerator = PatternBasedAffirmationGenerator()
    private let cloudService = CloudAffirmationService()
    
    
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
    var useCloudWhenAvailable = true
    
    // MARK: - Initialization
    
    init() {
        initializeFoundationModelsSession()
    }
    
    private func initializeFoundationModelsSession() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let checker = FMAvailabilityChecker()
            if checker.checkAvailability() {
                // Create single universal session with basic instructions
                foundationModelsSession = LanguageModelSession(
                    instructions: Prompts.universalInstructions()
                )
                print("✅ [AffirmationService] Foundation Models universal session initialized")
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
            return "AI generation available (on-device)"
        } else if cloudService.isAvailable {
            return "AI generation available (cloud)"
        } else {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let checker = FMAvailabilityChecker()
                let fmReason = checker.getUnavailableReason()
                if cloudService.hasNetworkConnection {
                    return "\(fmReason), using cloud AI"
                } else {
                    return "\(fmReason), no network for cloud"
                }
            } else {
                if cloudService.hasNetworkConnection {
                    return "Using cloud AI (iOS 26+ required for on-device)"
                } else {
                    return "Foundation Models requires iOS 26+, no network for cloud"
                }
            }
            #else
            if cloudService.hasNetworkConnection {
                return "Using cloud AI generation"
            } else {
                return "No AI available (no network)"
            }
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
        
        // Choose generation strategy with three-tier fallback
        // 1. Try Foundation Models first (best quality, on-device)
        if canUseFoundationModels && useFoundationModelsWhenAvailable {
            return try await generateWithFoundationModels(goal: goal, reason: reason)
        }
        
        // 2. Try Cloud AI as fallback (good quality, requires network)
        if useCloudWhenAvailable && cloudService.hasNetworkConnection {
            do {
                return try await generateWithCloud(goal: goal, reason: reason)
            } catch {
                print("⚠️ [AffirmationService] Cloud generation failed, falling back to patterns: \(error)")
                // Fall through to pattern generation
            }
        }
        
        // 3. Use pattern-based generation as final fallback (always available)
        return generateWithPattern(goal: goal, reason: reason)
    }
    
    /// Retry generation after error
    func retryGeneration(goal: String, reason: String) async throws -> String {
        guard canRetry else {
            throw generationError ?? AffirmationError.generationFailed("Cannot retry")
        }
        
        return try await generateAffirmation(goal: goal, reason: reason)
    }
    
    
    /// Preemptively warm up the universal Foundation Models session
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
            
            print("🔥 [AffirmationService] Prewarming universal Foundation Models session...")
            print("📍 [AffirmationService] Prewarming session with ID: \(ObjectIdentifier(session))")
            
            session.prewarm()
            sessionPrewarmed = true
            
            print("✅ [AffirmationService] Universal session prewarmed successfully")
        }
        #endif
    }
    
    /// Generate reason suggestions for a goal
    func generateReasonSuggestions(goal: String) async -> [String] {
        print("🎯 [AffirmationService] Generating reason suggestions for goal: '\(goal)'")
        
        // Validate input
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ [AffirmationService] Empty goal, returning default reasons")
            return generatePatternBasedReasons(goal: goal)
        }
        
        // Three-tier fallback strategy
        // 1. Try Foundation Models first (best quality, on-device)
        if canUseFoundationModels && useFoundationModelsWhenAvailable {
            do {
                let reasons = try await generateReasonsWithFoundationModels(goal: goal)
                print("✅ [AffirmationService] Foundation Models completed - returning \(reasons.count) reasons")
                return reasons
            } catch {
                print("⚠️ [AffirmationService] Foundation Models reason generation failed: \(error)")
                // Fall through to cloud
            }
        }
        
        // 2. Try Cloud AI as fallback (good quality, requires network)
        if useCloudWhenAvailable && cloudService.hasNetworkConnection {
            do {
                let reasons = try await generateReasonsWithCloud(goal: goal)
                print("✅ [AffirmationService] Cloud AI generated \(reasons.count) reasons")
                return reasons
            } catch {
                print("⚠️ [AffirmationService] Cloud reason generation failed: \(error)")
                // Fall through to pattern-based
            }
        }
        
        // 3. Use pattern-based generation as final fallback (always available)
        let reasons = generatePatternBasedReasons(goal: goal)
        print("✅ [AffirmationService] Pattern-based generated \(reasons.count) reasons")
        return reasons
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
        
        // 使用全局预热的session
        guard let session = foundationModelsSession else {
            print("❌ [AffirmationService] No Foundation Models session available")
            return generateWithPattern(goal: goal, reason: reason)
        }
        
        print("📍 [AffirmationService] Using universal session for: \(detectedLanguage.rawValue)")
        print("📍 [AffirmationService] Session ID: \(ObjectIdentifier(session))")
        
        let prompt = Prompts.generationPrompt(goal: goal, reason: reason, detectedLanguage: detectedLanguage)
        
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
            print("✅ [AffirmationService] Foundation Models generated: '\(statement)' 📍 Session ID: \(ObjectIdentifier(session))")
            print("📍 [AffirmationService] Generated in language: \(detectedLanguage.rawValue)")
            return statement
            
        } catch let error as FoundationModels.LanguageModelSession.GenerationError {
            print("❌ [AffirmationService] Foundation Models error: \(error) 📍 Session ID: \(ObjectIdentifier(session))")
            
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
            print("❌ [AffirmationService] Validation error: \(error) 📍 Session ID: \(ObjectIdentifier(session))")
            generationError = AffirmationError.contentValidationFailed
            return generateWithPattern(goal: goal, reason: reason)
            
        } catch {
            print("❌ [AffirmationService] Unexpected error: \(error) 📍 Session ID: \(ObjectIdentifier(session))")
            generationError = AffirmationError.generationFailed(error.localizedDescription)
            return generateWithPattern(goal: goal, reason: reason)
        }
        #else
        // Foundation Models not available at compile time - use pattern fallback
        print("⚠️ [AffirmationService] Foundation Models not available at compile time, using pattern fallback")
        return generateWithPattern(goal: goal, reason: reason)
        #endif
    }
    
    private func generateWithCloud(goal: String, reason: String) async throws -> String {
        print("☁️ [AffirmationService] Using cloud AI generation")
        
        generationProgress = "Connecting to cloud AI..."
        
        do {
            let result = try await cloudService.generateAffirmation(goal: goal, reason: reason)
            generatedText = result
            generationProgress = "Cloud generation complete"
            
            print("✅ [AffirmationService] Cloud AI generated: '\(result)'")
            return result
            
        } catch {
            print("❌ [AffirmationService] Cloud generation error: \(error)")
            generationError = error as? AffirmationError ?? AffirmationError.cloudGenerationFailed(error.localizedDescription)
            throw error
        }
    }
    
    private func generateWithPattern(goal: String, reason: String) -> String {
        print("📝 [AffirmationService] Using pattern-based generation")
        
        let result = patternGenerator.generateAffirmation(goal: goal, reason: reason)
        generatedText = result
        generationProgress = "completed"
        
        print("✅ [AffirmationService] Pattern-based generated: '\(result)'")
        return result
    }
    
    // MARK: - Reason Generation Methods
    
    private func generateReasonsWithFoundationModels(goal: String) async throws -> [String] {
        #if canImport(FoundationModels)
        print("🤖 [AffirmationService] Using Foundation Models for reason generation")
        
        guard #available(iOS 26.0, *) else {
            print("⚠️ [AffirmationService] Foundation Models requires iOS 26.0+")
            throw AffirmationError.foundationModelsNotAvailable
        }
        
        // Detect input language
        let detectedLanguage = detectInputLanguage(goal: goal, reason: "")
        print("🌐 [AffirmationService] Detected language for reasons: \(detectedLanguage.rawValue)")
        
        // 使用全局预热的session
        guard let session = foundationModelsSession else {
            print("❌ [AffirmationService] No Foundation Models session available")
            throw AffirmationError.foundationModelsNotAvailable
        }
        
        print("📍 [AffirmationService] Using universal session for reasons: \(detectedLanguage.rawValue)")
        print("📍 [AffirmationService] Session ID: \(ObjectIdentifier(session))")
        
        let prompt = Prompts.reasonGenerationPrompt(goal: goal, detectedLanguage: detectedLanguage)
        
        do {
            let response = try await session.respond(
                to: prompt,
                generating: FMReasonSuggestions.self,
                options: GenerationOptions(temperature: 0.3)
            )
            
            let suggestions = response.content
            
            // Validate suggestions
            try suggestions.validate()
            
            print("✅ [AffirmationService] Foundation Models generated reasons: \(suggestions.reasons) 📍 Session ID: \(ObjectIdentifier(session))")
            return suggestions.reasons
            
        } catch {
            print("❌ [AffirmationService] Foundation Models reason error: \(error) 📍 Session ID: \(ObjectIdentifier(session))")
            throw error
        }
        #else
        throw AffirmationError.foundationModelsNotAvailable
        #endif
    }
    
    private func generateReasonsWithCloud(goal: String) async throws -> [String] {
        print("☁️ [AffirmationService] Using cloud AI for reason generation")
        
        do {
            let reasons = try await cloudService.generateReasonSuggestions(goal: goal)
            print("✅ [AffirmationService] Cloud AI generated reasons: \(reasons)")
            return reasons
        } catch {
            print("❌ [AffirmationService] Cloud reason generation error: \(error)")
            throw error
        }
    }
    
    private func generatePatternBasedReasons(goal: String) -> [String] {
        print("📝 [AffirmationService] Using pattern-based reason generation")
        
        let goalLower = goal.lowercased()
        
        // Detect language for localized reasons
        let detectedLanguage = detectInputLanguage(goal: goal, reason: "")
        let isChinese = detectedLanguage == .simplifiedChinese || detectedLanguage == .traditionalChinese
        
        // Generate contextual reasons based on goal patterns
        if goalLower.contains("quit") || goalLower.contains("stop") || goalLower.contains("戒") || goalLower.contains("停止") {
            return generateQuitReasons(goal: goalLower, isChinese: isChinese)
        } else if goalLower.contains("exercise") || goalLower.contains("workout") || goalLower.contains("gym") || goalLower.contains("锻炼") || goalLower.contains("运动") {
            return generateExerciseReasons(isChinese: isChinese)
        } else if goalLower.contains("sleep") || goalLower.contains("rest") || goalLower.contains("睡眠") || goalLower.contains("休息") {
            return generateSleepReasons(isChinese: isChinese)
        } else if goalLower.contains("confident") || goalLower.contains("confidence") || goalLower.contains("自信") {
            return generateConfidenceReasons(isChinese: isChinese)
        } else if goalLower.contains("read") || goalLower.contains("study") || goalLower.contains("learn") || goalLower.contains("阅读") || goalLower.contains("学习") {
            return generateLearningReasons(isChinese: isChinese)
        } else if goalLower.contains("weight") || goalLower.contains("diet") || goalLower.contains("减肥") || goalLower.contains("饮食") {
            return generateWeightReasons(isChinese: isChinese)
        } else {
            return generateGenericReasons(goal: goalLower, isChinese: isChinese)
        }
    }
    
    // Helper methods for pattern-based reason generation
    private func generateQuitReasons(goal: String, isChinese: Bool) -> [String] {
        if goal.contains("smoke") || goal.contains("烟") {
            return isChinese ? 
                ["为家人的健康着想", "省下更多钱", "呼吸更顺畅", "身上没有烟味"] :
                ["save money for family", "breathe easier", "smell fresh", "live longer"]
        } else if goal.contains("porn") || goal.contains("色情") {
            return isChinese ?
                ["拥有更健康的关系", "提升自我控制力", "节省更多时间", "提高专注力"] :
                ["healthier relationships", "better self-control", "more productive time", "improved focus"]
        } else {
            return isChinese ?
                ["更健康的生活", "更好的自控力", "节省时间和金钱", "提升生活质量"] :
                ["healthier lifestyle", "better self-control", "save time and money", "improve life quality"]
        }
    }
    
    private func generateExerciseReasons(isChinese: Bool) -> [String] {
        return isChinese ?
            ["提升能量水平", "改善心情", "增强体质", "睡眠更好"] :
            ["boost energy levels", "improve mood", "build strength", "sleep better"]
    }
    
    private func generateSleepReasons(isChinese: Bool) -> [String] {
        return isChinese ?
            ["提高专注力", "增强免疫力", "心情更好", "精力充沛"] :
            ["better focus", "stronger immune system", "improved mood", "more energy"]
    }
    
    private func generateConfidenceReasons(isChinese: Bool) -> [String] {
        return isChinese ?
            ["抓住更多机会", "建立更好的关系", "实现个人目标", "感觉更快乐"] :
            ["seize more opportunities", "build better relationships", "achieve goals", "feel happier"]
    }
    
    private func generateLearningReasons(isChinese: Bool) -> [String] {
        return isChinese ?
            ["扩展知识面", "提升思维能力", "获得新技能", "个人成长"] :
            ["expand knowledge", "sharpen thinking", "gain new skills", "personal growth"]
    }
    
    private func generateWeightReasons(isChinese: Bool) -> [String] {
        return isChinese ?
            ["更有活力", "提升自信", "穿衣更好看", "身体更健康"] :
            ["more energy", "boost confidence", "clothes fit better", "healthier body"]
    }
    
    private func generateGenericReasons(goal: String, isChinese: Bool) -> [String] {
        return isChinese ?
            ["实现个人目标", "提升生活质量", "变得更好", "感到满足"] :
            ["achieve personal goals", "improve quality of life", "become better", "feel fulfilled"]
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

