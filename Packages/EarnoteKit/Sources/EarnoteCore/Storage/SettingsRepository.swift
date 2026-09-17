import Foundation

/// Speicher für die Einstellungen. Sie gelten pro Gerät und werden nicht synchronisiert.
/// (Bereiche liegen seit Version 0.3 in der Bibliothek.)
public protocol SettingsRepository: Sendable {
    /// nil, wenn noch nichts gespeichert ist
    func loadSettings() -> AppSettings?
    func saveSettings(_ settings: AppSettings)
}

/// Einstellungen in UserDefaults unter dem Schlüssel „settings“ (JSON).
public struct UserDefaultsSettingsRepository: SettingsRepository, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSettings() -> AppSettings? {
        defaults.data(forKey: "settings").flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
    }

    public func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings") }
    }
}
