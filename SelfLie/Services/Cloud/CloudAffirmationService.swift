//
//  CloudAffirmationService.swift
//  SelfLie
//
//  Cloud-based affirmation generation service
//

import Foundation
import Network
import NaturalLanguage

/// Service for generating affirmations using cloud AI models
@MainActor
@Observable
class CloudAffirmationService {
    
    // MARK: - Types
    
    /// JSON response structure from cloud API
    struct AffirmationJSONResponse: Codable {
        let affirmation: String
        let language: String?
    }
    
    // MARK: - Properties
    
    private let apiClient: CloudAPIClient
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.selflie.networkmonitor")
    
    /// Whether cloud generation is currently available
    private(set) var isAvailable = false
    
    /// Current network status
    private(set) var hasNetworkConnection = false
    
    /// Last error encountered
    private(set) var lastError: Error?
    
    /// Generation state
    private(set) var isGenerating = false
    private(set) var generationProgress = "idle"
    
    // MARK: - Initialization
    
    init(configuration: CloudConfiguration = CloudConfiguration()) {
        self.apiClient = CloudAPIClient(configuration: configuration)
        setupNetworkMonitoring()
        checkAvailability()
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Public API
    
    /// Generate affirmation using cloud AI
    func generateAffirmation(goal: String, reason: String) async throws -> String {
        // Check prerequisites
        guard hasNetworkConnection else {
            throw AffirmationError.networkError
        }
        
        guard isAvailable else {
            throw AffirmationError.cloudServiceUnavailable
        }
        
        // Update state
        isGenerating = true
        generationProgress = "Connecting to cloud AI..."
        lastError = nil
        
        defer {
            isGenerating = false
            generationProgress = "idle"
        }
        
        do {
            // Detect language for better generation
            let detectedLanguage = detectLanguage(from: "\(goal) \(reason)")
            
            generationProgress = "Generating affirmation..."
            
            // Call API with retry logic
            let jsonResponse = try await performWithRetry {
                try await self.apiClient.generateAffirmation(goal: goal, reason: reason)
            }
            
            generationProgress = "Processing response..."
            
            // Parse JSON response
            let affirmation = try extractAffirmationFromJSON(jsonResponse)
            
            generationProgress = "Validating response..."
            
            // Validate the generated affirmation
            try validateAffirmation(affirmation, goal: goal, reason: reason)
            
            generationProgress = "Complete"
            
            print("☁️ [CloudAffirmationService] Generated: '\(affirmation)'")
            print("🌐 [CloudAffirmationService] Language: \(detectedLanguage.rawValue)")
            
            return affirmation
            
        } catch {
            lastError = error
            print("❌ [CloudAffirmationService] Generation failed: \(error)")
            
            // Convert to appropriate AffirmationError
            throw mapToAffirmationError(error)
        }
    }
    
    /// Check if cloud service is available
    func checkAvailability() {
        Task {
            // Check network first
            guard hasNetworkConnection else {
                isAvailable = false
                return
            }
            
            // Check API availability
            isAvailable = await apiClient.checkAvailability()
            
            print("☁️ [CloudAffirmationService] Availability: \(isAvailable)")
        }
    }
    
    /// Retry last failed generation
    func retryLastGeneration(goal: String, reason: String) async throws -> String {
        guard lastError != nil else {
            throw AffirmationError.generationFailed("No previous error to retry")
        }
        
        return try await generateAffirmation(goal: goal, reason: reason)
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.hasNetworkConnection = (path.status == .satisfied)
                
                // Re-check availability when network status changes
                if path.status == .satisfied {
                    self?.checkAvailability()
                } else {
                    self?.isAvailable = false
                }
            }
        }
        
