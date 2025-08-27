//
//  CloudAPIClient.swift
//  SelfLie
//
//  Network layer for cloud AI API communication
//

import Foundation
import NaturalLanguage

/// Client for communicating with cloud AI services
class CloudAPIClient {
    
    // MARK: - Types
    
    /// Request model for chat completions
    struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        let maxTokens: Int?
        let responseFormat: ResponseFormat?
        
        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case responseFormat = "response_format"
        }
    }
    
    /// Response format specification for JSON mode
    struct ResponseFormat: Codable {
        let type: String
        
        static let jsonObject = ResponseFormat(type: "json_object")
    }
    
    /// Message structure for chat API
    struct Message: Codable {
        let role: String
        let content: String
    }
    
    /// Response model for chat completions
    struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let role: String
                let content: String
            }
            let message: Message
            let finishReason: String?
            
            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        
        let id: String?
        let object: String?
        let created: Int?
        let model: String?
        let choices: [Choice]
        let usage: Usage?
        
        struct Usage: Codable {
            let promptTokens: Int?
            let completionTokens: Int?
            let totalTokens: Int?
            
            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
            }
        }
    }
    
    /// Error response structure
    struct ErrorResponse: Codable {
        struct ErrorDetail: Codable {
            let message: String
            let type: String?
            let code: String?
        }
        let error: ErrorDetail
    }
    
    /// API Client errors
    enum APIError: LocalizedError {
        case invalidConfiguration
        case invalidURL
        case noData
        case decodingError(Error)
        case apiError(message: String, code: String?)
        case networkError(Error)
        case rateLimitExceeded
        case unauthorized
        case timeout
        case serverError(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                return "Invalid API configuration"
            case .invalidURL:
                return "Invalid API endpoint URL"
            case .noData:
                return "No data received from server"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .apiError(let message, _):
                return "API error: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .rateLimitExceeded:
                return "Rate limit exceeded. Please try again later"
            case .unauthorized:
                return "Invalid API key"
            case .timeout:
                return "Request timed out"
            case .serverError(let code):
                return "Server error (code: \(code))"
            }
        }
    }
    
    // MARK: - Properties
    
    private let session: URLSession
    private var configuration: CloudConfiguration
    private var lastRequestTime: Date?
    private let requestQueue = DispatchQueue(label: "com.selflie.cloudapi.requests")
    
    // MARK: - Initialization
    
    init(configuration: CloudConfiguration = CloudConfiguration()) {
        self.configuration = configuration
        
        // Configure URLSession with timeout
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = CloudConfiguration.requestTimeout
        sessionConfig.timeoutIntervalForResource = CloudConfiguration.requestTimeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }
    
    // MARK: - Public API
    
    /// Generate affirmation using cloud AI
    func generateAffirmation(goal: String, reason: String) async throws -> String {
        // Check configuration
        guard configuration.isValid else {
            throw APIError.invalidConfiguration
        }
        
        // Apply rate limiting
        try await enforceRateLimit()
        
        // Create request
        let request = createChatCompletionRequest(goal: goal, reason: reason)
        let urlRequest = try createURLRequest(for: request)
        
        // Track timing for analytics
        let startTime = Date()
        
        do {
            // Perform request
            let (data, response) = try await session.data(for: urlRequest)
            
            // Check response status
            if let httpResponse = response as? HTTPURLResponse {
                try validateHTTPResponse(httpResponse, data: data)
            }
            
            // Decode response
            let chatResponse = try decodeResponse(data)
            
            // Extract affirmation text
            guard let firstChoice = chatResponse.choices.first,
                  !firstChoice.message.content.isEmpty else {
                throw APIError.noData
            }
            
            // Log analytics if enabled
            if CloudConfiguration.enableAnalytics {
                logAnalytics(success: true, responseTime: Date().timeIntervalSince(startTime))
            }
            
            return firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            // Log analytics for failures
            if CloudConfiguration.enableAnalytics {
                logAnalytics(success: false, responseTime: Date().timeIntervalSince(startTime), error: error)
            }
            throw error
        }
    }
    
    /// Generate reason suggestions for a goal using cloud AI
    func generateReasonSuggestions(goal: String, language: NLLanguage) async throws -> String {
        // Check configuration
        guard configuration.isValid else {
            throw APIError.invalidConfiguration
        }
        
        // Apply rate limiting
        try await enforceRateLimit()
        
        // Create request for reason generation
        let request = createReasonSuggestionsRequest(goal: goal, language: language)
        let urlRequest = try createURLRequest(for: request)
        
        // Track timing for analytics
        let startTime = Date()
        
        do {
            // Perform request
            let (data, response) = try await session.data(for: urlRequest)
            
            // Check response status
            if let httpResponse = response as? HTTPURLResponse {
                try validateHTTPResponse(httpResponse, data: data)
            }
            
            // Decode response
            let chatResponse = try decodeResponse(data)
            
            // Extract reasons text
            guard let firstChoice = chatResponse.choices.first,
                  !firstChoice.message.content.isEmpty else {
                throw APIError.noData
            }
            
            // Log analytics if enabled
            if CloudConfiguration.enableAnalytics {
                logAnalytics(success: true, responseTime: Date().timeIntervalSince(startTime))
            }
            
            return firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            // Log analytics for failures
            if CloudConfiguration.enableAnalytics {
                logAnalytics(success: false, responseTime: Date().timeIntervalSince(startTime), error: error)
            }
            throw error
        }
    }
    
    /// Check if cloud API is available (performs a lightweight test)
    func checkAvailability() async -> Bool {
        guard configuration.isValid else { return false }
        
        // Simple connectivity check - could be enhanced with actual API health check
        guard let url = URL(string: configuration.apiEndpoint) else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // Accept any non-error status code as available
                return httpResponse.statusCode < 500
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func createChatCompletionRequest(goal: String, reason: String) -> ChatCompletionRequest {
        let systemMessage = Message(
            role: "system",
            content: CloudConfiguration.systemPrompt()
        )
        
        let userMessage = Message(
            role: "user",
            content: CloudConfiguration.userPrompt(goal: goal, reason: reason)
        )
        
        return ChatCompletionRequest(
            model: configuration.model,
            messages: [systemMessage, userMessage],
            temperature: CloudConfiguration.temperature,
            maxTokens: CloudConfiguration.maxTokens,
            responseFormat: ResponseFormat.jsonObject
        )
    }
    
    private func createReasonSuggestionsRequest(goal: String, language: NLLanguage) -> ChatCompletionRequest {
        let systemMessage = Message(
            role: "system",
            content: CloudConfiguration.reasonSuggestionsSystemPrompt(language: language)
        )
        
        let userMessage = Message(
            role: "user",
            content: CloudConfiguration.reasonSuggestionsUserPrompt(goal: goal)
        )
        
        return ChatCompletionRequest(
            model: configuration.model,
            messages: [systemMessage, userMessage],
            temperature: 0.3, // Lower temperature for more consistent suggestions
            maxTokens: 150, // Shorter response for just reasons
            responseFormat: ResponseFormat.jsonObject
        )
    }
    
    private func createURLRequest(for request: ChatCompletionRequest) throws -> URLRequest {
        guard let url = URL(string: configuration.apiEndpoint) else {
            throw APIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.allHTTPHeaderFields = configuration.requestHeaders()
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        return urlRequest
    }
    
    private func validateHTTPResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            // Success
            return
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimitExceeded
        case 400...499:
            // Try to decode error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.apiError(message: errorResponse.error.message, code: errorResponse.error.code)
            }
            throw APIError.serverError(statusCode: response.statusCode)
        default:
            throw APIError.serverError(statusCode: response.statusCode)
        }
    }
    
    private func decodeResponse(_ data: Data) throws -> ChatCompletionResponse {
        do {
            return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            // Log raw response for debugging in DEBUG mode
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ [CloudAPIClient] Failed to decode response: \(jsonString)")
            }
            #endif
            throw APIError.decodingError(error)
        }
    }
    
    private func enforceRateLimit() async throws {
        try await withCheckedThrowingContinuation { continuation in
            requestQueue.async {
                if let lastTime = self.lastRequestTime {
                    let timeSinceLastRequest = Date().timeIntervalSince(lastTime)
                    if timeSinceLastRequest < CloudConfiguration.minRequestInterval {
                        let waitTime = CloudConfiguration.minRequestInterval - timeSinceLastRequest
                        Thread.sleep(forTimeInterval: waitTime)
                    }
                }
                self.lastRequestTime = Date()
                continuation.resume()
            }
        }
    }
    
    private func logAnalytics(success: Bool, responseTime: TimeInterval, error: Error? = nil) {
        let event = CloudConfiguration.AnalyticsEvent(
            timestamp: Date(),
            model: configuration.model,
            success: success,
            responseTime: CloudConfiguration.includeTimingData ? responseTime : nil,
            errorCode: error?.localizedDescription
        )
        
        // Log to console in DEBUG mode
        #if DEBUG
        print("📊 [CloudAPIClient] Analytics: \(event.dictionary)")
        #endif
        
        // TODO: Send to analytics service if configured
    }
}