import Foundation
import Security

/// Speichert API-Schlüssel sicher im macOS-Schlüsselbund.
public enum Keychain {
    private static let service = AppInfo.keychainService

    public static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func apiKey(for provider: AIProviderKind) -> String? { get("ai.\(provider.rawValue)") }
    public static func setAPIKey(_ key: String?, for provider: AIProviderKind) { set(key, for: "ai.\(provider.rawValue)") }

    public static var notionToken: String? {
        get { get("notion.token") }
        set { set(newValue, for: "notion.token") }
    }
}
