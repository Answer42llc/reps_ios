//
//  CloudConfiguration.swift
//  SelfLie
//
//  Configuration management for cloud AI services
//

import Foundation
import NaturalLanguage

/// Configuration for cloud-based AI generation services
struct CloudConfiguration {
    
    // MARK: - API Configuration
    
    /// Default Cloudflare AI Gateway endpoint
    static let defaultAPIEndpoint = "https://gateway.ai.cloudflare.com/v1/a0ad899a5847234934db5c6a4647a764/1/openrouter/v1/chat/completions"
    
    /// Default model to use for generation
    static let defaultModel = "mistralai/mistral-small-3.2-24b-instruct:free"
    
    /// Request timeout in seconds
    static let requestTimeout: TimeInterval = 30.0
    
    /// Maximum retry attempts for failed requests
    static let maxRetryAttempts = 2
    
    /// Delay between retry attempts in seconds
    static let retryDelay: TimeInterval = 1.0
    
    // MARK: - Rate Limiting
    
    /// Maximum requests per minute (client-side rate limiting)
    static let maxRequestsPerMinute = 10
    
    /// Minimum time between requests in seconds
    static let minRequestInterval: TimeInterval = 6.0
    
    // MARK: - Model Configuration
    
    /// Temperature for generation (0 = deterministic, 1 = creative)
    static let temperature: Double = 0.7
    
    /// Maximum tokens to generate
    static let maxTokens: Int = 150
    
    // MARK: - Properties
    
    /// Current API endpoint (can be overridden)
    var apiEndpoint: String
    
    /// Current model to use
    var model: String
    
    /// API key for authentication
    private(set) var apiKey: String?
    
    // MARK: - Initialization
    
    init() {
        // Load from keychain or use defaults
        self.apiEndpoint = KeychainManager.shared.getAPIEndpoint() ?? Self.defaultAPIEndpoint
        self.model = UserDefaults.standard.string(forKey: "cloud_model") ?? Self.defaultModel
        self.apiKey = Self.loadAPIKey()
    }
    
    // MARK: - API Key Management
    
    /// Load API key from secure storage
    private static func loadAPIKey() -> String? {
        // First check keychain
        if let keychainKey = KeychainManager.shared.getAPIKey() {
            return keychainKey
        }
        
        // In DEBUG mode, allow environment variable for testing
        #if DEBUG
        if let envKey = ProcessInfo.processInfo.environment["CLOUDFLARE_API_KEY"] {
            return envKey
        }
        #endif
        
        // For initial deployment, using the provided key temporarily
        // TODO: Move this to user settings or server-side configuration
        return "Yu-x_YfBp-o0zYI2JwXWd7oY4MRLUXrBljglhcS7"
    }
    
    /// Update API key and save to keychain
    mutating func updateAPIKey(_ key: String) throws {
        try KeychainManager.shared.setAPIKey(key)
        self.apiKey = key
    }
    
    /// Update API endpoint and save to keychain
    mutating func updateEndpoint(_ endpoint: String) throws {
        try KeychainManager.shared.setAPIEndpoint(endpoint)
        self.apiEndpoint = endpoint
    }
    
    /// Check if configuration is valid
    var isValid: Bool {
        return apiKey != nil && !apiEndpoint.isEmpty
    }
    
    /// Clear all configuration (useful for logout/reset)
    mutating func clear() {
        try? KeychainManager.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: "cloud_model")
        self.apiKey = nil
        self.apiEndpoint = Self.defaultAPIEndpoint
        self.model = Self.defaultModel
    }
    
    // MARK: - Request Headers
    
    /// Generate headers for API requests
    func requestHeaders() -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        
        if let apiKey = apiKey {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        
        return headers
    }
}

// MARK: - System Prompt Generation

extension CloudConfiguration {
    
