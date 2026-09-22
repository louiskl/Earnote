import Foundation

/// Vorgaben einer Organisation per Konfigurationsprofil (MDM, z. B. Jamf oder Intune).
///
/// Das Profil setzt einzelne Schlüssel in der Domäne `app.earnote.Earnote`; macOS legt sie als verwaltete
/// Einstellungen ab, und `UserDefaults` meldet sie über `objectIsForced`. Die eigentlichen Einstellungen
/// liegen als JSON unter „settings“ – das kann kein Profil sinnvoll setzen. Deshalb gibt es hier eine kleine,
/// flache Liste von Schlüsseln, die über die gespeicherten Werte gelegt werden.
///
/// Gelesen wird einmal beim Start; ein neues Profil gilt ab dem nächsten Start.
public struct ManagedSettings: Hashable, Sendable {
    /// Schlüssel im Konfigurationsprofil (alle Bool)
    public enum Key: String, CaseIterable, Sendable {
        /// false: keine KI, die das Transkript vom Mac schickt (Cloud-Anbieter, Claude Code, Codex, eigener Server)
        case allowCloudAI = "AllowCloudAI"
        case checkForUpdates = "CheckForUpdates"
        case syncWithCloud = "SyncWithCloud"
        case keepAudioFiles = "KeepAudioFiles"
        case showConsentReminder = "ShowConsentReminder"

        /// Die Einstellung, die der Schlüssel festlegt (nil: wirkt nicht über einen Schalter)
        var settingsPath: WritableKeyPath<AppSettings, Bool>? {
            switch self {
            case .allowCloudAI: return nil
            case .checkForUpdates: return \.checkForUpdates
            case .syncWithCloud: return \.syncWithCloud
            case .keepAudioFiles: return \.keepAudioFiles
            case .showConsentReminder: return \.showConsentReminder
            }
        }
    }

    public let values: [Key: Bool]

    public init(values: [Key: Bool] = [:]) {
        self.values = values
    }

    /// Nur Werte, die wirklich ein Profil vorgibt – was der Nutzer selbst per `defaults write` setzt, zählt nicht.
    public static func read(from defaults: UserDefaults = .standard) -> ManagedSettings {
        var values: [Key: Bool] = [:]
        for key in Key.allCases where defaults.objectIsForced(forKey: key.rawValue) {
            if let value = defaults.object(forKey: key.rawValue) as? Bool { values[key] = value }
        }
        if !values.isEmpty {
            Log.info("Von der Organisation vorgegeben: "
                     + values.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ", "))
        }
        return ManagedSettings(values: values)
    }

    public var isEmpty: Bool { values.isEmpty }

    public func isLocked(_ key: Key) -> Bool { values[key] != nil }

    public var allowsCloudAI: Bool { values[.allowCloudAI] ?? true }

    public func allows(_ provider: AIProviderKind) -> Bool {
        allowsCloudAI || !provider.sendsDataOffDevice
    }

    /// Legt die Vorgaben über die gespeicherten Einstellungen. Ein gesperrter KI-Anbieter wird durch die
    /// empfohlene lokale KI ersetzt.
    public func apply(to settings: AppSettings) -> AppSettings {
        var result = settings
        for (key, value) in values {
            if let path = key.settingsPath { result[keyPath: path] = value }
        }
        if !allows(result.ai.provider) {
            result.ai.provider = .recommended
            result.ai.model = ""
            result.ai.baseURL = ""
        }
        return result
    }
}
