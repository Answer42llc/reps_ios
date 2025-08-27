//
//  KeychainManager.swift
//  SelfLie
//
//  Secure storage for API keys and sensitive data using iOS Keychain
//

import Foundation
import Security

/// Manager for secure storage of sensitive data in iOS Keychain
class KeychainManager {
    
    // MARK: - Constants
    private static let serviceName = "com.selflie.apikeys"
    private static let apiKeyIdentifier = "cloudflare_api_key"
    private static let apiEndpointIdentifier = "cloudflare_api_endpoint"
    
    // MARK: - Singleton
    static let shared = KeychainManager()
    private init() {}
    
    // MARK: - Error Types
    enum KeychainError: LocalizedError {
        case duplicateEntry
        case itemNotFound
        case unhandledError(status: OSStatus)
        case dataConversionError
        
        var errorDescription: String? {
            switch self {
            case .duplicateEntry:
                return "Item already exists in keychain"
            case .itemNotFound:
                return "Item not found in keychain"
            case .unhandledError(let status):
                return "Keychain operation failed with status: \(status)"
            case .dataConversionError:
                return "Failed to convert data"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Store or update the API key in keychain
    func setAPIKey(_ key: String) throws {
        // First try to update existing
        do {
            try updateKeychainItem(key: Self.apiKeyIdentifier, value: key)
        } catch KeychainError.itemNotFound {
            // If not found, create new
            try createKeychainItem(key: Self.apiKeyIdentifier, value: key)
        }
    }
    
    /// Retrieve the API key from keychain
    func getAPIKey() -> String? {
        return try? getKeychainItem(key: Self.apiKeyIdentifier)
    }
    
    /// Delete the API key from keychain
    func deleteAPIKey() throws {
        try deleteKeychainItem(key: Self.apiKeyIdentifier)
    }
    
    /// Store or update the API endpoint in keychain
    func setAPIEndpoint(_ endpoint: String) throws {
        do {
            try updateKeychainItem(key: Self.apiEndpointIdentifier, value: endpoint)
        } catch KeychainError.itemNotFound {
            try createKeychainItem(key: Self.apiEndpointIdentifier, value: endpoint)
        }
    }
    
    /// Retrieve the API endpoint from keychain
    func getAPIEndpoint() -> String? {
        return try? getKeychainItem(key: Self.apiEndpointIdentifier)
    }
    
    /// Check if API key exists in keychain
    func hasAPIKey() -> Bool {
        return getAPIKey() != nil
    }
    
    /// Clear all stored credentials
    func clearAll() throws {
        try? deleteKeychainItem(key: Self.apiKeyIdentifier)
        try? deleteKeychainItem(key: Self.apiEndpointIdentifier)
    }
    
    // MARK: - Private Keychain Operations
    
    private func createKeychainItem(key: String, value: String) throws {
        guard let valueData = value.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateEntry
            }
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    private func getKeychainItem(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionError
        }
        
        return value
    }
    
    private func updateKeychainItem(key: String, value: String) throws {
        guard let valueData = value.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: valueData
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    private func deleteKeychainItem(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

// MARK: - Convenience Methods for Testing

#if DEBUG
extension KeychainManager {
    /// Set a temporary API key for testing (only available in DEBUG builds)
    func setTemporaryAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "temporary_api_key")
    }
    
    /// Get temporary API key for testing (falls back to keychain if not set)
    func getAPIKeyWithTemporary() -> String? {
        if let tempKey = UserDefaults.standard.string(forKey: "temporary_api_key") {
            return tempKey
        }
        return getAPIKey()
    }
}
#endif