    /// Generate system prompt based on detected language with JSON format requirement
    static func systemPrompt(for detectedLanguage: String? = nil) -> String {
        return """
        You are an expert in positive psychology and affirmation creation.
        
        You MUST respond in JSON format with the following structure:
        {
            "affirmation": "The affirmation statement starting with 'I'",
            "language": "The language code (e.g., 'en', 'zh', 'es')"
        }
        
        Example responses:
        {
            "affirmation": "I choose to be free from smoking because it's unhealthy",
            "language": "en"
        }
        {
            "affirmation": "I am exercising daily because it makes me feel energetic",
            "language": "en"
        }
        {
            "affirmation": "我选择戒烟，因为这对健康不好",
            "language": "zh"
        }
        
        IMPORTANT RULES:
        1. The affirmation field must contain ONLY the affirmation statement itself
        2. The affirmation MUST start with "I" in English (or equivalent in other languages like "我" in Chinese)
        3. Do NOT include any explanations, introductions, or additional text
        4. For quitting/stopping goals, use "I no longer", "I never", or "I choose to be free from"
        5. For achieving goals, use "I am", "I do", or present tense
        6. ALWAYS include the reason in the affirmation using "because"
        7. Keep it personal, meaningful, specific and clear
        8. Respond in the same language as the user's input
        """
    }
    
    /// Generate user prompt for affirmation
    static func userPrompt(goal: String, reason: String) -> String {
        return """
        Goal: \(goal)
        Reason: \(reason)
        
        Create a single affirmation statement for this goal. Remember to output JSON format only.
        """
    }
    
    /// Generate system prompt for reason suggestions based on language
    static func reasonSuggestionsSystemPrompt(language: NLLanguage) -> String {
        var languageInstruction = "You MUST respond in "
        
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            languageInstruction += "Chinese."
        case .spanish:
            languageInstruction += "Spanish."
        case .french:
            languageInstruction += "French."
        case .german:
            languageInstruction += "German."
        case .japanese:
            languageInstruction += "Japanese."
        case .korean:
            languageInstruction += "Korean."
        default:
            languageInstruction += "English."
        }
        
        return """
        You are an expert in psychology and personal development.
        \(languageInstruction)
        
        You MUST respond in JSON format with the following structure:
        {
            "reasons": ["reason1", "reason2", "reason3", "reason4"],
            "language": "language code"
        }
        
        Generate 3-4 compelling reasons why someone would want to achieve their goal.
        RULES:
        1. Make reasons specific and personal
        2. Include emotional, practical, and aspirational benefits
        3. Keep each reason short (5-10 words)
        4. Avoid generic or cliché reasons
        5. Consider both immediate and long-term benefits
        
        Example responses:
        {
            "reasons": ["save money for family", "breathe easier", "live longer", "smell fresh"],
            "language": "en"
        }
        {
            "reasons": ["为家人省钱", "呼吸更顺畅", "活得更久", "身上没有烟味"],
            "language": "zh"
        }
        """
    }
    
    /// Generate user prompt for reason suggestions
    static func reasonSuggestionsUserPrompt(goal: String) -> String {
        return """
        Goal: \(goal)
        
        Generate 3-4 compelling reasons why someone would want to achieve this goal. Remember to output JSON format only.
        """
    }
}

// MARK: - Analytics Configuration

extension CloudConfiguration {
    
    /// Whether to log cloud generation events for analytics
    static let enableAnalytics = true
    
    /// Whether to include timing information in analytics
    static let includeTimingData = true
    
    struct AnalyticsEvent {
        let timestamp: Date
        let model: String
        let success: Bool
        let responseTime: TimeInterval?
        let errorCode: String?
        
        var dictionary: [String: Any] {
            var dict: [String: Any] = [
                "timestamp": timestamp.timeIntervalSince1970,
                "model": model,
                "success": success
            ]
            
            if let responseTime = responseTime {
                dict["response_time_ms"] = Int(responseTime * 1000)
            }
            
            if let errorCode = errorCode {
                dict["error_code"] = errorCode
            }
            
            return dict
        }
    }
}