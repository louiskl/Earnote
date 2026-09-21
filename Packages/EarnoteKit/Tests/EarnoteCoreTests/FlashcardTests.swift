import XCTest
@testable import EarnoteCore

/// Karteikarten leben als Zeilen in der Notiz – Lesen, Schreiben und Ersetzen müssen zusammenpassen.
final class FlashcardTests: XCTestCase {
    func testParsesCardsRegardlessOfBulletAndHeading() {
        let markdown = """
        ## Karteikarten

        - Was ist ein Eigenwert? :: Ein Skalar λ mit A·v = λ·v für einen Vektor v ≠ 0.
        * Wie findet man sie? :: Über die Nullstellen des charakteristischen Polynoms.
        Ohne Trennzeichen bleibt es normaler Text.
        -  :: Antwort ohne Frage
        """
        let cards = Flashcards.parse(markdown)
        XCTAssertEqual(cards.count, 2, "leere Fragen und normaler Text zählen nicht")
        XCTAssertEqual(cards.first?.question, "Was ist ein Eigenwert?")
        XCTAssertEqual(cards.last?.answer, "Über die Nullstellen des charakteristischen Polynoms.")
    }

    func testCsvQuotesQuotesSoAnkiReadsTwoColumns() {
        let cards = [Flashcard(question: "Was heißt \"diagonalisierbar\"?", answer: "A = S·D·S⁻¹, D diagonal")]
        XCTAssertEqual(Flashcards.csv(cards), "\"Was heißt \"\"diagonalisierbar\"\"?\",\"A = S·D·S⁻¹, D diagonal\"\n")
    }

    /// Zweimal erzeugen darf die Karten ersetzen, nicht verdoppeln – und den Rest der Notiz stehen lassen.
    func testSectionIsReplacedAndNothingElseIsLost() {
        let note = """
        Kurzfassung der Vorlesung.

        ## Aufgaben

        - [ ] Übungsblatt 4

        ## Karteikarten

        - Alt :: Alte Antwort

        """
        let without = NoteMarkdown.removingSection(named: "Karteikarten", from: note)
        XCTAssertTrue(without.contains("Übungsblatt 4"))
        XCTAssertFalse(without.contains("Alt :: Alte Antwort"))
        let updated = without + "\n" + Flashcards.markdownSection([Flashcard(question: "Neu", answer: "Neue Antwort")],
                                                                  heading: "Karteikarten")
        XCTAssertEqual(Flashcards.parse(updated).count, 1)
        XCTAssertEqual(NoteMarkdown.openTaskCount(updated), 1)
    }

    func testOpenTasksAreTheTextsWithoutTheBox() {
        let note = "- [ ] Übungsblatt 4 rechnen\n- [x] Kapitel gelesen\n  - [ ] Termin notieren\n- kein Kästchen"
        XCTAssertEqual(NoteMarkdown.openTasks(note), ["Übungsblatt 4 rechnen", "Termin notieren"])
    }
}

/// Logseq will eine Aufzählung mit Eigenschaften – daran hängt, ob die Seite dort lesbar ankommt.
final class LogseqDocumentTests: XCTestCase {
    func testEverythingBecomesABlockAndTasksBecomeTodos() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let recording = Recording(title: "Analysis II", startedAt: start, endedAt: start.addingTimeInterval(3600))
        let summary = Summary(title: "Eigenwerte", markdown: """
        Kurzfassung in einem Satz.

        ## Aufgaben

        - [ ] Übungsblatt 4 rechnen
        - [x] Kapitel gelesen
        """, taskCount: 1, provider: "Test")
        let payload = ExportPayload(recording: recording, category: RecordingCategory(name: "Uni", emoji: "🎓", symbol: "book.fill",
                                                                colorHex: "#4F7CFF", instructions: ""),
                                    summary: summary, transcript: "", settings: DestinationSettings())
        let doc = LogseqDestination.document(payload)

        XCTAssertTrue(doc.hasPrefix("title:: Eigenwerte"), "Eigenschaften stehen zuerst")
        XCTAssertTrue(doc.contains("tags:: earnote, uni"))
        XCTAssertTrue(doc.contains("- TODO Übungsblatt 4 rechnen"))
        XCTAssertTrue(doc.contains("- DONE Kapitel gelesen"))
        XCTAssertTrue(doc.contains("- Kurzfassung in einem Satz."), "auch Fließtext wird ein Block")
        for line in doc.components(separatedBy: "\n").dropFirst(4) where !line.isEmpty {
            XCTAssertTrue(line.trimmingCharacters(in: CharacterSet.whitespaces).hasPrefix("-"), "jede Zeile ist ein Block: \(line)")
        }
    }
}

/// Der Schlüsselbund darf nicht bei jedem Neuzeichnen gefragt werden – sonst fragt macOS
/// den Nutzer immer wieder nach dem Passwort des Schlüsselbunds.
final class KeychainCacheTests: XCTestCase {
    private let key = "test.token"

    override func setUp() {
        super.setUp()
        Keychain.set(nil, for: key)
        Keychain.forgetCachedValues()
    }

    override func tearDown() {
        Keychain.set(nil, for: key)
        super.tearDown()
    }

    func testValueSurvivesAndPresenceIsKnownWithoutReading() {
        XCTAssertFalse(Keychain.hasValue(for: key))
        Keychain.set("  geheim  ", for: key)
        XCTAssertEqual(Keychain.get(key), "geheim", "Leerzeichen am Rand gehören nicht zum Schlüssel")
        XCTAssertTrue(Keychain.hasValue(for: key))

        // Nach dem Leeren des Zwischenspeichers weiß der Vermerk weiterhin Bescheid
        Keychain.forgetCachedValues()
        XCTAssertTrue(Keychain.hasValue(for: key))

        Keychain.set("", for: key)
        XCTAssertNil(Keychain.get(key))
        XCTAssertFalse(Keychain.hasValue(for: key), "ein leerer Schlüssel zählt als keiner")
    }
}
