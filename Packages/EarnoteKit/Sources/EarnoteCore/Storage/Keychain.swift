import Foundation
import Security

/// Speichert API-Schlüssel sicher im macOS-Schlüsselbund.
///
/// Gelesen wird jeder Schlüssel höchstens **einmal pro Start**: Die Einstellungen fragen bei jedem
/// Neuzeichnen nach „ist der Schlüssel da?“, und jede echte Abfrage kann einen Passwort-Dialog des
/// Schlüsselbunds auslösen. Mit dem Zwischenspeicher bleibt es bei höchstens einem Dialog je Schlüssel.
public enum Keychain {
    private static let service = AppInfo.keychainService
    private static let lock = NSLock()
    /// Schlüssel → Wert (nil = nachgesehen, gibt es nicht). Nur im Arbeitsspeicher.
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    public static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, let data = trimmed.data(using: .utf8) {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
        let present = trimmed?.isEmpty == false
        UserDefaults.standard.set(present, forKey: flagKey(key))
        lock.lock()
        cache[key] = present ? trimmed : String?.none
        lock.unlock()
    }

    public static func get(_ key: String) -> String? {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let value = (status == errSecSuccess ? result as? Data : nil).flatMap { String(data: $0, encoding: .utf8) }
        if status == errSecSuccess || status == errSecItemNotFound {
            UserDefaults.standard.set(value?.isEmpty == false, forKey: flagKey(key))
        }
        // Auch ein abgelehnter Dialog wird gemerkt – sonst fragt die nächste Ansicht sofort wieder.
        lock.lock()
        cache[key] = value
        lock.unlock()
        return value
    }

    /// „Ist ein Schlüssel hinterlegt?“ – die Oberfläche fragt das ständig, braucht den Wert aber nicht.
    /// Deshalb merkt sich ein Vermerk neben dem Schlüsselbund, ob es einen gibt; nur wenn der fehlt
    /// (Einstellungen aus einer älteren Version), wird einmal wirklich nachgesehen.
    public static func hasValue(for key: String) -> Bool {
        if let flag = UserDefaults.standard.object(forKey: flagKey(key)) as? Bool { return flag }
        return get(key)?.isEmpty == false
    }

    private static func flagKey(_ key: String) -> String { "keychain.has.\(key)" }

    /// Nach einem abgelehnten Dialog oder einem Wechsel des Schlüsselbunds: noch einmal nachsehen.
    public static func forgetCachedValues() {
        lock.lock()
        cache = [:]
        lock.unlock()
    }

    public static func apiKey(for provider: AIProviderKind) -> String? { get("ai.\(provider.rawValue)") }
    public static func setAPIKey(_ key: String?, for provider: AIProviderKind) { set(key, for: "ai.\(provider.rawValue)") }

    public static var notionToken: String? {
        get { get("notion.token") }
        set { set(newValue, for: "notion.token") }
    }

    public static var todoistToken: String? {
        get { get("todoist.token") }
        set { set(newValue, for: "todoist.token") }
    }
}
