import XCTest
@testable import EarnoteCore

final class OpenRouterTests: XCTestCase {
    func testRanksPreferredFreeModelsWithEnoughContext() {
        let models: [[String: Any]] = [
            ["id": "openai/gpt-4o", "context_length": 128_000],                       // kostet
            ["id": "tiny/model:free", "context_length": 8_000],                        // zu wenig Kontext
            ["id": "qwen/qwen2.5-vl-72b-instruct:free", "context_length": 128_000],    // Bild-Modell
            ["id": "some/unknown-model:free", "context_length": 200_000],
            ["id": "meta-llama/llama-3.3-70b-instruct:free", "context_length": 64_000],
            ["id": "deepseek/deepseek-chat-v3-0324:free", "context_length": 64_000],
        ]
        XCTAssertEqual(OpenRouterModels.rank(models), [
            "deepseek/deepseek-chat-v3-0324:free",
            "meta-llama/llama-3.3-70b-instruct:free",
            "some/unknown-model:free",
        ])
    }

    func testTriesNextModelOnlyWhenAnotherCouldWork() {
        XCTAssertTrue(OpenRouterClient.tryNext(LLMError(message: "HTTP 404: No endpoints found for x:free.")))
        XCTAssertTrue(OpenRouterClient.tryNext(LLMError(message: "HTTP 429: x:free is temporarily rate-limited upstream")))
        XCTAssertFalse(OpenRouterClient.tryNext(LLMError(message: "HTTP 401: No auth credentials found")))
        XCTAssertFalse(OpenRouterClient.tryNext(LLMError(message: "HTTP 404: No endpoints found matching your data policy (Free model training)")))
    }

    /// Sprachunabhängig: Die Tests laufen auch mit englischer Oberfläche
    func testBeginnerFriendlyErrors() {
        let raws = ["HTTP 401: No auth credentials found",
                    "HTTP 404: No endpoints found matching your data policy (Free model training)",
                    "HTTP 429: Rate limit exceeded: free-models-per-day"]
        let messages = raws.map { OpenRouterClient.friendly(LLMError(message: $0)).message }
        for (raw, message) in zip(raws, messages) { XCTAssertNotEqual(raw, message) }
        XCTAssertEqual(Set(messages).count, 3, "Drei verschiedene Hinweise")
        XCTAssertEqual(OpenRouterClient.friendly(LLMError(message: "Keine Verbindung")).message, "Keine Verbindung")
    }

    func testProviderNeedsKeyAndSendsTextOffDevice() {
        XCTAssertTrue(AIProviderKind.openRouter.needsAPIKey)
        XCTAssertTrue(AIProviderKind.openRouter.sendsDataOffDevice)
        XCTAssertEqual(AIProviderKind.openRouter.defaultModel, "", "Leer: Earnote wählt selbst ein kostenloses Modell")
    }
}
