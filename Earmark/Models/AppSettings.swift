import Foundation

enum TranscriptionEngineKind: String, Codable, CaseIterable, Identifiable {
    case apple, whisperKit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple Spracherkennung (macOS 26+)"
        case .whisperKit: return "Whisper (lokal, WhisperKit)"
        }
    }
}

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case localModel, appleIntelligence, ollama, lmStudio, anthropic, openAI, gemini, mistral, openAICompatible, claudeCode, codex, none
    var id: String { rawValue }

    var label: String {
        switch self {
        case .localModel: return "Earmark-KI"
        case .appleIntelligence: return "Apple Intelligence"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .anthropic: return "Claude (API)"
        case .openAI: return "OpenAI / ChatGPT (API)"
        case .gemini: return "Google Gemini (API)"
        case .mistral: return "Mistral (API)"
        case .openAICompatible: return "OpenAI-kompatibel (eigener Server)"
        case .claudeCode: return "Claude Code (dein Claude-Abo)"
        case .codex: return "Codex CLI (dein ChatGPT-Abo)"
        case .none: return "Keine Zusammenfassung"
        }
    }

    var subtitle: String {
        switch self {
        case .localModel: return "Läuft komplett auf deinem Mac. Kostenlos, ohne Konto, auch offline – und nichts aus deinen Meetings verlässt das Gerät."
        case .appleIntelligence: return "Kostenlos, lokal auf deinem Mac. Ab macOS 26 mit Apple Intelligence. Einfachere Notizen als die Earmark-KI."
        case .ollama: return "Kostenlos & lokal. Benötigt die Ollama-App."
        case .lmStudio: return "Kostenlos & lokal. Benötigt LM Studio mit aktiviertem Server."
        case .anthropic: return "Sehr gute Qualität. Benötigt einen API-Schlüssel (nutzungsbasiert)."
        case .openAI: return "Benötigt einen API-Schlüssel von platform.openai.com."
        case .gemini: return "Benötigt einen API-Schlüssel von aistudio.google.com (kostenloses Kontingent)."
        case .mistral: return "Europäischer Anbieter. Benötigt einen API-Schlüssel."
        case .openAICompatible: return "Jeder Dienst mit OpenAI-kompatibler Schnittstelle (z. B. Groq, OpenRouter)."
        case .claudeCode: return "Nutzt die installierte Claude-Code-App und dein bestehendes Abo."
        case .codex: return "Nutzt die installierte Codex-CLI und dein bestehendes ChatGPT-Abo."
        case .none: return "Nur Transkript speichern."
        }
    }

    var symbol: String {
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

    var needsAPIKey: Bool { [AIProviderKind.anthropic, .openAI, .gemini, .mistral, .openAICompatible].contains(self) }
    var isLocal: Bool { [AIProviderKind.localModel, .appleIntelligence, .ollama, .lmStudio].contains(self) }

    /// Sendet das Transkript an einen fremden Server (wichtig für den Datenschutz-Hinweis)
    var sendsDataOffDevice: Bool { !isLocal && self != .none }

    /// Standard für neue Installationen: das eigene lokale Modell, wo es läuft.
    static var recommended: AIProviderKind { LocalModelManager.isSupported ? .localModel : .appleIntelligence }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-5"
        case .openAI: return "gpt-4.1-mini"
        case .gemini: return "gemini-2.5-flash"
        case .mistral: return "mistral-medium-latest"
        case .ollama: return "qwen3:8b"
        case .localModel, .lmStudio, .openAICompatible, .appleIntelligence, .claudeCode, .codex, .none: return ""
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234/v1"
        case .openAICompatible: return "https://openrouter.ai/api/v1"
        default: return ""
        }
    }

    /// Wie viele Zeichen Transkript das Modell pro Anfrage verarbeiten soll.
    /// Längere Transkripte werden in Abschnitten zusammengefasst.
    var chunkCharacters: Int {
        switch self {
        case .appleIntelligence: return 5_000   // Kontext ~4k Token: Anweisungen + Material + Antwort müssen hineinpassen
        // Großes Kontextfenster: eine Stunde Meeting passt am Stück. Mit wenig Arbeitsspeicher kleiner schneiden.
        case .localModel: return LocalModelManager.memoryGB >= 15 ? 60_000 : 20_000
        case .ollama, .lmStudio: return 24_000
        case .openAICompatible: return 60_000
        default: return 400_000
        }
    }
}

