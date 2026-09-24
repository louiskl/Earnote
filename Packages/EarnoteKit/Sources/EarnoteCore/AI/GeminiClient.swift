import Foundation

/// Google Gemini über die OpenAI-kompatible Schnittstelle. Google zieht einzelne Modellversionen nach einiger Zeit
/// zurück – neue Schlüssel bekommen dann „HTTP 404 … no longer available“. Deshalb ist der Standard der Alias
/// `gemini-flash-latest`, und fehlt ein Modell trotzdem, nimmt der Client das beste Flash-Modell aus der Liste
/// des Schlüssels. Fehler, die Einsteigern begegnen (falscher Schlüssel, Kontingent), werden verständlich übersetzt.
public struct GeminiClient: LLMClient {
    public static let baseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
    /// Zeigt immer auf das aktuelle Flash-Modell
    public static let defaultModel = "gemini-flash-latest"

    public let apiKey: String
    public let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? Self.defaultModel : model
    }

    private func client(_ model: String) -> OpenAICompatibleClient {
        OpenAICompatibleClient(baseURL: Self.baseURL, apiKey: apiKey, model: model)
    }

    public func complete(system: String, prompt: String) async throws -> String {
        do {
            return try await client(model).complete(system: system, prompt: prompt)
        } catch let error as LLMError where Self.isModelUnavailable(error) {
            let available = (try? await listModels()) ?? []
            guard let replacement = GeminiModels.best(available), replacement != model else { throw Self.friendly(error) }
            Log.info("Gemini: \(model) nicht verfügbar, nehme \(replacement)")
            do {
                return try await client(replacement).complete(system: system, prompt: prompt)
            } catch let error as LLMError {
                throw Self.friendly(error)
            }
        } catch let error as LLMError {
            throw Self.friendly(error)
        }
    }

    /// Modelle, die dieser Schlüssel nutzen darf (ohne „models/“ davor)
    public func listModels() async throws -> [String] {
        try await client("").listModels()
            .map { $0.replacingOccurrences(of: "models/", with: "") }
            .filter { $0.hasPrefix("gemini") }
    }

    static func isModelUnavailable(_ error: LLMError) -> Bool {
        let text = error.message.lowercased()
        return text.hasPrefix("http 404") || text.contains("no longer available") || text.contains("is not found for api version")
            || text.contains("not supported for generatecontent")
    }

    /// Die rohen Fehler von Google sind englisch und technisch – Einsteiger sollen wissen, was zu tun ist
    static func friendly(_ error: LLMError) -> LLMError {
        let text = error.message.lowercased()
        if text.contains("api key not valid") || text.contains("api_key_invalid") || text.hasPrefix("http 401")
            || text.hasPrefix("http 403") {
            return LLMError(message: t("Google nimmt den Gemini-Schlüssel nicht an. Prüfe, ob du ihn vollständig kopiert hast."))
        }
        if text.hasPrefix("http 429") || text.contains("resource_exhausted") || text.contains("quota") {
            return LLMError(message: t("Das kostenlose Kontingent von Gemini ist gerade aufgebraucht. Versuche es in ein paar Minuten erneut."))
        }
        if isModelUnavailable(error) {
            return LLMError(message: t("Google bietet das gewählte Gemini-Modell nicht mehr an. Wähle in den Einstellungen ein anderes Modell oder lass das Feld leer."))
        }
        return error
    }
}

public enum GeminiModels {
    /// Varianten, die für Notizen nicht taugen oder sich bald ändern
    private static let excluded = ["lite", "preview", "exp", "tts", "image", "audio", "live", "embedding", "thinking", "learnlm", "gemma"]

    /// Bestes Flash-Modell aus der Liste des Schlüssels: der Alias, sonst die höchste stabile Version
    public static func best(_ models: [String]) -> String? {
        if models.contains(GeminiClient.defaultModel) { return GeminiClient.defaultModel }
        let flash = models.filter { $0.hasPrefix("gemini-") && $0.contains("flash") }
        let stable = flash.filter { name in !excluded.contains { name.contains($0) } }
        return stable.max { version($0) < version($1) } ?? flash.first
    }

    /// „gemini-2.5-flash“ → 2.5
    static func version(_ name: String) -> Double {
        let parts = name.split(separator: "-")
        return parts.count > 1 ? Double(parts[1]) ?? 0 : 0
    }
}
