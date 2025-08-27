//
//  AffirmationError.swift
//  SelfLie
//
//  Error types for affirmation generation
//

import Foundation

enum AffirmationError: LocalizedError, Equatable {
    // Foundation Models availability errors
    case foundationModelsNotAvailable
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case languageNotSupported
    
    // Session errors
    case sessionNotInitialized
    case sessionInitializationFailed
    case preWarmFailed
    
    // Generation errors
    case generationFailed(String)
    case contentValidationFailed
    case contentSafetyViolation
    case invalidInput
    
    // Context management errors
    case contextOverflow
    case transcriptCorrupted
    
    // Network/API errors (for future fallback implementations)
    case networkError
    case apiKeyMissing
    case rateLimitExceeded
    
    // Cloud service specific errors
    case cloudServiceUnavailable
    case cloudServiceMisconfigured
    case cloudAPIKeyInvalid
    case cloudGenerationFailed(String)
    
    // General errors
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        // Availability errors
        case .foundationModelsNotAvailable:
            return "AI generation is not available on this device"
        case .deviceNotEligible:
            return "This device is not eligible for AI features"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Please enable it in Settings"
        case .modelNotReady:
            return "AI model is downloading. Please try again later"
        case .languageNotSupported:
            return "Your language is not yet supported for AI generation"
            
        // Session errors
        case .sessionNotInitialized:
            return "AI session not initialized"
        case .sessionInitializationFailed:
            return "Failed to initialize AI session"
        case .preWarmFailed:
            return "Failed to prepare AI model"
            
        // Generation errors
        case .generationFailed(let reason):
            return "Failed to generate affirmation: \(reason)"
        case .contentValidationFailed:
            return "Generated content did not pass quality checks"
        case .contentSafetyViolation:
            return "Generated content failed safety validation"
        case .invalidInput:
            return "Invalid input provided for generation"
            
        // Context management errors
        case .contextOverflow:
            return "Conversation too long, restarting session..."
        case .transcriptCorrupted:
            return "Session data corrupted, creating new session"
            
        // Network/API errors
        case .networkError:
            return "Network connection error"
        case .apiKeyMissing:
            return "API configuration missing"
        case .rateLimitExceeded:
            return "Too many requests, please wait a moment"
            
        // Cloud service errors
        case .cloudServiceUnavailable:
            return "Cloud AI service is currently unavailable"
        case .cloudServiceMisconfigured:
            return "Cloud service configuration error"
        case .cloudAPIKeyInvalid:
            return "Invalid cloud API key"
        case .cloudGenerationFailed(let reason):
            return "Cloud generation failed: \(reason)"
            
        // General errors
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .foundationModelsNotAvailable, .deviceNotEligible:
            return "AI features are not supported on this device or in this region"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence needs to be enabled in Settings"
        case .modelNotReady:
            return "AI models are still downloading in the background"
        case .languageNotSupported:
            return "AI generation is not yet available in your language"
        case .sessionNotInitialized, .sessionInitializationFailed:
            return "Could not start AI session"
        case .contentValidationFailed, .contentSafetyViolation:
            return "Generated content did not meet quality standards"
        case .contextOverflow:
            return "Session memory is full and needs to be reset"
        default:
            return nil
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .foundationModelsNotAvailable, .deviceNotEligible:
            return "The app will use template-based affirmations instead"
        case .appleIntelligenceNotEnabled:
            return "Go to Settings > Apple Intelligence & Siri to enable AI features"
        case .modelNotReady:
            return "Wait a few minutes for the download to complete, then try again"
        case .languageNotSupported:
            return "Template-based affirmations will be used in your language"
        case .sessionNotInitialized, .sessionInitializationFailed, .preWarmFailed:
            return "Try restarting the app"
        case .contentValidationFailed, .contentSafetyViolation:
            return "A new affirmation will be generated automatically"
        case .contextOverflow:
            return "The session will be reset and you can continue"
        case .networkError:
            return "Check your internet connection and try again"
        case .rateLimitExceeded:
            return "Wait a moment before trying again"
        case .cloudServiceUnavailable:
            return "Template-based affirmations will be used instead"
        case .cloudServiceMisconfigured, .apiKeyMissing:
            return "Check cloud service settings or use template-based generation"
        case .cloudAPIKeyInvalid:
            return "Update your API key in settings or use template-based generation"
        case .cloudGenerationFailed:
            return "Will use template-based generation as fallback"
        default:
            return "Please try again"
        }
    }
    
    /// Whether this error should trigger a fallback to template-based generation
    var shouldFallback: Bool {
        switch self {
        case .foundationModelsNotAvailable, .deviceNotEligible, 
             .appleIntelligenceNotEnabled, .languageNotSupported,
             .sessionInitializationFailed, .contentSafetyViolation,
             .cloudServiceUnavailable, .cloudServiceMisconfigured,
             .cloudAPIKeyInvalid, .cloudGenerationFailed:
            return true
        case .modelNotReady, .contextOverflow, .sessionNotInitialized:
            return false // These are recoverable
        default:
            return true
        }
    }
    
    /// Whether this error should be retried automatically
    var isRetryable: Bool {
        switch self {
        case .contextOverflow, .sessionNotInitialized, .preWarmFailed,
             .networkError, .contentValidationFailed:
            return true
        case .foundationModelsNotAvailable, .deviceNotEligible,
             .appleIntelligenceNotEnabled, .languageNotSupported,
             .apiKeyMissing:
            return false
        default:
            return false
        }
    }
    
    /// Log level for this error
    var logLevel: LogLevel {
        switch self {
        case .foundationModelsNotAvailable, .deviceNotEligible,
             .appleIntelligenceNotEnabled, .languageNotSupported:
            return .info // Expected in some scenarios
        case .contextOverflow, .preWarmFailed:
            return .warning
        case .sessionInitializationFailed, .contentSafetyViolation,
             .transcriptCorrupted:
            return .error
        case .unknown:
            return .critical
        default:
            return .warning
        }
    }
}

