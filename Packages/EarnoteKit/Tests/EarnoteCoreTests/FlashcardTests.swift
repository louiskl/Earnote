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
