import XCTest
@testable import EarnoteCore

final class NoteChatTests: XCTestCase {
    private let transcript = Transcript(segments: [
        TranscriptSegment(start: 0, end: 30, text: "Heute geht es um lineare Abbildungen und Matrizen."),
        TranscriptSegment(start: 70, end: 100, text: "Ein Eigenwert ist eine Zahl, bei der die Abbildung nur streckt."),
        TranscriptSegment(start: 140, end: 170, text: "Das kommt in der Klausur: Eigenwerte über das charakteristische Polynom."),
        TranscriptSegment(start: 210, end: 240, text: "Nächste Woche machen wir Determinanten."),
    ], engine: "test")

    func testPassagesMatchWordStemsInTimeOrder() {
        let found = NoteChat.passages(for: "Was hat er zu Eigenwerten gesagt?", in: transcript)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found[0].contains("Eigenwert ist eine Zahl"))
        XCTAssertTrue(found[1].contains("charakteristische"))
    }

    func testNoPassagesWithoutMatchOrTranscript() {
        XCTAssertTrue(NoteChat.passages(for: "Wie ist das Wetter?", in: transcript).isEmpty)
        XCTAssertTrue(NoteChat.passages(for: "Eigenwerte", in: nil).isEmpty)
    }

    func testRequestKeepsRecentHistoryAndCapsNote() {
        let history = (0..<10).map { NoteChat.Message(fromUser: $0 % 2 == 0, text: "Nachricht \($0)") }
        let (_, prompt) = NoteChat.request(title: "Analysis", note: String(repeating: "x", count: 20_000),
                                           passages: ["[00:01:10] Stelle"], history: history, question: "Und jetzt?")
        XCTAssertFalse(prompt.contains("Nachricht 3"))
        XCTAssertTrue(prompt.contains("Nachricht 9"))
        XCTAssertTrue(prompt.contains("[00:01:10] Stelle"))
        XCTAssertTrue(prompt.hasSuffix("Und jetzt?"))
        XCTAssertLessThan(prompt.count, 14_000)
    }

    func testAskSendsNoteAndMatchingPassagesOnly() async throws {
        let client = FakeLLMClient(answer: "  Ein Eigenwert streckt nur. [00:01:10]  ")
        let answer = try await NoteChat.ask(client: client, title: "Analysis", note: "# Eigenwerte\nKurz erklärt",
                                            transcript: transcript, history: [], question: "Was ist ein Eigenwert?") { _ in }
        XCTAssertEqual(answer, "Ein Eigenwert streckt nur. [00:01:10]")
        let prompt = try XCTUnwrap(client.calls.mutate { $0.first?.prompt })
        XCTAssertTrue(prompt.contains("Kurz erklärt"))
        XCTAssertTrue(prompt.contains("nur streckt"))
        XCTAssertFalse(prompt.contains("Determinanten"))
    }
}
