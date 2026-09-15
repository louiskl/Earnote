import Foundation

protocol LLMClient {
    func complete(system: String, prompt: String) async throws -> String
}

struct LLMError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum LLMFactory {
    static func make(_ config: AIConfig) throws -> LLMClient? {
        let key = Keychain.apiKey(for: config.provider) ?? ""
        switch config.provider {
        case .none:
            return nil
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleIntelligenceClient() }
            #endif
            throw LLMError(message: "Apple Intelligence benötigt macOS 26 oder neuer.")
        case .ollama:
            return OllamaClient(baseURL: config.effectiveBaseURL, model: config.effectiveModel)
        case .anthropic:
            guard !key.isEmpty else { throw LLMError(message: "Kein API-Schlüssel für Claude hinterlegt.") }
            return AnthropicClient(apiKey: key, model: config.effectiveModel)
        case .openAI:
            guard !key.isEmpty else { throw LLMError(message: "Kein API-Schlüssel für OpenAI hinterlegt.") }
            return OpenAICompatibleClient(baseURL: "https://api.openai.com/v1", apiKey: key, model: config.effectiveModel)
        case .gemini:
            guard !key.isEmpty else { throw LLMError(message: "Kein API-Schlüssel für Gemini hinterlegt.") }
            return OpenAICompatibleClient(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                                          apiKey: key, model: config.effectiveModel)
        case .mistral:
            guard !key.isEmpty else { throw LLMError(message: "Kein API-Schlüssel für Mistral hinterlegt.") }
            return OpenAICompatibleClient(baseURL: "https://api.mistral.ai/v1", apiKey: key, model: config.effectiveModel)
        case .lmStudio, .openAICompatible:
            return OpenAICompatibleClient(baseURL: config.effectiveBaseURL, apiKey: key, model: config.effectiveModel)
        case .claudeCode:
            return CLIClient(tool: .claude, model: config.model)
        case .codex:
            return CLIClient(tool: .codex, model: config.model)
        }
    }

    /// Verfügbare Modelle beim Anbieter abfragen (für die Auswahlliste).
    static func listModels(_ config: AIConfig) async throws -> [String] {
        let key = Keychain.apiKey(for: config.provider) ?? ""
        switch config.provider {
        case .ollama:
            return try await OllamaClient(baseURL: config.effectiveBaseURL, model: "").listModels()
        case .anthropic:
            return try await AnthropicClient(apiKey: key, model: "").listModels()
        case .openAI:
            return try await OpenAICompatibleClient(baseURL: "https://api.openai.com/v1", apiKey: key, model: "").listModels()
                .filter { $0.hasPrefix("gpt") || $0.hasPrefix("o") }
        case .gemini:
            return try await OpenAICompatibleClient(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", apiKey: key, model: "")
                .listModels().map { $0.replacingOccurrences(of: "models/", with: "") }
                .filter { $0.hasPrefix("gemini") }
        case .mistral:
            return try await OpenAICompatibleClient(baseURL: "https://api.mistral.ai/v1", apiKey: key, model: "").listModels()
        case .lmStudio, .openAICompatible:
            return try await OpenAICompatibleClient(baseURL: config.effectiveBaseURL, apiKey: key, model: "").listModels()
        default:
            return []
        }
    }
}

// MARK: - HTTP

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()

    static func json(_ url: String, method: String = "POST", headers: [String: String] = [:],
                     body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw LLMError(message: "Ungültige Adresse: \(url)") }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        var lastError: Error?
        for attempt in 0..<4 {
            do {
                let (data, response) = try await session.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                if (200..<300).contains(status) { return obj }
                let msg = Self.errorMessage(obj) ?? String(data: data, encoding: .utf8) ?? ""
                if [429, 500, 502, 503, 504, 529].contains(status) && attempt < 3 {
                    lastError = LLMError(message: "HTTP \(status): \(msg)")
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000)
                    continue
                }
                throw LLMError(message: "HTTP \(status): \(msg.prefix(400))")
            } catch let error as URLError {
                lastError = error
                if error.code == .cannotConnectToHost {
                    throw LLMError(message: "Keine Verbindung zu \(u.host ?? url). Läuft der Dienst?")
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        throw lastError ?? LLMError(message: "Unbekannter Fehler")
    }

    private static func errorMessage(_ obj: [String: Any]) -> String? {
        if let e = obj["error"] as? [String: Any] { return e["message"] as? String }
        if let e = obj["error"] as? String { return e }
        return nil
    }
}

// MARK: - Anbieter

struct AnthropicClient: LLMClient {
    let apiKey: String
    let model: String
    private var headers: [String: String] { ["x-api-key": apiKey, "anthropic-version": "2023-06-01"] }

    func complete(system: String, prompt: String) async throws -> String {
        let res = try await HTTP.json("https://api.anthropic.com/v1/messages", headers: headers, body: [
            "model": model, "max_tokens": 8_000, "system": system,
            "messages": [["role": "user", "content": prompt]],
        ])
        let blocks = res["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw LLMError(message: "Leere Antwort von Claude") }
        return text
    }

    func listModels() async throws -> [String] {
        let res = try await HTTP.json("https://api.anthropic.com/v1/models?limit=100", method: "GET", headers: headers)
        return (res["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }
}

struct OpenAICompatibleClient: LLMClient {
    let baseURL: String
    let apiKey: String
    let model: String
    private var base: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }
    private var headers: [String: String] { apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(apiKey)"] }

    func complete(system: String, prompt: String) async throws -> String {
        var body: [String: Any] = [
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
        ]
        if !model.isEmpty { body["model"] = model }
        let res = try await HTTP.json("\(base)/chat/completions", headers: headers, body: body)
        let choices = res["choices"] as? [[String: Any]] ?? []
        let text = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !text.isEmpty else { throw LLMError(message: "Leere Antwort vom Modell") }
        return text.removingThinkBlocks
    }

    func listModels() async throws -> [String] {
        let res = try await HTTP.json("\(base)/models", method: "GET", headers: headers)
        return (res["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted()
    }
}

struct OllamaClient: LLMClient {
    let baseURL: String
    let model: String
    private var base: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }

    func complete(system: String, prompt: String) async throws -> String {
        let res = try await HTTP.json("\(base)/api/chat", body: [
            "model": model, "stream": false,
            "options": ["num_ctx": 16_384, "temperature": 0.2],
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
        ])
        let text = (res["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !text.isEmpty else { throw LLMError(message: "Leere Antwort von Ollama") }
        return text.removingThinkBlocks
    }

    func listModels() async throws -> [String] {
        let res = try await HTTP.json("\(base)/api/tags", method: "GET")
        return (res["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    }
}

extension String {
    var removingThinkBlocks: String {
        replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