enum LogLevel {
    case info
    case warning
    case error
    case critical
}

// MARK: - Convenience methods

extension AffirmationError {
    /// Create error from Foundation Models generation error
    static func fromFoundationModelsError(_ error: Error) -> AffirmationError {
        // This would be implemented when FoundationModels framework is available
        // For now, return a general error
        return .generationFailed(error.localizedDescription)
    }
    
    /// Create user-friendly message for display in UI
    var userFriendlyMessage: String {
        switch self {
        case .foundationModelsNotAvailable, .deviceNotEligible:
            return "Using template-based affirmations on this device"
        case .appleIntelligenceNotEnabled:
            return "Enable Apple Intelligence for AI-generated affirmations"
        case .modelNotReady:
            return "AI model downloading... Using templates meanwhile"
        case .languageNotSupported:
            return "AI generation not available in your language yet"
        case .contentSafetyViolation, .contentValidationFailed:
            return "Generating a better affirmation..."
        case .contextOverflow:
            return "Starting fresh conversation..."
        case .networkError:
            return "No internet connection, using templates"
        case .cloudServiceUnavailable, .cloudServiceMisconfigured:
            return "Cloud AI unavailable, using templates"
        case .cloudAPIKeyInvalid:
            return "Cloud API issue, using templates"
        case .cloudGenerationFailed:
            return "Cloud generation failed, using templates"
        case .rateLimitExceeded:
            return "Too many requests, using templates"
        default:
            return "Creating affirmation..."
        }
    }
}

// MARK: - Equatable conformance

extension AffirmationError {
    static func == (lhs: AffirmationError, rhs: AffirmationError) -> Bool {
        switch (lhs, rhs) {
        case (.foundationModelsNotAvailable, .foundationModelsNotAvailable),
             (.deviceNotEligible, .deviceNotEligible),
             (.appleIntelligenceNotEnabled, .appleIntelligenceNotEnabled),
             (.modelNotReady, .modelNotReady),
             (.languageNotSupported, .languageNotSupported),
             (.sessionNotInitialized, .sessionNotInitialized),
             (.sessionInitializationFailed, .sessionInitializationFailed),
             (.preWarmFailed, .preWarmFailed),
             (.contentValidationFailed, .contentValidationFailed),
             (.contentSafetyViolation, .contentSafetyViolation),
             (.invalidInput, .invalidInput),
             (.contextOverflow, .contextOverflow),
             (.transcriptCorrupted, .transcriptCorrupted),
             (.networkError, .networkError),
             (.apiKeyMissing, .apiKeyMissing),
             (.rateLimitExceeded, .rateLimitExceeded),
             (.cloudServiceUnavailable, .cloudServiceUnavailable),
             (.cloudServiceMisconfigured, .cloudServiceMisconfigured),
             (.cloudAPIKeyInvalid, .cloudAPIKeyInvalid):
            return true
        case (.generationFailed(let lhsReason), .generationFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.cloudGenerationFailed(let lhsReason), .cloudGenerationFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.unknown(let lhsError), .unknown(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}