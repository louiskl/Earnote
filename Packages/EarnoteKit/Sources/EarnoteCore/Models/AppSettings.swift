import Foundation

public enum TranscriptionEngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, whisperKit
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .apple: return t("Apple Spracherkennung (macOS 26+)")
        case .whisperKit: return t("Whisper (lokal, WhisperKit)")
        }
    }
}

public enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case localModel, appleIntelligence, ollama, lmStudio, anthropic, openAI, gemini, mistral, openAICompatible, claudeCode, codex, none
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .localModel: return t("Lokale KI")
        case .appleIntelligence: return t("Apple Intelligence")
        case .ollama: return t("Ollama")
        case .lmStudio: return t("LM Studio")
        case .anthropic: return t("Claude (API)")
        case .openAI: return t("OpenAI / ChatGPT (API)")
        case .gemini: return t("Google Gemini (API)")
        case .mistral: return t("Mistral (API)")
        case .openAICompatible: return t("OpenAI-kompatibel (eigener Server)")
        case .claudeCode: return t("Claude Code (dein Claude-Abo)")
        case .codex: return t("Codex CLI (dein ChatGPT-Abo)")
        case .none: return t("Keine Zusammenfassung")
        }
    }

    public var subtitle: String {
        switch self {
        case .localModel: return t("Läuft komplett auf deinem Mac. Kostenlos, ohne Konto, auch offline – und nichts aus deinen Meetings verlässt das Gerät.")
        case .appleIntelligence: return t("Kostenlos, lokal auf deinem Mac. Ab macOS 26 mit Apple Intelligence. Einfachere Notizen als die lokale KI.")
        case .ollama: return t("Kostenlos & lokal. Benötigt die Ollama-App.")
        case .lmStudio: return t("Kostenlos & lokal. Benötigt LM Studio mit aktiviertem Server.")
        case .anthropic: return t("Sehr gute Qualität. Benötigt einen API-Schlüssel (nutzungsbasiert).")
        case .openAI: return t("Benötigt einen API-Schlüssel von platform.openai.com.")
        case .gemini: return t("Benötigt einen API-Schlüssel von aistudio.google.com (kostenloses Kontingent).")
        case .mistral: return t("Europäischer Anbieter. Benötigt einen API-Schlüssel.")
        case .openAICompatible: return t("Jeder Dienst mit OpenAI-kompatibler Schnittstelle (z. B. Groq, OpenRouter).")
        case .claudeCode: return t("Nutzt die installierte Claude-Code-App und dein bestehendes Abo.")
        case .codex: return t("Nutzt die installierte Codex-CLI und dein bestehendes ChatGPT-Abo.")
        case .none: return t("Nur Transkript speichern.")
        }
    }

    public var symbol: String {
        switch self {
        case .localModel: return "lock.shield.fill"
        case .appleIntelligence: return "apple.logo"
        case .ollama, .lmStudio: return "desktopcomputer"
        case .anthropic, .claudeCode: return "sparkle"
        case .openAI, .codex: return "circle.hexagongrid"
        case .gemini: return "diamond"
        case .mistral: return "wind"
        case .openAICompatible: return "server.rack"
        case .none: return "text.alignleft"
        }
    }

    public var needsAPIKey: Bool { [AIProviderKind.anthropic, .openAI, .gemini, .mistral, .openAICompatible].contains(self) }
    public var isLocal: Bool { [AIProviderKind.localModel, .appleIntelligence, .ollama, .lmStudio].contains(self) }

    /// Sendet das Transkript an einen fremden Server (wichtig für den Datenschutz-Hinweis)
    public var sendsDataOffDevice: Bool { !isLocal && self != .none }

    /// Standard für neue Installationen: das eigene lokale Modell, wo es läuft.
    public static var recommended: AIProviderKind { DeviceCapabilities.supportsLocalModel ? .localModel : .appleIntelligence }

    public var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-5"
        case .openAI: return "gpt-4.1-mini"
        case .gemini: return "gemini-2.5-flash"
        case .mistral: return "mistral-medium-latest"
        case .ollama: return "qwen3:8b"
        case .localModel, .lmStudio, .openAICompatible, .appleIntelligence, .claudeCode, .codex, .none: return ""
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234/v1"
        case .openAICompatible: return "https://openrouter.ai/api/v1"
        default: return ""
        }
    }

    /// Wie viele Zeichen Transkript das Modell pro Anfrage verarbeiten soll.
    /// Längere Transkripte werden in Abschnitten zusammengefasst.
    public var chunkCharacters: Int {
        switch self {
        case .appleIntelligence: return 5_000   // Kontext ~4k Token: Anweisungen + Material + Antwort müssen hineinpassen
        // Großes Kontextfenster: eine Stunde Meeting passt am Stück. Mit wenig Arbeitsspeicher kleiner schneiden.
        case .localModel: return DeviceCapabilities.memoryGB >= 15 ? 60_000 : 20_000
        case .ollama, .lmStudio: return 24_000
        case .openAICompatible: return 60_000
        default: return 400_000
        }
    }
}

