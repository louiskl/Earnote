import XCTest
@testable import EarnoteCore

final class ExamRadarTests: XCTestCase {
    func testItemsComeOnlyFromExamSections() {
        let note = """
        Kurzfassung der Vorlesung.
        ## Rechenweg
        - Polynom aufstellen
        ## Wichtig für die Klausur
        - Diagonalisierbarkeit prüfen
        1. Doppelte Nullstellen beachten
        ## Aufgaben
        - [ ] Übungsblatt 4
        ## Exam tips
        - Know the definition
        """
        XCTAssertEqual(ExamRadar.items(in: note),
                       ["Diagonalisierbarkeit prüfen", "Doppelte Nullstellen beachten", "Know the definition"])
    }

    func testMarksRoundTripAndInstructionQuotesWhatWasSaidBefore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(ImportantMarks.load(in: folder), [])
        ImportantMarks.append(95, in: folder)
        ImportantMarks.append(12, in: folder)
        XCTAssertEqual(ImportantMarks.load(in: folder), [95, 12])

        let transcript = Transcript(segments: [
            TranscriptSegment(start: 0, end: 10, text: "Einleitung."),
            TranscriptSegment(start: 80, end: 92, text: "Das kommt sicher dran."),
            TranscriptSegment(start: 200, end: 210, text: "Später."),
        ], engine: "test")
        let text = ImportantMarks.instruction(marks: [95], transcript: transcript)
        XCTAssertTrue(text.contains("[00:01:35] „Das kommt sicher dran.“"))
        XCTAssertFalse(text.contains("Später"))
        XCTAssertEqual(ImportantMarks.instruction(marks: [], transcript: transcript), "")
    }
}