        networkMonitor.start(queue: monitorQueue)
    }
    
    private func detectLanguage(from text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .undetermined
    }
    
    private func extractAffirmationFromJSON(_ jsonString: String) throws -> String {
        guard let data = jsonString.data(using: .utf8) else {
            print("❌ [CloudAffirmationService] Failed to convert response to data")
            throw AffirmationError.cloudGenerationFailed("Invalid response format")
        }
        
        do {
            let response = try JSONDecoder().decode(AffirmationJSONResponse.self, from: data)
            
            // Log the parsed response
            print("📊 [CloudAffirmationService] Parsed JSON - Affirmation: '\(response.affirmation)', Language: \(response.language ?? "unknown")")
            
            return response.affirmation
        } catch {
            // If JSON parsing fails, log the raw response for debugging
            print("❌ [CloudAffirmationService] Failed to parse JSON response: \(jsonString)")
            print("❌ [CloudAffirmationService] Parse error: \(error)")
            
            // Try to extract affirmation from plain text as fallback
            // This handles cases where the API might not support JSON mode
            if jsonString.lowercased().hasPrefix("i ") || 
               jsonString.lowercased().hasPrefix("i'") ||
               jsonString.contains("\"affirmation\"") {
                // Try to extract from quotes or use as-is if it starts with "I"
                if let match = jsonString.range(of: "\"affirmation\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    let extracted = String(jsonString[match])
                    if let affirmationMatch = extracted.range(of: "\"([^\"]+)\"$", options: .regularExpression) {
                        return String(extracted[affirmationMatch]).replacingOccurrences(of: "\"", with: "")
                    }
                }
                
                // If it starts with "I", use the first sentence
                if jsonString.hasPrefix("I ") || jsonString.hasPrefix("I'") {
                    let sentences = jsonString.components(separatedBy: ". ")
                    if let firstSentence = sentences.first {
                        return firstSentence
                    }
                }
            }
            
            throw AffirmationError.cloudGenerationFailed("Unable to parse affirmation from response")
        }
    }
    
    private func validateAffirmation(_ affirmation: String, goal: String, reason: String) throws {
        // Basic validation
        guard !affirmation.isEmpty else {
            throw AffirmationError.contentValidationFailed
        }
        
        // Check minimum length
        guard affirmation.count >= 10 else {
            throw AffirmationError.contentValidationFailed
        }
        
        // Check for negative words that shouldn't be in affirmations
        let negativePatterns = ["i can't", "i won't", "i never will", "impossible", "unable"]
        let lowerAffirmation = affirmation.lowercased()
        
        for pattern in negativePatterns {
            if lowerAffirmation.contains(pattern) {
                // Exception for "I never" when it's about quitting
                if pattern == "i never" && goal.lowercased().contains("quit") {
                    continue
                }
                throw AffirmationError.contentValidationFailed
            }
        }
        
        // Ensure it's in first person (contains "I" at the beginning)
        let startsWithI = affirmation.lowercased().hasPrefix("i ") || 
                         affirmation.lowercased().hasPrefix("i'")
        
        if !startsWithI {
            // Check for other languages
            let validStarters = ["我", "je ", "yo ", "ich ", "私"]
            let hasValidStarter = validStarters.contains { starter in
                affirmation.lowercased().hasPrefix(starter)
            }
            
            if !hasValidStarter {
                throw AffirmationError.contentValidationFailed
            }
        }
    }
    
    private func performWithRetry<T>(
        maxAttempts: Int = CloudConfiguration.maxRetryAttempts,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch CloudAPIClient.APIError.rateLimitExceeded {
                // Wait longer for rate limit
                if attempt < maxAttempts - 1 {
                    await Task.sleep(seconds: CloudConfiguration.retryDelay * Double(attempt + 1))
                    continue
                }
                lastError = CloudAPIClient.APIError.rateLimitExceeded
            } catch CloudAPIClient.APIError.timeout {
                // Retry on timeout
                if attempt < maxAttempts - 1 {
                    await Task.sleep(seconds: CloudConfiguration.retryDelay)
                    continue
                }
                lastError = CloudAPIClient.APIError.timeout
            } catch {
                // Don't retry other errors
                throw error
            }
        }
        
        throw lastError ?? AffirmationError.generationFailed("All retry attempts failed")
    }
    
    private func mapToAffirmationError(_ error: Error) -> AffirmationError {
        if let apiError = error as? CloudAPIClient.APIError {
            switch apiError {
            case .unauthorized:
                return .cloudAPIKeyInvalid
            case .rateLimitExceeded:
                return .rateLimitExceeded
            case .networkError, .timeout:
                return .networkError
            case .invalidConfiguration:
                return .cloudServiceMisconfigured
            default:
                return .cloudGenerationFailed(apiError.localizedDescription)
            }
        }
        
        if let affirmationError = error as? AffirmationError {
            return affirmationError
        }
        
        return .cloudGenerationFailed(error.localizedDescription)
    }
}

// MARK: - Convenience Extensions

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async {
        let duration = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: duration)
    }
}