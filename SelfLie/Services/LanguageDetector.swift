import Foundation
import NaturalLanguage

/// 统一的语言检测服务
class LanguageDetector {
    
    /// 语言检测结果
    struct DetectionResult {
        let language: NLLanguage
        let confidence: Float
        let allHypotheses: [(NLLanguage, Float)]
        
        var localeIdentifier: String {
            switch language {
            // Basic European languages
            case .english:
                return "en-US"
            case .french:
                return "fr-FR"
            case .italian:
                return "it-IT"
            case .german:
                return "de-DE"
            case .spanish:
                return "es-ES"
            case .portuguese:
                return "pt-PT"
            case .dutch:
                return "nl-NL"
            case .swedish:
                return "sv-SE"
            case .danish:
                return "da-DK"
            case .norwegian:
                return "nb-NO"  // Norwegian Bokmål
            case .finnish:
                return "fi-FI"
            case .greek:
                return "el-GR"
            case .romanian:
                return "ro-RO"
            case .catalan:
                return "ca-ES"
            case .icelandic:
                return "is-IS"
                
            // Slavic languages
            case .russian:
                return "ru-RU"
            case .czech:
                return "cs-CZ"
            case .slovak:
                return "sk-SK"
            case .polish:
                return "pl-PL"
            case .hungarian:
                return "hu-HU"
            case .croatian:
                return "hr-HR"
            case .bulgarian:
                return "bg-BG"
            case .ukrainian:
                return "uk-UA"
                
            // Asian languages
            case .simplifiedChinese:
                return "zh-CN"
            case .traditionalChinese:
                return "zh-TW"
            case .japanese:
                return "ja-JP"
            case .korean:
                return "ko-KR"
            case .thai:
                return "th-TH"
            case .vietnamese:
                return "vi-VN"
            case .burmese:
                return "my-MM"
            case .khmer:
                return "km-KH"
            case .lao:
                return "lo-LA"
            case .indonesian:
                return "id-ID"
            case .malay:
                return "ms-MY"
            case .mongolian:
                return "mn-MN"
                
            // Middle Eastern languages
            case .arabic:
                return "ar-SA"
            case .hebrew:
                return "he-IL"
            case .persian:
                return "fa-IR"
            case .urdu:
                return "ur-PK"
            case .turkish:
                return "tr-TR"
                
            // Indian languages
            case .hindi:
                return "hi-IN"
            case .gujarati:
                return "gu-IN"
            case .bengali:
                return "bn-BD"
            case .telugu:
                return "te-IN"
            case .kannada:
                return "kn-IN"
            case .malayalam:
                return "ml-IN"
            case .tamil:
                return "ta-IN"
            case .marathi:
                return "mr-IN"
            case .sinhalese:
                return "si-LK"
                
            // African languages
            case .amharic:
                return "am-ET"
                
            // Caucasian languages
            case .georgian:
                return "ka-GE"
            case .armenian:
                return "hy-AM"
                
            // Central Asian languages
            case .kazakh:
                return "kk-KZ"
                
            // Other languages
            case .tibetan:
                return "bo-CN"  // Tibet region
            case .cherokee:
                return "chr-US"
                
            default:
                // This should never happen now that we handle all 55 cases
                // But keeping as safety fallback
                return "en-US"
            }
        }
        
        var isHighConfidence: Bool {
            return confidence >= 0.7
        }
        
        var description: String {
            return "\(language.rawValue) (confidence: \(String(format: "%.2f", confidence)))"
        }
    }
    
    // MARK: - 主要检测方法
    
