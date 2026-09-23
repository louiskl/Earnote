import Foundation

public protocol LLMClient: Sendable {
    func complete(system: String, prompt: String) async throws -> String
    /// Wie `complete`, meldet aber zwischendurch den bisher geschriebenen Text – damit die Notiz beim Entstehen
    /// sichtbar wird, statt nach Minuten auf einmal. Wer nicht schrittweise liefern kann, meldet nichts.
    func complete(system: String, prompt: String, partial: @escaping @Sendable (String) -> Void) async throws -> String
}

public extension LLMClient {
    func complete(system: String, prompt: String, partial: @escaping @Sendable (String) -> Void) async throws -> String {
        try await complete(system: system, prompt: prompt)
    }
}

public struct LLMError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }

    public init(message: String) { self.message = message }
}

// MARK: - HTTP

public enum HTTP {
    public static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()

    public static func json(_ url: String, method: String = "POST", headers: [String: String] = [:],
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

public struct AnthropicClient: LLMClient {
    public let apiKey: String
    public let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    private var headers: [String: String] { ["x-api-key": apiKey, "anthropic-version": "2023-06-01"] }

    public func complete(system: String, prompt: String) async throws -> String {
        let res = try await HTTP.json("https://api.anthropic.com/v1/messages", headers: headers, body: [
            "model": model, "max_tokens": 8_000, "system": system,
            "messages": [["role": "user", "content": prompt]],
        ])
        let blocks = res["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw LLMError(message: "Leere Antwort von Claude") }
        return text
    }

    public func listModels() async throws -> [String] {
        let res = try await HTTP.json("https://api.anthropic.com/v1/models?limit=100", method: "GET", headers: headers)
        return (res["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }
}

public struct OpenAICompatibleClient: LLMClient {
    public let baseURL: String
    public let apiKey: String
    public let model: String

    public init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
    private var base: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }
    private var headers: [String: String] { apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(apiKey)"] }

    public func complete(system: String, prompt: String) async throws -> String {
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

    public func listModels() async throws -> [String] {
        let res = try await HTTP.json("\(base)/models", method: "GET", headers: headers)
        return (res["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted()
    }
}

public struct OllamaClient: LLMClient {
    public let baseURL: String
    public let model: String

    public init(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }
    private var base: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }

    public func complete(system: String, prompt: String) async throws -> String {
        let res = try await HTTP.json("\(base)/api/chat", body: [
            "model": model, "stream": false,
            "options": ["num_ctx": 16_384, "temperature": 0.2],
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
        ])
        let text = (res["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !text.isEmpty else { throw LLMError(message: "Leere Antwort von Ollama") }
        return text.removingThinkBlocks
    }

    public func listModels() async throws -> [String] {
        let res = try await HTTP.json("\(base)/api/tags", method: "GET")
        return (res["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    }
}

extension String {
    public var removingThinkBlocks: String {
        replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
