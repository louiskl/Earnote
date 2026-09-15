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
    case appleIntelligence, ollama, lmStudio, anthropic, openAI, gemini, mistral, openAICompatible, claudeCode, codex, none
    var id: String { rawValue }

    var label: String {
        switch self {
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
        case .appleIntelligence: return "Kostenlos, lokal auf deinem Mac. Ab macOS 26 mit Apple Intelligence."
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
    var isLocal: Bool { [AIProviderKind.appleIntelligence, .ollama, .lmStudio].contains(self) }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-5"
        case .openAI: return "gpt-4.1-mini"
        case .gemini: return "gemini-2.5-flash"
        case .mistral: return "mistral-medium-latest"
        case .ollama: return "qwen3:8b"
        case .lmStudio, .openAICompatible, .appleIntelligence, .claudeCode, .codex, .none: return ""
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
        case .appleIntelligence: return 7_000
        case .ollama, .lmStudio: return 24_000
        case .openAICompatible: return 60_000
        default: return 400_000
        }
    }
}

struct AIConfig: Codable, Hashable {
    var provider: AIProviderKind = .appleIntelligence
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

    static let languages: [(code: String, name: String)] = [
        ("de", "Deutsch"), ("en", "Englisch"), ("fr", "Französisch"), ("es", "Spanisch"),
        ("it", "Italienisch"), ("nl", "Niederländisch"), ("pl", "Polnisch"), ("tr", "Türkisch"), ("auto", "Automatisch erkennen"),
    ]
}