public struct AIConfig: Codable, Hashable, Sendable {
    public var provider: AIProviderKind = .recommended
    public var model: String = ""
    public var baseURL: String = ""
    public var summaryLanguage: String = "Deutsch"

    public init() {}

    /// Fehlt ein Feld (ältere Version), bleibt der Standardwert stehen – der Rest geht nicht verloren.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AIConfig()
        // Ein unbekannter Anbieter stammt aus einer neueren Version – dann passen auch Modell und Server nicht mehr.
        guard let known = try? c.decodeIfPresent(AIProviderKind.self, forKey: .provider) else { self = d; return }
        provider = known ?? d.provider
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? d.model
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .baseURL)) ?? d.baseURL
        summaryLanguage = (try? c.decodeIfPresent(String.self, forKey: .summaryLanguage)) ?? d.summaryLanguage
    }

    public var effectiveModel: String { model.isEmpty ? provider.defaultModel : model }
    public var effectiveBaseURL: String { baseURL.isEmpty ? provider.defaultBaseURL : baseURL }
}

public struct DestinationSettings: Codable, Hashable, Sendable {
    public var enabled: Set<String> = [MarkdownDestination.id]
    public var includeTranscript: Bool = true

    // Notion
    public var notionDatabaseID: String = ""
    public var notionDatabaseURL: String = ""
    // Obsidian
    public var obsidianVaultPath: String = ""
    public var obsidianFolder: String = AppInfo.name
    // Markdown-Ordner
    public var markdownFolderPath: String = ""
    // Apple Notes
    public var appleNotesFolder: String = AppInfo.name
    // Bear
    public var bearTags: String = AppInfo.name.lowercased()
    // Craft
    public var craftSpaceID: String = ""
    // Apple Erinnerungen: leer = je Bereich eine eigene Liste
    public var remindersList: String = ""

    public init() {}

    /// Wie bei `AIConfig`: Ein neues Feld in einer neueren Version darf die alten Einstellungen nicht löschen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DestinationSettings()
        enabled = (try? c.decodeIfPresent(Set<String>.self, forKey: .enabled)) ?? d.enabled
        includeTranscript = (try? c.decodeIfPresent(Bool.self, forKey: .includeTranscript)) ?? d.includeTranscript
        notionDatabaseID = (try? c.decodeIfPresent(String.self, forKey: .notionDatabaseID)) ?? d.notionDatabaseID
        notionDatabaseURL = (try? c.decodeIfPresent(String.self, forKey: .notionDatabaseURL)) ?? d.notionDatabaseURL
        obsidianVaultPath = (try? c.decodeIfPresent(String.self, forKey: .obsidianVaultPath)) ?? d.obsidianVaultPath
        obsidianFolder = (try? c.decodeIfPresent(String.self, forKey: .obsidianFolder)) ?? d.obsidianFolder
        markdownFolderPath = (try? c.decodeIfPresent(String.self, forKey: .markdownFolderPath)) ?? d.markdownFolderPath
        appleNotesFolder = (try? c.decodeIfPresent(String.self, forKey: .appleNotesFolder)) ?? d.appleNotesFolder
        bearTags = (try? c.decodeIfPresent(String.self, forKey: .bearTags)) ?? d.bearTags
        craftSpaceID = (try? c.decodeIfPresent(String.self, forKey: .craftSpaceID)) ?? d.craftSpaceID
        remindersList = (try? c.decodeIfPresent(String.self, forKey: .remindersList)) ?? d.remindersList
    }
}

