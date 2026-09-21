import XCTest
@testable import EarnoteCore

/// Vorverdichten während der Aufnahme: Es darf nur vollständige Blöcke verdichten, nichts doppelt
/// verarbeiten und nach dem Stopp genau den Rest übrig lassen.
final class LiveCondenserTests: XCTestCase {
    private func context() -> SummaryContext {
        SummaryContext(category: nil, titleHint: "", sourceApp: nil, date: Date(), duration: 3600,
                       hasSpeakers: false, language: "Deutsch")
    }

    private func makeCondenser(block: Int, client: FakeLLMClient) -> LiveCondenser {
        LiveCondenser(summarizer: Summarizer(client: client, chunkCharacters: 20_000, providerName: "Test"),
                      context: context(), blockCharacters: block)
    }

    /// Zeilen à 100 Zeichen – so lässt sich am Zeilenumbruch schneiden
    private func transcript(lines: Int) -> String {
        (0..<lines).map { "Zeile \($0) " + String(repeating: "x", count: 90) }.joined(separator: "\n") + "\n"
    }

    func testNothingHappensUntilABlockIsFull() async {
        let client = FakeLLMClient(answer: "Notiz")
        let condenser = makeCondenser(block: 5_000, client: client)
        await condenser.advance(fullText: transcript(lines: 10))   // ~1000 Zeichen
        XCTAssertEqual(client.calls.get().count, 0, "für einen halben Block lohnt sich der Modellstart nicht")
        let nothing = await condenser.finish(fullText: transcript(lines: 10))
        XCTAssertNil(nothing, "ohne verdichteten Block gibt es nichts zu übergeben")
    }

    func testEachBlockIsCondensedOnceAndTheRestStaysRaw() async {
        let client = FakeLLMClient { call, index in
            XCTAssertTrue(FakeLLMClient.isCondense(call))
            return "Notiz \(index + 1)"
        }
        let condenser = makeCondenser(block: 5_000, client: client)
        let text = transcript(lines: 120)   // ~12 000 Zeichen

        await condenser.advance(fullText: text)
        await condenser.advance(fullText: text)
        XCTAssertEqual(client.calls.get().count, 2, "aus 12 000 Zeichen werden zwei volle Blöcke")

        let ready = await condenser.finish(fullText: text)
        XCTAssertEqual(ready?.notes, "Notiz 1\n\nNotiz 2")
        let tail = ready?.tail ?? ""
        XCTAssertTrue(tail.hasSuffix("\n"), "der Rest endet dort, wo das Transkript endet")
        // Kein Zeichen doppelt und keines verloren
        let consumed = text.count - tail.count
        XCTAssertTrue(consumed >= 9_000 && consumed <= 12_000, "verdichtet wurden \(consumed) Zeichen")
        XCTAssertTrue(text.hasSuffix(tail))
    }

    func testAFailingModelStopsQuietlyAndGivesNothingBack() async {
        let client = FakeLLMClient { _, _ in throw LLMError(message: "kein Speicher") }
        let condenser = makeCondenser(block: 2_000, client: client)
        let text = transcript(lines: 60)
        await condenser.advance(fullText: text)
        await condenser.advance(fullText: text)
        XCTAssertEqual(client.calls.get().count, 1, "nach einem Fehler wird nicht weiter versucht")
        let nothing = await condenser.finish(fullText: text)
        XCTAssertNil(nothing, "dann wird nach dem Stopp normal verdichtet")
    }

    /// Die Zusammenfassung muss das Vorverdichtete benutzen, statt alles noch einmal zu verdichten.
    func testSummarizerUsesPrecondensedMaterial() async throws {
        let client = FakeLLMClient { call, _ in
            FakeLLMClient.isCondense(call) ? "Verdichtet" : "# Titel\n\nFertige Notiz."
        }
        let summarizer = Summarizer(client: client, chunkCharacters: 20_000, providerName: "Test")
        let ready = PreCondensed(notes: "Block 1\n\nBlock 2", tail: "Der kurze Rest.")
        let summary = try await summarizer.summarize(transcript: transcript(lines: 300), context: context(),
                                                     precondensed: ready) { _ in }
        XCTAssertEqual(summary.title, "Titel")
        XCTAssertEqual(client.calls.get().filter { FakeLLMClient.isCondense($0) }.count, 0,
                       "ein kurzer Rest wird nicht noch einmal verdichtet")
        let finalPrompt = try XCTUnwrap(client.calls.get().last?.prompt)
        XCTAssertTrue(finalPrompt.contains("Block 1"), "die vorverdichteten Notizen gehen in die Notiz ein")
        XCTAssertTrue(finalPrompt.contains("Der kurze Rest."))
        XCTAssertFalse(finalPrompt.contains("Zeile 200"), "das rohe Transkript wird nicht noch einmal geschickt")
    }
}
