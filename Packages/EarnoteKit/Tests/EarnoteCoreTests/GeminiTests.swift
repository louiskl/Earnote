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
        let key = GeminiClient.friendly(LLMError(message: "HTTP 400: API key not valid. Please pass a valid API key."))
        XCTAssertTrue(key.message.contains("Schlüssel"))
        let quota = GeminiClient.friendly(LLMError(message: "HTTP 429: RESOURCE_EXHAUSTED"))
        XCTAssertTrue(quota.message.contains("Kontingent"))
        let other = LLMError(message: "Keine Verbindung")
        XCTAssertEqual(GeminiClient.friendly(other).message, "Keine Verbindung")
    }

    func testEmptyModelUsesAlias() {
        XCTAssertEqual(GeminiClient(apiKey: "k", model: "").model, GeminiClient.defaultModel)
        XCTAssertEqual(AIProviderKind.gemini.defaultModel, GeminiClient.defaultModel)
    }
}
