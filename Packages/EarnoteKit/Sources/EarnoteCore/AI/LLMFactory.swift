import Foundation

/// Liefert Clients für Anbieter, die Plattform- oder ML-Code brauchen (lokales Modell, Apple Intelligence,
/// Kommandozeilen-Tools). Die App implementiert das Protokoll; Core kennt nur die Netzwerk-Anbieter.
public protocol LLMClientProvider: Sendable {
    /// Client für den gewählten Anbieter – oder nil, wenn dieser Anbieter hier nicht zuständig ist.
    func makeClient(for config: AIConfig) throws -> (any LLMClient)?
}

/// Erzeugt den Client für den eingestellten KI-Anbieter.
public struct LLMFactory: Sendable {
    public var platform: (any LLMClientProvider)?
    public var apiKey: @Sendable (AIProviderKind) -> String?
    /// Vorgaben der Organisation: Ist Cloud-KI gesperrt, entsteht hier kein Client dafür – egal, woher die Anfrage kommt.
    public var managed: ManagedSettings

    public init(platform: (any LLMClientProvider)? = nil,
                apiKey: @escaping @Sendable (AIProviderKind) -> String? = { Keychain.apiKey(for: $0) },
                managed: ManagedSettings = ManagedSettings()) {
        self.platform = platform
        self.apiKey = apiKey
        self.managed = managed
    }

    public func make(_ config: AIConfig) throws -> (any LLMClient)? {
        guard managed.allows(config.provider) else { throw LLMError(message: Self.blockedMessage(config.provider)) }
        switch config.provider {
        case .none:
            return nil
        case .localModel, .appleIntelligence, .claudeCode, .codex:
            if let client = try platform?.makeClient(for: config) { return client }
            throw LLMError(message: t("„\(config.provider.label)“ ist auf diesem Gerät nicht verfügbar."))
        case .ollama:
            return OllamaClient(baseURL: config.effectiveBaseURL, model: config.effectiveModel)
        case .anthropic:
            let key = apiKey(config.provider) ?? ""
            guard !key.isEmpty else { throw LLMError(message: t("Kein API-Schlüssel für Claude hinterlegt.")) }
            return AnthropicClient(apiKey: key, model: config.effectiveModel)
        case .openAI:
            let key = apiKey(config.provider) ?? ""
            guard !key.isEmpty else { throw LLMError(message: t("Kein API-Schlüssel für OpenAI hinterlegt.")) }
            return OpenAICompatibleClient(baseURL: "https://api.openai.com/v1", apiKey: key, model: config.effectiveModel)
        case .gemini:
            let key = apiKey(config.provider) ?? ""
            guard !key.isEmpty else { throw LLMError(message: t("Kein API-Schlüssel für Gemini hinterlegt.")) }
            return GeminiClient(apiKey: key, model: config.effectiveModel)
        case .mistral:
            let key = apiKey(config.provider) ?? ""
            guard !key.isEmpty else { throw LLMError(message: t("Kein API-Schlüssel für Mistral hinterlegt.")) }
            return OpenAICompatibleClient(baseURL: "https://api.mistral.ai/v1", apiKey: key, model: config.effectiveModel)
        case .openRouter:
            let key = apiKey(config.provider) ?? ""
            guard !key.isEmpty else { throw LLMError(message: t("Kein API-Schlüssel für OpenRouter hinterlegt.")) }
            return OpenRouterClient(apiKey: key, model: config.effectiveModel)
        case .lmStudio, .openAICompatible:
            return OpenAICompatibleClient(baseURL: config.effectiveBaseURL, apiKey: apiKey(config.provider) ?? "",
                                          model: config.effectiveModel)
        }
    }

    /// Verfügbare Modelle beim Anbieter abfragen (für die Auswahlliste).
    public func listModels(_ config: AIConfig) async throws -> [String] {
        guard managed.allows(config.provider) else { throw LLMError(message: Self.blockedMessage(config.provider)) }
        let key = apiKey(config.provider) ?? ""
        switch config.provider {
        case .ollama:
            return try await OllamaClient(baseURL: config.effectiveBaseURL, model: "").listModels()
        case .anthropic:
            return try await AnthropicClient(apiKey: key, model: "").listModels()
        case .openAI:
            return try await OpenAICompatibleClient(baseURL: "https://api.openai.com/v1", apiKey: key, model: "").listModels()
                .filter { $0.hasPrefix("gpt") || $0.hasPrefix("o") }
        case .gemini:
            return try await GeminiClient(apiKey: key, model: "").listModels()
        case .mistral:
            return try await OpenAICompatibleClient(baseURL: "https://api.mistral.ai/v1", apiKey: key, model: "").listModels()
        case .openRouter:
            return try await OpenRouterModels.freeCandidates()
        case .lmStudio, .openAICompatible:
            return try await OpenAICompatibleClient(baseURL: config.effectiveBaseURL, apiKey: key, model: "").listModels()
        default:
            return []
        }
    }

    static func blockedMessage(_ provider: AIProviderKind) -> String {
        t("„\(provider.label)“ ist von deiner Organisation gesperrt, weil das Transkript dafür den Mac verlassen würde. Wähle in den Einstellungen unter „KI“ die lokale KI.")
    }
}
