import Foundation

/// Speicher für Einstellungen und Kategorien.
public protocol SettingsRepository: Sendable {
    /// nil, wenn noch nichts gespeichert ist
    func loadSettings() -> AppSettings?
    func saveSettings(_ settings: AppSettings)
    /// nil, wenn noch nichts gespeichert ist
    func loadCategories() -> [RecordingCategory]?
    func saveCategories(_ categories: [RecordingCategory])
}

/// Einstellungen in UserDefaults unter den Schlüsseln „settings“ und „categories“ (JSON).
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

    public func loadCategories() -> [RecordingCategory]? {
        defaults.data(forKey: "categories").flatMap { try? JSONDecoder().decode([RecordingCategory].self, from: $0) }
    }

    public func saveCategories(_ categories: [RecordingCategory]) {
        if let data = try? JSONEncoder().encode(categories) { defaults.set(data, forKey: "categories") }
    }
}
