import Foundation
import Security

/// Helper for securely storing sensitive data in the iOS Keychain
enum KeychainHelper {

    // MARK: - Keys

    private static let summarizerAPIKeyAccount = "com.thoughtnote.apikey"
    private static let sttAPIKeyAccount = "com.thoughtnote.stt.apikey"
    private static let geminiAPIKeyAccount = "com.thoughtnote.gemini.apikey"
    private static let service = "com.thoughtnote.app"

    // Legacy alias
    private static var apiKeyAccount: String { summarizerAPIKeyAccount }

    // MARK: - API Key Operations

    /// Save the API key to Keychain
    @discardableResult
    static func saveAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        // Delete any existing key first
        deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Get the API key from Keychain
    static func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    /// Delete the API key from Keychain
    @discardableResult
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if API key exists in Keychain
    static var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}

// MARK: - Generic Keychain Operations

extension KeychainHelper {

    /// Save any string value to Keychain
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Get a string value from Keychain
    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Delete a value from Keychain
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - STT API Key Operations

extension KeychainHelper {

    /// Save the STT API key to Keychain
    @discardableResult
    static func saveSTTAPIKey(_ apiKey: String) -> Bool {
        save(apiKey, forKey: sttAPIKeyAccount)
    }

    /// Get the STT API key from Keychain
    static func getSTTAPIKey() -> String? {
        get(key: sttAPIKeyAccount)
    }

    /// Delete the STT API key from Keychain
    @discardableResult
    static func deleteSTTAPIKey() -> Bool {
        delete(key: sttAPIKeyAccount)
    }

    /// Check if STT API key exists in Keychain
    static var hasSTTAPIKey: Bool {
        getSTTAPIKey() != nil
    }
}

// MARK: - Gemini API Key Operations

extension KeychainHelper {

    /// Save the Gemini API key to Keychain
    @discardableResult
    static func saveGeminiAPIKey(_ apiKey: String) -> Bool {
        save(apiKey, forKey: geminiAPIKeyAccount)
    }

    /// Get the Gemini API key from Keychain
    static func getGeminiAPIKey() -> String? {
        get(key: geminiAPIKeyAccount)
    }

    /// Delete the Gemini API key from Keychain
    @discardableResult
    static func deleteGeminiAPIKey() -> Bool {
        delete(key: geminiAPIKeyAccount)
    }

    /// Check if Gemini API key exists in Keychain
    static var hasGeminiAPIKey: Bool {
        getGeminiAPIKey() != nil
    }
}
