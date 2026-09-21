import EarnoteCore
import EventKit
import PDFKit
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
        // Der Name kommt vom System und heißt je nach Oberflächensprache „Deutsch“ oder „German“
        XCTAssertEqual(MainWindowFormat.language("de"), Locale.current.localizedString(forLanguageCode: "de")?.localizedCapitalized)
        XCTAssertEqual(MainWindowFormat.language("xx"), "xx")
    }

    /// Welcher Termin gibt den Titel? Ohne Kalenderzugriff prüfbar, weil die Auswahl für sich steht.
    @MainActor
    func testCalendarPicksTheShortestRunningEvent() {
        let store = EKEventStore()
        let now = Date()
        func event(_ title: String, from: TimeInterval, to: TimeInterval, allDay: Bool = false) -> EKEvent {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = now.addingTimeInterval(from)
            event.endDate = now.addingTimeInterval(to)
            event.isAllDay = allDay
            return event
        }
        let events = [
            event("Semesterferien", from: -3600, to: 3600, allDay: true),
            event("Uni-Tag", from: -3 * 3600, to: 3 * 3600),
            event("Analysis II", from: -600, to: 3000),
            event("Mittagessen", from: 3 * 3600, to: 4 * 3600),
            event("Schon vorbei", from: -7200, to: -60),
        ]
        XCTAssertEqual(CalendarTitles.pick(from: events, now: now), "Analysis II")
        XCTAssertNil(CalendarTitles.pick(from: [events[0], events[4]], now: now),
                     "ganztägig und vorbei zählen beide nicht")
        // Ein Termin, der in fünf Minuten beginnt, zählt schon (man startet vorher)
        XCTAssertEqual(CalendarTitles.pick(from: [event("Lineare Algebra", from: 300, to: 3600)], now: now),
                       "Lineare Algebra")
        XCTAssertNil(CalendarTitles.pick(from: [event("Erst in einer Stunde", from: 3600, to: 7200)], now: now))
    }

    @MainActor
    func testSearchCursorWrapsAroundInBothDirections() {
        let cursor = SearchCursor()
        // Ohne Fundstellen passiert nichts
        cursor.next()
        XCTAssertEqual(cursor.index, 0)
        XCTAssertEqual(cursor.count, 0)

        cursor.reset(count: 3)
        cursor.next()
        XCTAssertEqual(cursor.index, 1)
        cursor.next()
        cursor.next()
        XCTAssertEqual(cursor.index, 0, "nach der letzten Fundstelle geht es wieder von vorn los")
        cursor.previous()
        XCTAssertEqual(cursor.index, 2, "rückwärts von der ersten zur letzten")

        // Neue Suche zählt von vorn
        cursor.reset(count: 1)
        XCTAssertEqual(cursor.index, 0)
        cursor.next()
        XCTAssertEqual(cursor.index, 0, "eine einzige Fundstelle bleibt stehen")
    }

    func testDetailModeSurvivesTheSceneStorageRoundTrip() {
        XCTAssertEqual(DetailMode(rawValue: DetailMode.transcript.rawValue), .transcript)
        XCTAssertNil(DetailMode(rawValue: "unbekannt"))
    }
}

/// Lernzettel: Satz und PDF (Phase 3c)
@MainActor
final class NoteDocumentTests: XCTestCase {
    private let markdown = """
        Eine Kurzfassung mit **fettem** Wort.

        ## Thema [00:12:30]
        - Erster Punkt
        - Zweiter Punkt

        ## Aufgaben
        - [ ] Übungsblatt rechnen
        - [x] Skript lesen
        """

    func testAttributedNoteKeepsEveryBlock() {
        let text = NoteDocument.attributed(title: "Analysis II", subtitle: "18. Sept. · 90 Min.", markdown: markdown).string
        XCTAssertTrue(text.hasPrefix("Analysis II\n18. Sept. · 90 Min."), text)
        XCTAssertTrue(text.contains("Thema  00:12:30"), "Zeitmarke steht hinter der Überschrift")
        XCTAssertTrue(text.contains("•\tErster Punkt"))
        XCTAssertTrue(text.contains("☐\tÜbungsblatt rechnen"), "Offene Aufgabe als leeres Kästchen")
        XCTAssertTrue(text.contains("☑\tSkript lesen"), "Erledigte Aufgabe abgehakt")
        XCTAssertFalse(text.contains("**"), "Markdown-Zeichen gehören nicht ins PDF")
    }

    func testWritesPDFWithAtLeastOnePage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lernzettel-Test-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = NoteDocument.attributed(title: "Analysis II", subtitle: "Test",
                                           markdown: Array(repeating: markdown, count: 12).joined(separator: "\n\n"))
        try NoteDocument.writePDF(text, title: "Analysis II", to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 1, "Lange Notizen brechen auf mehrere Seiten um")
        XCTAssertTrue(document.string?.contains("Übungsblatt rechnen") == true, "Der Text steht im PDF")
    }
}
