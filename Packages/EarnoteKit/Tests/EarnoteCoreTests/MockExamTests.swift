import XCTest
@testable import EarnoteCore

final class MockExamTests: XCTestCase {
    /// Liefert feste Antworten und merkt sich die Anfragen – keine echte KI
    private final class FakeClient: LLMClient, @unchecked Sendable {
        var replies: [String]
        var prompts: [String] = []
        init(_ replies: [String]) { self.replies = replies }
        func complete(system: String, prompt: String) async throws -> String {
            prompts.append(prompt)
            return replies.isEmpty ? "" : replies.removeFirst()
        }
    }

    private func source(_ title: String, daysAgo: Double, _ markdown: String) -> MockExam.Source {
        MockExam.Source(recordingID: UUID(), title: title, date: Date().addingTimeInterval(-daysAgo * 86_400), markdown: markdown)
    }

    func testMaterialPutsNewestFirstAndExamItemsUpFront() {
        let old = source("Determinanten", daysAgo: 7, "Text alt")
        let new = source("Eigenwerte", daysAgo: 1, "Text neu\n\n## Wichtig für die Klausur\n- Charakteristisches Polynom")
        let (text, used) = MockExam.material([old, new], limit: 10_000)
        XCTAssertEqual(used.map(\.title), ["Eigenwerte", "Determinanten"])
        XCTAssertTrue(text.hasPrefix("## [V1] Eigenwerte"))
        XCTAssertTrue(text.contains("Prüfungsrelevant:\n- Charakteristisches Polynom"))
        XCTAssertTrue(text.contains("## [V2] Determinanten"))
    }

    func testMaterialKeepsWithinBudgetButNeverEmpty() {
        let big = source("Lang", daysAgo: 1, String(repeating: "x", count: 5_000))
        let other = source("Älter", daysAgo: 5, "kurz")
        let (text, used) = MockExam.material([big, other], limit: 1_000)
        XCTAssertEqual(used.map(\.title), ["Lang"], "Die neueste kommt gekürzt mit, die nächste passt nicht mehr")
        XCTAssertLessThanOrEqual(text.count, 1_000)
    }

    func testParseQuestionsReadsSourceKindAndText() {
        let reply = """
        Hier sind die Fragen:
        V1 | Wissen | Was ist ein Eigenwert einer Matrix?
        2. V2 | Rechnen | Berechne die Determinante der Matrix [[1,2],[3,4]].
        V9 | Verständnis | Warum hat eine Dreiecksmatrix ihre Diagonale als Eigenwerte?
        V1 | Wissen | Was ist ein Eigenwert einer Matrix?
        """
        let questions = MockExam.parseQuestions(reply, sourceCount: 2)
        XCTAssertEqual(questions.count, 3, "Einleitung und Doppelte fallen weg")
        XCTAssertEqual(questions[0].source, 0)
        XCTAssertEqual(questions[0].kind, "Wissen")
        XCTAssertEqual(questions[1].source, 1)
        XCTAssertTrue(questions[1].text.hasPrefix("Berechne"))
        XCTAssertNil(questions[2].source, "V9 gibt es nicht")
    }

    func testParseGradeTolerantOfFormat() {
        XCTAssertEqual(MockExam.parseGrade("Punkte: 1\nRückmeldung: Die Idee stimmt, der Rechenweg fehlt."),
                       MockExam.Grade(points: 1, feedback: "Die Idee stimmt, der Rechenweg fehlt."))
        XCTAssertEqual(MockExam.parseGrade("**Points: 2** Feedback: Correct.")?.points, 2)
        XCTAssertNil(MockExam.parseGrade("Gut gemacht!"))
    }

    func testGradeSkipsEmptyAnswerAndSendsOnlyItsSource() async throws {
        let client = FakeClient(["Punkte: 2\nRückmeldung: Richtig."])
        let q = MockExam.Question(text: "Was ist ein Eigenwert?", kind: "Wissen", source: 0)
        let s = source("Eigenwerte", daysAgo: 1, "Ein Eigenwert ist der Faktor …")
        let empty = try await MockExam.grade(client: client, question: q, answer: "  ", source: s, language: "Deutsch", limit: 100)
        XCTAssertEqual(empty.points, 0)
        XCTAssertTrue(client.prompts.isEmpty, "Leere Antwort kostet keine Anfrage")
        let graded = try await MockExam.grade(client: client, question: q, answer: "Der Streckfaktor", source: s,
                                              language: "Deutsch", limit: 100)
        XCTAssertEqual(graded.points, 2)
        XCTAssertTrue(client.prompts[0].contains("Ein Eigenwert ist der Faktor"))
        XCTAssertTrue(client.prompts[0].contains("Der Streckfaktor"))
    }

    func testRepeatingTheQuestionGetsNoPoints() async throws {
        let client = FakeClient(["Punkte: 2\nRückmeldung: Richtig."])
        let q = MockExam.Question(text: "Was ist der Eigenraum zu einem Eigenwert λ?", kind: "Wissen", source: nil)
        let graded = try await MockExam.grade(client: client, question: q, answer: "Was ist der Eigenraum zu einem Eigenwert λ?",
                                              source: nil, language: "Deutsch", limit: 100)
        XCTAssertEqual(graded.points, 0)
        XCTAssertTrue(client.prompts.isEmpty, "Keine Anfrage an die KI")
        XCTAssertFalse(MockExam.repeatsQuestion("Der Kern von A minus Lambda E", q.text))
    }

    func testQuestionsEndToEndAndMarkdown() async throws {
        let s = source("Eigenwerte", daysAgo: 1, "Notiz")
        let client = FakeClient(["V1 | Wissen | Was ist ein Eigenwert einer Matrix?\nV1 | Rechnen | Berechne die Eigenwerte von diag(2,3)."])
        let (questions, used) = try await MockExam.questions(client: client, sources: [s], language: "Deutsch", limit: 5_000)
        XCTAssertEqual(questions.count, 2)
        let md = MockExam.markdown(title: "Probeklausur – Analysis II", date: Date(), questions: questions,
                                   answers: ["Streckfaktor", ""],
                                   grades: [.init(points: 2, feedback: "Richtig."), .init(points: 0, feedback: "Keine Antwort.")],
                                   sources: used)
        XCTAssertTrue(md.contains("Ergebnis: 2 von 4 Punkten"))
        XCTAssertTrue(md.contains("## 1. Was ist ein Eigenwert einer Matrix?"))
        XCTAssertTrue(md.contains("Steht in: Eigenwerte"))
        XCTAssertTrue(md.contains("**Deine Antwort:** –"))
    }
}
