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

/// Die Übersicht über mehrere Aufnahmen steht und fällt mit dem Material, das ins Modell geht.
final class PeriodSummaryTests: XCTestCase {
    private func sources(_ count: Int, size: Int = 100) -> [PeriodSummary.Source] {
        (0..<count).map { i in
            PeriodSummary.Source(title: "Vorlesung \(i + 1)",
                                 date: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400 * 7),
                                 markdown: String(repeating: "x", count: size))
        }
    }

    func testMaterialKeepsChronologyAndStaysWithinTheLimit() {
        let material = PeriodSummary.material(sources(3), limit: 10_000)
        let first = material.range(of: "Vorlesung 1")!
        let last = material.range(of: "Vorlesung 3")!
        XCTAssertTrue(first.lowerBound < last.lowerBound, "die früheste Mitschrift steht oben")
        XCTAssertLessThanOrEqual(material.count, 10_000)
    }

    func testTooMuchMaterialIsCutAtWholeNotes() {
        let all = sources(10, size: 1_000)
        let limit = 3_000
        let material = PeriodSummary.material(all, limit: limit)
        XCTAssertLessThanOrEqual(material.count, limit)
        XCTAssertTrue(material.contains("Vorlesung 1"))
        XCTAssertFalse(material.contains("Vorlesung 9"), "was nicht mehr passt, fällt ganz weg statt halb")
        XCTAssertEqual(PeriodSummary.fittingCount(all, limit: limit), 2)
    }

    func testSingleNoteStillProducesMaterialEvenIfItIsLongerThanTheLimit() {
        let material = PeriodSummary.material(sources(1, size: 5_000), limit: 1_000)
        XCTAssertFalse(material.isEmpty, "eine einzelne lange Notiz darf nicht zu leerem Material führen")
        XCTAssertLessThanOrEqual(material.count, 1_000)
    }

    func testSystemPromptCarriesSubjectAndExtraInstruction() {
        let system = PeriodSummary.system(language: "Deutsch", subject: "Analysis II", simple: true,
                                          extra: "Nur die Rechenwege")
        XCTAssertTrue(system.contains("Analysis II"))
        XCTAssertTrue(system.contains("Nur die Rechenwege"))
        XCTAssertTrue(system.contains("Prüfungshinweise"))
    }
}

/// Formeln dürfen beim Anzeigen nicht verschwinden: „A*v“ wurde vorher zu „Av“.
final class MathProtectionTests: XCTestCase {
    private func rendered(_ text: String) -> String {
        let source = NoteMarkdown.protectingMath(text)
        let parsed = (try? AttributedString(markdown: source,
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return String(parsed.characters)
    }

    func testMultiplicationSurvives() {
        XCTAssertEqual(rendered("A*v = λ*v für v_1 und v_2"), "A*v = λ*v für v_1 und v_2")
        XCTAssertEqual(rendered("2*3*4 = 24"), "2*3*4 = 24")
    }

    func testBoldStillWorks() {
        XCTAssertEqual(rendered("Das ist **wichtig**"), "Das ist wichtig")
        XCTAssertEqual(rendered("**Satz von Cayley-Hamilton**: p(A) = 0"), "Satz von Cayley-Hamilton: p(A) = 0")
    }

    func testCodeSpansAreLeftAlone() {
        XCTAssertEqual(rendered("Die Formel `a*b + c*d` gilt"), "Die Formel a*b + c*d gilt")
    }

    func testTextWithoutStarsIsUntouched() {
        XCTAssertEqual(NoteMarkdown.protectingMath("Ganz normaler Text"), "Ganz normaler Text")
    }
}

/// Das Kurzprotokoll ist das, was man nach einem Meeting weiterschickt: Ergebnis und Aufgaben.
final class ShortMinutesTests: XCTestCase {
    private let note = """
    Das Team hat den Zeitplan für die Einführung festgelegt.

    ## Zeitplan

    - Start im Oktober
    - Schulung im November

    ## Entscheidungen

    - Wir bleiben bei Anbieter B
    - Kein eigener Server

    ## Aufgaben

    - [ ] Angebot bis Freitag einholen
    - [x] Termin mit dem Betriebsrat

    ## Offene Fragen

    - Wer übernimmt die Schulung?
    """

    func testKeepsSummaryResultsAndTasksAndDropsTheRest() {
        let minutes = NoteMarkdown.shortMinutes(title: "Einführung neues System", markdown: note)
        XCTAssertTrue(minutes.hasPrefix("# Einführung neues System"))
        XCTAssertTrue(minutes.contains("Das Team hat den Zeitplan"))
        XCTAssertTrue(minutes.contains("Wir bleiben bei Anbieter B"))
        XCTAssertTrue(minutes.contains("- [ ] Angebot bis Freitag einholen"))
        XCTAssertTrue(minutes.contains("- [x] Termin mit dem Betriebsrat"), "auch Erledigtes gehört ins Protokoll")
        XCTAssertFalse(minutes.contains("Schulung im November"), "Themenblöcke bleiben draußen")
        XCTAssertFalse(minutes.contains("Wer übernimmt die Schulung?"), "offene Fragen bleiben draußen")
    }

    func testWorksWithEnglishHeadingsAndWithoutResults() {
        let english = "We agreed on the timeline.\n\n## Decisions\n\n- Vendor B\n\n## Tasks\n\n- [ ] Ask for a quote"
        XCTAssertTrue(NoteMarkdown.shortMinutes(title: "Kickoff", markdown: english).contains("Vendor B"))

        let plain = "Nur eine Kurzfassung ohne Abschnitte."
        let minutes = NoteMarkdown.shortMinutes(title: "Kurz", markdown: plain)
        XCTAssertTrue(minutes.contains("Nur eine Kurzfassung"))
        XCTAssertFalse(minutes.contains("##"), "ohne Ergebnisse und Aufgaben keine leeren Überschriften")
    }
}
