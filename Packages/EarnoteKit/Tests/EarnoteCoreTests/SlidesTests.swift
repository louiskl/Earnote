import XCTest
@testable import EarnoteCore

final class SlidesTests: XCTestCase {
    func testSaveAndLoad() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(Slides.pages(in: folder), [])
        try Slides.save(pages: ["Eigenwerte", ""], in: folder)
        XCTAssertEqual(Slides.pages(in: folder), ["Eigenwerte", ""])
        Slides.remove(in: folder)
        XCTAssertEqual(Slides.pages(in: folder), [])
    }

    func testInstructionKeepsEveryPageNumberWithinBudget() {
        let pages = (1...20).map { "Seite \($0) " + String(repeating: "Wort ", count: 200) }
        let text = Slides.instruction(pages: pages, budget: 3_000)
        XCTAssertTrue(text.contains("Folie 1:"))
        XCTAssertTrue(text.contains("Folie 20:"), "Jede Folie bleibt mit Nummer drin")
        XCTAssertLessThan(text.count, 4_000)
    }

    func testInstructionSkipsEmptyPagesAndEmptyDecks() {
        XCTAssertEqual(Slides.instruction(pages: ["", "  "], budget: 1_000), "")
        let text = Slides.instruction(pages: ["", "Determinante\n\n det(A)"], budget: 1_000)
        XCTAssertTrue(text.contains("Folie 2: Determinante det(A)"), "Nummer der echten Seite, Leerraum zusammengefasst")
        XCTAssertFalse(text.contains("Folie 1:"))
    }

    func testLinkedOnlyForExistingPages() {
        let text = Slides.linked("Eigenwerte (Folie 3), Beweis auf Slide 99", pageCount: 10)
        XCTAssertEqual(text, "Eigenwerte ([Folie 3](earnote-slide:3)), Beweis auf Slide 99")
        XCTAssertEqual(Slides.linked("Folie 3", pageCount: 0), "Folie 3", "Ohne Folien kein Link")
        XCTAssertEqual(Slides.page(from: URL(string: "earnote-slide:3")!), 3)
        XCTAssertNil(Slides.page(from: URL(string: "https://earnote.app")!))
    }
}