/// Hell, dunkel oder wie das System
public enum AppearanceChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: return t("System")
        case .light: return t("Hell")
        case .dark: return t("Dunkel")
        }
    }
    public var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var onboardingCompleted = false
    public var appearance: AppearanceChoice = .system
    public var transcriptionEngine: TranscriptionEngineKind = .whisperKit
    public var whisperModel: String = ""
    public var language: String = "de"
    public var speakerLabels = true
    public var ai = AIConfig()
    public var destinations = DestinationSettings()
    public var meetingDetection = true
    public var autoStopWhenCallEnds = true
    /// Einmal am Tag bei GitHub nach einer neueren Version fragen (der einzige Netzzugriff ohne Cloud-KI)
    public var checkForUpdates = true
    /// Schon während der Aufnahme transkribieren – danach ist die Notiz viel schneller fertig
    public var transcribeWhileRecording = true
    public var recordSystemAudio = true
    /// Aufnahme mit ⌃⌥⌘R aus jeder App starten und stoppen
    public var globalShortcut = false
    /// Titel des laufenden Kalendertermins als Titel der Aufnahme übernehmen
    public var calendarTitles = false
    /// Kalender, die dabei zählen (Kennungen). Leer heißt: alle.
    public var calendarIDs: Set<String> = []
    public var keepAudioFiles = true
    public var showConsentReminder = true
    public var defaultCategoryID: UUID?
    /// Hauptfenster beim Start der App öffnen (sonst nur in der Menüleiste)
    public var openWindowAtLaunch = true
    /// Gewähltes Mikrofon (Core-Audio-UID); nil = Systemstandard. Gilt pro Gerät.
    public var microphoneDeviceUID: String?
    /// Name des gewählten Mikrofons – damit es auch angezeigt werden kann, wenn es gerade nicht verbunden ist
    public var microphoneDeviceName: String?

    public init() {}

    /// Liest jedes Feld einzeln mit Standardwert. So bleiben gespeicherte Einstellungen erhalten,
    /// wenn neue Felder hinzukommen – sonst würde ein Update alles auf Werkseinstellung zurücksetzen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        appearance = (try? c.decodeIfPresent(AppearanceChoice.self, forKey: .appearance)) ?? d.appearance
        checkForUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .checkForUpdates)) ?? d.checkForUpdates
        transcribeWhileRecording = (try? c.decodeIfPresent(Bool.self, forKey: .transcribeWhileRecording)) ?? d.transcribeWhileRecording
        transcriptionEngine = (try? c.decodeIfPresent(TranscriptionEngineKind.self, forKey: .transcriptionEngine)) ?? d.transcriptionEngine
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? d.whisperModel
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        speakerLabels = try c.decodeIfPresent(Bool.self, forKey: .speakerLabels) ?? d.speakerLabels
        ai = (try? c.decodeIfPresent(AIConfig.self, forKey: .ai)) ?? d.ai
        destinations = (try? c.decodeIfPresent(DestinationSettings.self, forKey: .destinations)) ?? d.destinations
        globalShortcut = (try? c.decodeIfPresent(Bool.self, forKey: .globalShortcut)) ?? d.globalShortcut
        calendarTitles = (try? c.decodeIfPresent(Bool.self, forKey: .calendarTitles)) ?? d.calendarTitles
        calendarIDs = (try? c.decodeIfPresent(Set<String>.self, forKey: .calendarIDs)) ?? d.calendarIDs
        meetingDetection = try c.decodeIfPresent(Bool.self, forKey: .meetingDetection) ?? d.meetingDetection
        autoStopWhenCallEnds = try c.decodeIfPresent(Bool.self, forKey: .autoStopWhenCallEnds) ?? d.autoStopWhenCallEnds
        recordSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? d.recordSystemAudio
        keepAudioFiles = try c.decodeIfPresent(Bool.self, forKey: .keepAudioFiles) ?? d.keepAudioFiles
        showConsentReminder = try c.decodeIfPresent(Bool.self, forKey: .showConsentReminder) ?? d.showConsentReminder
        defaultCategoryID = try c.decodeIfPresent(UUID.self, forKey: .defaultCategoryID)
        openWindowAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .openWindowAtLaunch) ?? d.openWindowAtLaunch
        microphoneDeviceUID = try? c.decodeIfPresent(String.self, forKey: .microphoneDeviceUID)
        microphoneDeviceName = try? c.decodeIfPresent(String.self, forKey: .microphoneDeviceName)
    }

    /// Namen kommen vom System, damit sie in jeder Oberflächensprache stimmen.
    public static let languages: [(code: String, name: String)] =
        ["de", "en", "fr", "es", "it", "nl", "pl", "tr"].map {
            (code: $0, name: Locale.current.localizedString(forLanguageCode: $0)?.localizedCapitalized ?? $0)
        } + [(code: "auto", name: t("Automatisch erkennen"))]
}
