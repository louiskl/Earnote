import EarnoteCore
import EarnoteML
import XCTest
@testable import Earnote

/// Whisper-Modellauswahl: Fehlt das eingestellte Modell, muss die App sagen, welches sie wirklich nimmt.
final class WhisperSelectionTests: XCTestCase {
    @MainActor
    func testFallbackReportsActuallyUsedModel() throws {
        let manager = WhisperModelManager.shared
        guard let expected = manager.installed.keys.sorted().first else { throw XCTSkip("Kein Modell installiert") }
        let selected = try XCTUnwrap(manager.installedFolder(for: "missing-phase0-test-model"))
        XCTAssertEqual(selected.model, expected)
        XCTAssertEqual(manager.installedFolder(for: expected)?.model, expected)
        var settings = AppSettings()
        settings.whisperModel = "missing-phase0-test-model"
        let transcriber = try TranscriberFactory.make(for: settings)
        XCTAssertEqual(transcriber.engineName, "Whisper \(expected)")
    }
}
