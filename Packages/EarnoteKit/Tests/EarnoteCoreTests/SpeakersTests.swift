import XCTest
@testable import EarnoteCore

final class SpeakersTests: XCTestCase {
    private let transcript = Transcript(segments: [
        TranscriptSegment(start: 0, end: 10, text: "Guten Morgen, heute Eigenwerte."),
        TranscriptSegment(start: 10, end: 14, text: "Kommt das in der Klausur?"),
        TranscriptSegment(start: 16, end: 30, text: "Ja, ganz sicher."),
    ], engine: "test")

    func testAssignsByLargestOverlapNumberedByFirstAppearance() {
        let turns = [SpeakerTurn(start: 0, end: 9.5, speaker: "B"), SpeakerTurn(start: 9.5, end: 15, speaker: "A"),
                     SpeakerTurn(start: 15.5, end: 30, speaker: "B")]
        let result = Speakers.assign(turns, to: transcript)
        XCTAssertEqual(result.segments.map(\.speaker), ["Sprecher 1", "Sprecher 2", "Sprecher 1"])
        XCTAssertEqual(Speakers.names(in: result), ["Sprecher 1", "Sprecher 2"])
    }

    func testSingleVoiceLeavesTranscriptUnchanged() {
        let result = Speakers.assign([SpeakerTurn(start: 0, end: 30, speaker: "A")], to: transcript)
        XCTAssertEqual(result.segments.map(\.speaker), [nil, nil, nil])
    }

    func testRenameChangesTranscriptAndNote() {
        let turns = [SpeakerTurn(start: 0, end: 10, speaker: "A"), SpeakerTurn(start: 10, end: 30, speaker: "B")]
        let named = Speakers.assign(turns, to: transcript)
        let (renamed, note) = Speakers.rename("Sprecher 1", to: "Prof. Klein", transcript: named,
                                              note: "Sprecher 1 erklärt Eigenwerte, Sprecher 2 fragt nach.")
        XCTAssertEqual(renamed.segments.first?.speaker, "Prof. Klein")
        XCTAssertEqual(note, "Prof. Klein erklärt Eigenwerte, Sprecher 2 fragt nach.")
    }

    func testTinyThirdVoiceIsIgnored() {
        let turns = [SpeakerTurn(start: 0, end: 10, speaker: "A"), SpeakerTurn(start: 10, end: 10.2, speaker: "X"),
                     SpeakerTurn(start: 10.2, end: 30, speaker: "B")]
        let result = Speakers.assign(turns, to: transcript)
        XCTAssertEqual(Speakers.names(in: result), ["Sprecher 1", "Sprecher 2"])
    }
}