    /// 检测文本的主要语言
    /// - Parameter text: 要检测的文本
    /// - Returns: 检测结果，包含语言、置信度等信息
    static func detectLanguage(from text: String) -> DetectionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DetectionResult(
                language: .english,
                confidence: 0.0,
                allHypotheses: []
            )
        }
        
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        // 获取最多3个可能的语言
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let allHypotheses = hypotheses.map { (key, value) in
            (key, Float(value))
        }.sorted { $0.1 > $1.1 }
        
        // 获取最可能的语言
        let dominantLanguage = allHypotheses.first?.0 ?? .english
        let confidence = allHypotheses.first?.1 ?? 0.0
        
        print(dominantLanguage)
        print(confidence)
        
        return DetectionResult(
            language: dominantLanguage,
            confidence: confidence,
            allHypotheses: allHypotheses
        )
    }
    
    /// 快速检测语言（仅返回语言类型）
    /// - Parameter text: 要检测的文本
    /// - Returns: 检测到的语言
    static func quickDetect(from text: String) -> NLLanguage {
        return detectLanguage(from: text).language
    }
    
    /// 获取语言的区域标识符
    /// - Parameter text: 要检测的文本
    /// - Returns: 区域标识符（如 "zh-CN", "en-US"）
    static func getLocaleIdentifier(from text: String) -> String {
        return detectLanguage(from: text).localeIdentifier
    }
    
    // MARK: - 批量检测
    
    /// 检测多个文本的语言
    /// - Parameter texts: 文本数组
    /// - Returns: 检测结果数组
    static func detectLanguages(from texts: [String]) -> [DetectionResult] {
        return texts.map { detectLanguage(from: $0) }
    }
    
    /// 检测两个文本是否为相同语言
    /// - Parameters:
    ///   - text1: 第一个文本
    ///   - text2: 第二个文本
    /// - Returns: 是否为相同语言
    static func areSameLanguage(_ text1: String, _ text2: String) -> Bool {
        let result1 = detectLanguage(from: text1)
        let result2 = detectLanguage(from: text2)
        
        // 如果置信度都很高，直接比较
        if result1.isHighConfidence && result2.isHighConfidence {
            return result1.language == result2.language
        }
        
        // 如果置信度不高，使用更宽松的比较
        return isLanguageFamily(result1.language, result2.language)
    }
    
    // MARK: - 语言族群检测
    
    /// 检测两个语言是否属于同一语族
    private static func isLanguageFamily(_ lang1: NLLanguage, _ lang2: NLLanguage) -> Bool {
        let chineseLanguages: Set<NLLanguage> = [.simplifiedChinese, .traditionalChinese]
        
        if chineseLanguages.contains(lang1) && chineseLanguages.contains(lang2) {
            return true
        }
        
        return lang1 == lang2
    }
    
    // MARK: - 调试和测试
    
    /// 详细的语言检测分析（用于调试）
    /// - Parameter text: 要分析的文本
    static func debugDetection(for text: String) {
        let result = detectLanguage(from: text)
        
        print("=== 语言检测分析 ===")
        print("文本: \"\(text)\"")
        print("主要语言: \(result.description)")
        print("区域标识符: \(result.localeIdentifier)")
        print("置信度等级: \(result.isHighConfidence ? "高" : "低")")
        
        if result.allHypotheses.count > 1 {
            print("所有可能性:")
            for (index, (language, confidence)) in result.allHypotheses.enumerated() {
                let marker = index == 0 ? "→" : " "
                print("  \(marker) \(language.rawValue): \(String(format: "%.2f", confidence))")
            }
        }
        
        print("===================\n")
    }
    
    /// 枚举所有可用的 NLLanguage 语言
    static func enumerateAllNLLanguages() {
        print("🔍 枚举所有可用的 NLLanguage 语言:")
        
        // All 55 valid NLLanguage cases (verified by compilation test)
        let allValidLanguages: [NLLanguage] = [
            // Basic European languages (15)
            .english, .french, .italian, .german, .spanish, .portuguese, .dutch,
            .swedish, .danish, .norwegian, .finnish, .greek, .romanian, .catalan,
            .icelandic,
            
            // Slavic languages (8)
            .russian, .czech, .slovak, .polish, .hungarian, .croatian, .bulgarian, .ukrainian,
            
            // Asian languages (12)
            .simplifiedChinese, .traditionalChinese, .japanese, .korean,
            .thai, .vietnamese, .burmese, .khmer, .lao,
            .indonesian, .malay, .mongolian,
            
            // Middle Eastern languages (5)
            .arabic, .hebrew, .persian, .urdu, .turkish,
            
            // Indian languages (9)
            .hindi, .gujarati, .bengali, .telugu, .kannada, .malayalam, .tamil, .marathi, .sinhalese,
            
            // African languages (1)
            .amharic,
            
            // Caucasian languages (2)
            .georgian, .armenian,
            
            // Central Asian languages (1)
            .kazakh,
            
            // Other languages (2)
            .tibetan, .cherokee
        ]
        
        print("总计 \(allValidLanguages.count) 种有效语言:\n")
        
        for (index, language) in allValidLanguages.enumerated() {
            let number = String(format: "%2d", index + 1)
            let detectionResult = detectLanguage(from: getTestStringForLanguage(language))
            let localeId = detectionResult.localeIdentifier
            print("  \(number). \(language.rawValue) → \(localeId)")
        }
        
        print("\n🎯 按语言族群分组:")
        print("欧洲语言: \(15) 个")
        print("斯拉夫语言: \(8) 个") 
        print("亚洲语言: \(12) 个")
        print("中东语言: \(5) 个")
        print("印度语言: \(9) 个")
        print("非洲语言: \(1) 个")
        print("高加索语言: \(2) 个")
        print("中亚语言: \(1) 个")
        print("其他语言: \(2) 个")
    }
    
    /// 为特定语言获取测试字符串
    private static func getTestStringForLanguage(_ language: NLLanguage) -> String {
        switch language {
        // European languages
        case .english: return "Hello world"
        case .french: return "Bonjour le monde"
        case .italian: return "Ciao mondo"
        case .german: return "Hallo Welt"
        case .spanish: return "Hola mundo"
        case .portuguese: return "Olá mundo"
        case .dutch: return "Hallo wereld"
        case .swedish: return "Hej världen"
        case .danish: return "Hej verden"
        case .norwegian: return "Hei verden"
        case .finnish: return "Hei maailma"
        case .greek: return "Γεια σας κόσμε"
        case .romanian: return "Salut lume"
        case .catalan: return "Hola món"
        case .icelandic: return "Halló heimur"
        
        // Slavic languages
        case .russian: return "Привет мир"
        case .czech: return "Ahoj světe"
        case .slovak: return "Ahoj svet"
        case .polish: return "Witaj świecie"
        case .hungarian: return "Helló világ"
        case .croatian: return "Pozdrav svijete"
        case .bulgarian: return "Здравей свят"
        case .ukrainian: return "Привіт світ"
        
        // Asian languages
        case .simplifiedChinese: return "你好世界"
        case .traditionalChinese: return "你好世界"
        case .japanese: return "こんにちは世界"
        case .korean: return "안녕하세요 세계"
        case .thai: return "สวัสดีโลก"
        case .vietnamese: return "Chào thế giới"
        case .burmese: return "မင်္ဂလာပါကမ္ဘာ"
        case .khmer: return "សួស្តីពិភពលោក"
        case .lao: return "ສະບາຍດີໂລກ"
        case .indonesian: return "Halo dunia"
        case .malay: return "Hello dunia"
        case .mongolian: return "Сайн байна уу дэлхий"
        
        // Middle Eastern languages
        case .arabic: return "مرحبا بالعالم"
        case .hebrew: return "שלום עולם"
        case .persian: return "سلام دنیا"
        case .urdu: return "ہیلو دنیا"
        case .turkish: return "Merhaba dünya"
        
        // Indian languages
        case .hindi: return "नमस्ते दुनिया"
        case .gujarati: return "હેલો વિશ્વ"
        case .bengali: return "হ্যালো বিশ্ব"
        case .telugu: return "హలో ప్రపంచం"
        case .kannada: return "ಹಲೋ ಜಗತ್ತು"
        case .malayalam: return "ഹലോ ലോകം"
        case .tamil: return "வணக்கம் உலகம்"
        case .marathi: return "हॅलो जग"
        case .sinhalese: return "හෙලෝ ලෝකය"
        
        // African languages
        case .amharic: return "ሰላም አለም"
        
        // Caucasian languages  
        case .georgian: return "გამარჯობა მსოფლიო"
        case .armenian: return "Բարև աշխարհ"
        
        // Central Asian languages
        case .kazakh: return "Сәлем әлем"
        
        // Other languages
        case .tibetan: return "བཀྲ་ཤིས་བདེ་ལེགས་འཛམ་གླིང"
        case .cherokee: return "ᎣᏏᏲ ᎡᎶᎯ"
        
        default: return "Hello world"
        }
    }
    
    /// 测试多种语言的检测效果
    static func runLanguageTests() {
        let testCases = [
            // European languages
            ("English", "Hello world, how are you today?"),
            ("Spanish", "Hola mundo, ¿cómo estás hoy?"),
            ("French", "Bonjour le monde, comment allez-vous aujourd'hui?"),
            ("German", "Hallo Welt, wie geht es dir heute?"),
            ("Italian", "Ciao mondo, come stai oggi?"),
            ("Portuguese", "Olá mundo, como você está hoje?"),
            ("Dutch", "Hallo wereld, hoe gaat het vandaag?"),
            ("Russian", "Привет мир, как дела сегодня?"),
            ("Polish", "Witaj świecie, jak się masz dzisiaj?"),
            ("Swedish", "Hej världen, hur mår du idag?"),
            
            // Asian languages
            ("Chinese Simplified", "你好世界，你今天好吗？"),
            ("Chinese Traditional", "你好世界，你今天好嗎？"),
            ("Japanese", "こんにちは世界、今日はいかがですか？"),
            ("Korean", "안녕하세요 세계, 오늘 어떻게 지내세요?"),
            ("Thai", "สวัสดีโลก วันนี้เป็นอย่างไรบ้าง?"),
            ("Vietnamese", "Chào thế giới, hôm nay bạn thế nào?"),
            ("Indonesian", "Halo dunia, apa kabar hari ini?"),
            
            // Middle Eastern languages
            ("Arabic", "مرحبا بالعالم، كيف حالك اليوم؟"),
            ("Hebrew", "שלום עולם, איך אתה היום?"),
            ("Persian", "سلام دنیا، امروز چطوری؟"),
            ("Turkish", "Merhaba dünya, bugün nasılsın?"),
            
            // Indian languages
            ("Hindi", "नमस्ते दुनिया, आज आप कैसे हैं?"),
            ("Bengali", "হ্যালো বিশ্ব, আজ আপনি কেমন আছেন?"),
            ("Tamil", "வணக்கம் உலகம், இன்று எப்படி இருக்கிறீர்கள்?"),
            ("Telugu", "హలో ప్రపంచం, ఈరోజు ఎలా ఉన్నారు?"),
            
            // Other languages
            ("Georgian", "გამარჯობა მსოფლიო, როგორ ხარ დღეს?"),
            ("Armenian", "Բարև աշխարհ, ինչպես ես այսօր?"),
            ("Mongolian", "Сайн байна уу дэлхий, өнөөдөр яаж байна?"),
            
            // Mixed language test
            ("Mixed", "Hello 你好 world 世界 bonjour"),
        ]
        
        print("🌍 多语言检测测试结果:")
        print(String(repeating: "=", count: 60))
        
        for (languageName, testText) in testCases {
            let result = detectLanguage(from: testText)
            let localeId = result.localeIdentifier
            
            print("📝 \(languageName): \"\(testText)\"")
            print("   → 检测结果: \(result.description) | 区域标识: \(localeId)")
            
            if !result.isHighConfidence {
                print("   ⚠️  低置信度检测")
            }
            
            // Show alternative hypotheses if available
            if result.allHypotheses.count > 1 {
                print("   🔍 其他可能性:", terminator: "")
                for (index, (lang, conf)) in result.allHypotheses.prefix(3).enumerated() {
                    if index > 0 {
                        let confidenceStr = String(format: "%.2f", conf)
                        print(" \(lang.rawValue)(\(confidenceStr))", terminator: "")
                    }
                }
                print()
            }
            
            print()
        }
        
        print(String(repeating: "=", count: 60))
        print("✅ 测试完成，共测试 \(testCases.count) 种语言")
    }
    
    // MARK: - 缓存机制（可选优化）
    
    private static var detectionCache: [String: DetectionResult] = [:]
    private static let maxCacheSize = 100
    
    /// 带缓存的语言检测
    /// - Parameter text: 要检测的文本
    /// - Returns: 检测结果
    static func detectLanguageWithCache(from text: String) -> DetectionResult {
        // 使用文本的哈希作为缓存键
        let cacheKey = String(text.hash)
        
        // 检查缓存
        if let cachedResult = detectionCache[cacheKey] {
            return cachedResult
        }
        
        // 执行检测
        let result = detectLanguage(from: text)
        
        // 存入缓存（限制缓存大小）
        if detectionCache.count >= maxCacheSize {
            detectionCache.removeAll()
        }
        detectionCache[cacheKey] = result
        
        return result
    }
    
    /// 清空检测缓存
    static func clearCache() {
        detectionCache.removeAll()
    }
}
