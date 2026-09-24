import Foundation

/// OpenRouter mit kostenlosen Modellen (Kennung endet auf „:free“). Welche Modelle kostenlos sind, wechselt oft –
/// deshalb wählt der Client ohne festes Modell selbst aus der öffentlichen Liste und nimmt das nächste, wenn eines
/// gerade nicht erreichbar ist. Kostenlose Anbieter dürfen den Text zum Training nutzen; OpenRouter verlangt dafür
/// eine Freigabe in den eigenen Datenschutz-Einstellungen – fehlt sie, sagt Earnote genau das.
public struct OpenRouterClient: LLMClient {
    public static let baseURL = "https://openrouter.ai/api/v1"
    public static let keysPage = URL(string: "https://openrouter.ai/settings/keys")!
    public static let privacyPage = URL(string: "https://openrouter.ai/settings/privacy")!

    public let apiKey: String
    /// Leer = selbst ein kostenloses Modell wählen
    public let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    public func complete(system: String, prompt: String) async throws -> String {
        let candidates = model.isEmpty ? try await OpenRouterModels.freeCandidates() : [model]
        guard !candidates.isEmpty else { throw LLMError(message: t("OpenRouter bietet gerade kein kostenloses Modell an.")) }
        var lastError: LLMError?
        for (index, candidate) in candidates.prefix(4).enumerated() {
            do {
                let text = try await OpenAICompatibleClient(baseURL: Self.baseURL, apiKey: apiKey, model: candidate)
                    .complete(system: system, prompt: prompt)
                if index > 0 { Log.info("OpenRouter: \(candidates[0]) nicht verfügbar, nehme \(candidate)") }
                return text
            } catch let error as LLMError {
                lastError = error
                // Schlüssel oder Freigabe fehlen – dann hilft kein anderes Modell
                guard model.isEmpty, Self.tryNext(error) else { throw Self.friendly(error) }
            }
        }
        throw Self.friendly(lastError ?? LLMError(message: t("OpenRouter bietet gerade kein kostenloses Modell an.")))
    }

    /// Nur die kostenlosen Modelle – für die Auswahlliste
    public func listModels() async throws -> [String] {
        try await OpenRouterModels.freeCandidates()
    }

    /// Dieses Modell geht gerade nicht, ein anderes vielleicht schon
    static func tryNext(_ error: LLMError) -> Bool {
        let text = error.message.lowercased()
        if isDataPolicy(text) { return false }
        return text.hasPrefix("http 404") || text.hasPrefix("http 429") || text.hasPrefix("http 502") || text.hasPrefix("http 503")
            || text.contains("no endpoints found") || text.contains("not a valid model") || text.contains("leere antwort")
    }

    private static func isDataPolicy(_ text: String) -> Bool {
        text.contains("data policy") || text.contains("privacy settings")
    }

    /// Die rohen Fehler von OpenRouter sind englisch und technisch – Einsteiger sollen wissen, was zu tun ist
    static func friendly(_ error: LLMError) -> LLMError {
        let text = error.message.lowercased()
        if text.hasPrefix("http 401") || text.contains("no auth credentials") || text.contains("user not found") {
            return LLMError(message: t("OpenRouter nimmt den Schlüssel nicht an. Prüfe, ob du ihn vollständig kopiert hast."))
        }
        if isDataPolicy(text) {
            return LLMError(message: t("Erlaube bei OpenRouter unter Einstellungen › Datenschutz die kostenlosen Modelle (openrouter.ai/settings/privacy) und versuche es erneut."))
        }
        if text.hasPrefix("http 429") || text.contains("rate limit") {
            return LLMError(message: t("Das kostenlose Tageslimit von OpenRouter ist erreicht. Versuche es später erneut oder wähle einen anderen Weg."))
        }
        return error
    }
}

public enum OpenRouterModels {
    /// Bevorzugte Familien, beste zuerst – gute deutsche Texte und langer Kontext
    private static let preferred = ["deepseek-chat", "deepseek-v3", "qwen3", "llama-3.3-70b", "gemma-3-27b", "mistral-small", "llama-4"]
    /// Taugen nicht für Notizen
    private static let excluded = ["vision", "-vl", "coder", "embed", "guard", "audio", "image"]

    /// Kostenlose Modelle aus der öffentlichen Liste, in der Reihenfolge, in der Earnote sie probiert
    public static func freeCandidates() async throws -> [String] {
        let res = try await HTTP.json("\(OpenRouterClient.baseURL)/models", method: "GET")
        return rank(res["data"] as? [[String: Any]] ?? [])
    }

    /// Reihenfolge: bevorzugte Familie, dann größerer Kontext. Mindestens 32.000 Token Kontext.
    static func rank(_ models: [[String: Any]]) -> [String] {
        let free = models.compactMap { model -> (id: String, context: Int)? in
            guard let id = model["id"] as? String, id.hasSuffix(":free"),
                  !excluded.contains(where: { id.lowercased().contains($0) }) else { return nil }
            let context = model["context_length"] as? Int ?? 0
            return context >= 32_000 ? (id, context) : nil
        }
        func rank(_ id: String) -> Int { preferred.firstIndex { id.lowercased().contains($0) } ?? preferred.count }
        return free.sorted { a, b in
            rank(a.id) != rank(b.id) ? rank(a.id) < rank(b.id) : a.context > b.context
        }.map(\.id)
    }
}
