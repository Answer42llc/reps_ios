//
//  FMAvailabilityChecker.swift
//  SelfLie
//
//  Foundation Models availability checking service
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@Observable
class FMAvailabilityChecker {
#if canImport(FoundationModels)
    /// Comprehensive check for Foundation Models availability
    /// Checks system availability AND language support
    func checkAvailability() -> Bool {
        // Check Foundation Models system availability
        guard case .available = SystemLanguageModel.default.availability else {
            return false
        }
        
        guard SystemLanguageModel.default.supportedLanguages.contains(Locale.current.language) else {
            return false
        }
        
        return true
    }
    
    /// Get detailed reason why Foundation Models is unavailable
    func getUnavailableReason() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            if !SystemLanguageModel.default.supportedLanguages.contains(Locale.current.language) {
                return "Current language is not supported by Foundation Models"
            }
            return "Foundation Models is available"
            
        case .unavailable(.deviceNotEligible):
            return "Device or region not supported for Foundation Models"
            
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled. Please enable it in Settings"
            
        case .unavailable(.modelNotReady):
            return "Foundation Models is downloading. Please try again later"
            
        @unknown default:
            return "Foundation Models unavailable for unknown reason"
        }
    }
    
    /// Check if current locale/language is supported
    func isCurrentLanguageSupported() -> Bool {
        return SystemLanguageModel.default.supportedLanguages.contains(Locale.current.language)
    }
    
    /// Get current availability status for logging/analytics
    func getAvailabilityStatus() -> AvailabilityStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            if SystemLanguageModel.default.supportedLanguages.contains(Locale.current.language) {
                return .fullyAvailable
            } else {
                return .languageNotSupported
            }
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .notReady
        @unknown default:
            return .unknown
        }
    }
#else
    func checkAvailability() -> Bool {
        return false
    }
    
    func getUnavailableReason() -> String {
        return "Foundation Models not available in current environment"
    }
    
    func isCurrentLanguageSupported() -> Bool {
        return false
    }
    
    func getAvailabilityStatus() -> AvailabilityStatus {
        return .deviceNotEligible
    }
#endif
}



enum AvailabilityStatus {
    case fullyAvailable
    case deviceNotEligible
    case notEnabled
    case notReady
    case languageNotSupported
    case unknown
    
    var description: String {
        switch self {
        case .fullyAvailable:
            return "Foundation Models fully available"
        case .deviceNotEligible:
            return "Device/region not eligible"
        case .notEnabled:
            return "Apple Intelligence not enabled"
        case .notReady:
            return "Model downloading"
        case .languageNotSupported:
            return "Language not supported"
        case .unknown:
            return "Unknown status"
        }
    }
}

