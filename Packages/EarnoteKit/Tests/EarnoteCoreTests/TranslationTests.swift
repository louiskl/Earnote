import XCTest
@testable import EarnoteCore

final class TranslationTests: XCTestCase {
    func testChunksKeepLinesWhole() {
        let lines = (0..<10).map { String(repeating: "\($0)", count: 30) }
        let parts = Translation.chunks(lines, limit: 100)
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts.joined(separator: "\n"), lines.joined(separator: "\n"))
    }

    func testTranscriptKeepsOnlyTimestampedLines() async throws {
        let transcript = Transcript(segments: [
            TranscriptSegment(start: 0, end: 5, text: "Guten Morgen."),
            TranscriptSegment(start: 70, end: 75, text: "Heute Eigenwerte."),
        ], engine: "test")
        let client = FakeLLMClient(answer: "Hier die Übersetzung:\n[00:00:00] Good morning.\n[00:01:10] Eigenvalues today.")
        let lines = try await Translation.transcript(transcript, to: "Englisch", client: client)
        XCTAssertEqual(lines, ["[00:00:00] Good morning.", "[00:01:10] Eigenvalues today."])
        let system = try XCTUnwrap(client.calls.mutate { $0.first?.system })
        XCTAssertTrue(system.contains("Englisch"))
    }
}