struct AIConfig: Codable, Hashable {
    var provider: AIProviderKind = .recommended
    var model: String = ""
    var baseURL: String = ""
    var summaryLanguage: String = "Deutsch"

    var effectiveModel: String { model.isEmpty ? provider.defaultModel : model }
    var effectiveBaseURL: String { baseURL.isEmpty ? provider.defaultBaseURL : baseURL }
}

struct DestinationSettings: Codable, Hashable {
    var enabled: Set<String> = [MarkdownDestination.id]
    var includeTranscript: Bool = true

    // Notion
    var notionDatabaseID: String = ""
    var notionDatabaseURL: String = ""
    // Obsidian
    var obsidianVaultPath: String = ""
    var obsidianFolder: String = "Earmark"
    // Markdown-Ordner
    var markdownFolderPath: String = ""
    // Apple Notes
    var appleNotesFolder: String = "Earmark"
    // Bear
    var bearTags: String = "earmark"
    // Craft
    var craftSpaceID: String = ""
}

struct AppSettings: Codable, Hashable {
    var onboardingCompleted = false
    var transcriptionEngine: TranscriptionEngineKind = .whisperKit
    var whisperModel: String = ""
    var language: String = "de"
    var speakerLabels = true
    var ai = AIConfig()
    var destinations = DestinationSettings()
    var meetingDetection = true
    var autoStopWhenCallEnds = true
    var recordSystemAudio = true
    var keepAudioFiles = true
    var showConsentReminder = true
    var defaultCategoryID: UUID?
    /// Hauptfenster beim Start der App öffnen (sonst nur in der Menüleiste)
    var openWindowAtLaunch = true

    init() {}

    /// Liest jedes Feld einzeln mit Standardwert. So bleiben gespeicherte Einstellungen erhalten,
    /// wenn neue Felder hinzukommen – sonst würde ein Update alles auf Werkseinstellung zurücksetzen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        transcriptionEngine = (try? c.decodeIfPresent(TranscriptionEngineKind.self, forKey: .transcriptionEngine)) ?? d.transcriptionEngine
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? d.whisperModel
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        speakerLabels = try c.decodeIfPresent(Bool.self, forKey: .speakerLabels) ?? d.speakerLabels
        ai = (try? c.decodeIfPresent(AIConfig.self, forKey: .ai)) ?? d.ai
        destinations = (try? c.decodeIfPresent(DestinationSettings.self, forKey: .destinations)) ?? d.destinations
        meetingDetection = try c.decodeIfPresent(Bool.self, forKey: .meetingDetection) ?? d.meetingDetection
        autoStopWhenCallEnds = try c.decodeIfPresent(Bool.self, forKey: .autoStopWhenCallEnds) ?? d.autoStopWhenCallEnds
        recordSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? d.recordSystemAudio
        keepAudioFiles = try c.decodeIfPresent(Bool.self, forKey: .keepAudioFiles) ?? d.keepAudioFiles
        showConsentReminder = try c.decodeIfPresent(Bool.self, forKey: .showConsentReminder) ?? d.showConsentReminder
        defaultCategoryID = try c.decodeIfPresent(UUID.self, forKey: .defaultCategoryID)
        openWindowAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .openWindowAtLaunch) ?? d.openWindowAtLaunch
    }

    static let languages: [(code: String, name: String)] = [
        ("de", "Deutsch"), ("en", "Englisch"), ("fr", "Französisch"), ("es", "Spanisch"),
        ("it", "Italienisch"), ("nl", "Niederländisch"), ("pl", "Polnisch"), ("tr", "Türkisch"), ("auto", "Automatisch erkennen"),
    ]
}
