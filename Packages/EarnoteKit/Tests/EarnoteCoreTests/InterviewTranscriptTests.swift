#if canImport(AppKit)
import AppKit
#endif
import XCTest
@testable import EarnoteCore

final class InterviewTranscriptTests: XCTestCase {
    private let interview = Transcript(segments: [
        TranscriptSegment(start: 0, end: 4.2, text: "Schön, dass du da bist.", speaker: "Anna"),
        TranscriptSegment(start: 4.2, end: 8.0, text: "Wie bist du zum Studium gekommen?", speaker: "Anna"),
        TranscriptSegment(start: 8.0, end: 20.55, text: "Über meine Schwester.", speaker: "Ben"),
        TranscriptSegment(start: 20.55, end: 25.0, text: "Und warum gerade Jura?", speaker: "Anna"),
        TranscriptSegment(start: 25.0, end: 83.31, text: "Wegen {Klammern} und \\ Ärger.", speaker: "Ben"),
    ], engine: "test")

    func testParagraphsPerSpeakerWithInterviewerAsI() throws {
        let paragraphs = try XCTUnwrap(InterviewTranscript.paragraphs(interview))
        XCTAssertEqual(paragraphs.map(\.code), ["I", "B", "I", "B"])
        XCTAssertEqual(paragraphs[0].text, "Schön, dass du da bist. Wie bist du zum Studium gekommen?")
        XCTAssertEqual(paragraphs[0].end, 8.0)
    }

    func testInterviewerIsWhoAsksEvenIfNotFirst() throws {
        var swapped = interview
        swapped.segments.insert(TranscriptSegment(start: 0, end: 1, text: "Hallo.", speaker: "Ben"), at: 0)
        let paragraphs = try XCTUnwrap(InterviewTranscript.paragraphs(swapped))
        XCTAssertEqual(paragraphs.first?.code, "B")
    }

    func testThreeVoicesGetNumberedCodes() throws {
        var group = interview
        group.segments.append(TranscriptSegment(start: 90, end: 95, text: "Darf ich ergänzen.", speaker: "Cem"))
        XCTAssertEqual(try XCTUnwrap(InterviewTranscript.paragraphs(group)).map(\.code).last, "B2")
    }

    func testNeedsTwoSpeakers() {
        let alone = Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: "Hallo")], engine: "test")
        XCTAssertNil(InterviewTranscript.text(alone, title: "x", date: .now, duration: 1))
    }

    func testTextHasStampsAndLegend() throws {
        let text = try XCTUnwrap(InterviewTranscript.text(interview, title: "Interview 1", date: .now, duration: 83))
        XCTAssertTrue(text.contains("I = Anna, B = Ben"))
        XCTAssertTrue(text.contains("B: Über meine Schwester. #00:00:20-5#"))
        XCTAssertTrue(text.contains("#00:01:23-3#"))
    }

    func testRTFEscapesAndNumbersLines() throws {
        let rtf = try XCTUnwrap(InterviewTranscript.rtf(interview, title: "Interview 1", date: .now, duration: 83))
        XCTAssertTrue(rtf.hasPrefix("{\\rtf1"))
        XCTAssertTrue(rtf.contains("\\linemod1"))
        XCTAssertTrue(rtf.contains("Wegen \\{Klammern\\} und \\\\ \\u196?rger."))
        XCTAssertFalse(rtf.contains("Ä"))
    }

    #if canImport(AppKit)
    /// Das RTF muss sich so öffnen lassen, wie Word es liest: Umlaute, Klammern und Kürzel kommen heil an
    func testRTFOpensAsText() throws {
        let rtf = try XCTUnwrap(InterviewTranscript.rtf(interview, title: "Interview 1", date: .now, duration: 83))
        let text = try XCTUnwrap(NSAttributedString(rtf: Data(rtf.utf8), documentAttributes: nil)).string
        XCTAssertTrue(text.contains("I: Schön, dass du da bist. Wie bist du zum Studium gekommen? #00:00:08-0#"))
        XCTAssertTrue(text.contains("B: Wegen {Klammern} und \\ Ärger. #00:01:23-3#"))
    }
    #endif
}
