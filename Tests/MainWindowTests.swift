import EarnoteCore
import XCTest
@testable import Earnote

/// Kleine Hilfen des neuen Hauptfensters (Phase 2a)
final class MainWindowTests: XCTestCase {
    func testDurationIsReadableAndNotAClockTime() {
        XCTAssertEqual(MainWindowFormat.duration(48), "48 Sek.")
        XCTAssertEqual(MainWindowFormat.duration(0), "0 Sek.")
        // „36:00“ liest sich wie eine Uhrzeit, „36 Min.“ nicht
        XCTAssertEqual(MainWindowFormat.duration(36 * 60), "36 Min.")
        XCTAssertTrue(MainWindowFormat.duration(89 * 60).contains("1 Std."))
        XCTAssertTrue(MainWindowFormat.duration(89 * 60).contains("29 Min."))
    }

    func testLevelMapsQuietToZeroAndLoudToOne() {
        XCTAssertEqual(MainWindowFormat.level(0), 0)
        XCTAssertEqual(MainWindowFormat.level(1), 1, accuracy: 0.001)
        // −50 dB ist die untere Grenze der Anzeige
        XCTAssertEqual(MainWindowFormat.level(pow(10, -50 / 20)), 0, accuracy: 0.001)
        let half = MainWindowFormat.level(pow(10, -25 / 20))
        XCTAssertEqual(half, 0.5, accuracy: 0.01)
    }

    func testLanguageNameFallsBackToTheCode() {
        XCTAssertEqual(MainWindowFormat.language("de"), "Deutsch")
        XCTAssertEqual(MainWindowFormat.language("xx"), "xx")
    }

    func testDetailModeSurvivesTheSceneStorageRoundTrip() {
        XCTAssertEqual(DetailMode(rawValue: DetailMode.transcript.rawValue), .transcript)
        XCTAssertNil(DetailMode(rawValue: "unbekannt"))
    }
}
