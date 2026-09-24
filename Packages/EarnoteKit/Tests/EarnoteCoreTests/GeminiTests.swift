import XCTest
@testable import EarnoteCore

/// Google zieht Gemini-Modelle zurück – Earnote soll dann selbst ein passendes finden
final class GeminiTests: XCTestCase {
    func testPrefersTheLatestAlias() {
        XCTAssertEqual(GeminiModels.best(["gemini-2.5-flash", "gemini-flash-latest", "gemini-3.0-flash"]), "gemini-flash-latest")
    }

    func testOtherwiseHighestStableFlash() {
        let models = ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-3.0-flash-preview", "gemini-3.0-flash-lite",
                      "gemini-2.5-pro", "gemini-3.0-flash-image"]
        XCTAssertEqual(GeminiModels.best(models), "gemini-2.5-flash")
    }

    func testFallsBackToAnyFlashAndNilWithoutOne() {
        XCTAssertEqual(GeminiModels.best(["gemini-3.0-flash-preview"]), "gemini-3.0-flash-preview")
        XCTAssertNil(GeminiModels.best(["gemini-2.5-pro"]))
    }

    func testRecognizesRetiredModels() {
        XCTAssertTrue(GeminiClient.isModelUnavailable(LLMError(message: "HTTP 404: models/gemini-2.5-flash is no longer available to new users")))
        XCTAssertFalse(GeminiClient.isModelUnavailable(LLMError(message: "HTTP 429: quota exceeded")))
    }

    func testBeginnerFriendlyErrors() {
        // Sprachunabhängig prüfen: Die Tests laufen auch mit englischer Oberfläche
        let rawKey = "HTTP 400: API key not valid. Please pass a valid API key."
        let key = GeminiClient.friendly(LLMError(message: rawKey))
        XCTAssertNotEqual(key.message, rawKey, "Falscher Schlüssel wird übersetzt")
        let rawQuota = "HTTP 429: RESOURCE_EXHAUSTED"
        let quota = GeminiClient.friendly(LLMError(message: rawQuota))
        XCTAssertNotEqual(quota.message, rawQuota, "Kontingent wird übersetzt")
        XCTAssertNotEqual(key.message, quota.message)
        let other = LLMError(message: "Keine Verbindung")
        XCTAssertEqual(GeminiClient.friendly(other).message, "Keine Verbindung")
    }

    /// So antwortet Google auf einen falschen Schlüssel beim Einrichten (am iPhone gesehen, 24.09.2026)
    func testInvalidKeyAs400IsFriendly() {
        let raw = #"HTTP 400: [{ "error": { "code": 400, "message": "Please pass a valid API key", "status": "INVALID_ARGUMENT" } }]"#
        XCTAssertFalse(GeminiClient.friendly(LLMError(message: raw)).message.hasPrefix("HTTP"))
    }

    func testEmptyModelUsesAlias() {
        XCTAssertEqual(GeminiClient(apiKey: "k", model: "").model, GeminiClient.defaultModel)
        XCTAssertEqual(AIProviderKind.gemini.defaultModel, GeminiClient.defaultModel)
    }
}
