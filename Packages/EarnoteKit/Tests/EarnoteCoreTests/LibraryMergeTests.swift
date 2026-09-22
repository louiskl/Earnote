import SwiftData
import XCTest
@testable import EarnoteCore

/// Doppelte nach dem iCloud-Abgleich: Zwei Macs legen dieselben Bereiche an, danach stehen sie doppelt da.
final class LibraryMergeTests: XCTestCase {
    private var container: ModelContainer!
    private var library: SwiftDataLibraryRepository!

    override func setUpWithError() throws {
        container = try LibraryContainer.makeInMemory()
        library = SwiftDataLibraryRepository(modelContainer: container)
        Log.url = FileManager.default.temporaryDirectory.appendingPathComponent("EarnoteCoreTests.log")
    }

    override func tearDown() {
        library = nil
        container = nil
    }

    /// Legt Bereiche direkt im Speicher an – so, wie sie der Abgleich von einem anderen Gerät bringt
    /// (auch mit einer ID, die es schon gibt; das Repository selbst ließe das nicht zu).
    @discardableResult
    private func addCategory(id: UUID = UUID(), name: String, created: TimeInterval, instructions: String = "") throws -> UUID {
        let context = ModelContext(container)
        let model = LibraryCategory(id: id)
        model.name = name
        model.instructions = instructions
        model.createdAt = Date(timeIntervalSince1970: created)
        context.insert(model)
        try context.save()
        return id
    }

    func testSameNameFromTwoMacsBecomesOne() async throws {
        let first = try addCategory(name: "Vorlesung", created: 100, instructions: "Zum Lernen")
        let second = try addCategory(name: " vorlesung ", created: 200)
        let recording = Recording(title: "Analysis", categoryID: second, startedAt: Date(timeIntervalSince1970: 300))
        try await library.insertRecording(recording)
        try await library.insertGlossaryTerm(GlossaryTerm(term: "Eigenwert", variants: ["Eigen Wert"], categoryID: first))
        try await library.insertGlossaryTerm(GlossaryTerm(term: "eigenwert", variants: ["eigen wert", "Eigenwerth"],
                                                          note: "Lineare Algebra", categoryID: second))

        let report = try await library.mergeDuplicates()

        XCTAssertEqual(report.categoryReplacements, [second: first])
        XCTAssertEqual(report.removedGlossaryTerms, 1)
        let categories = try await library.categories()
        XCTAssertEqual(categories.map(\.id), [first])
        XCTAssertEqual(categories.first?.instructions, "Zum Lernen", "Der ältere Bereich bleibt mit seinen Einstellungen")
        let moved = try await library.recording(recording.id)
        XCTAssertEqual(moved?.categoryID, first, "Die Aufnahme wandert mit")
        let terms = try await library.glossaryTerms()
        XCTAssertEqual(terms.count, 1)
        XCTAssertEqual(terms.first?.categoryID, first)
        XCTAssertEqual(terms.first?.variants.count, 2, "„Eigen Wert“ und „eigen wert“ sind dieselbe Schreibweise")
        XCTAssertTrue(terms.first?.variants.contains("Eigenwerth") == true)
        XCTAssertEqual(terms.first?.note, "Lineare Algebra")
    }

    /// Standardbereich mit fester ID, auf einem Mac schon umbenannt: bleibt einer, der ältere
    func testSameIDIsMergedEvenWhenRenamed() async throws {
        let id = RecordingCategory.defaults[0].id
        try addCategory(id: id, name: "Team", created: 100)
        try addCategory(id: id, name: "Meeting", created: 200)
        let report = try await library.mergeDuplicates()
        XCTAssertTrue(report.categoryReplacements.isEmpty, "Gleiche ID – für die App ändert sich nichts")
        let names = try await library.categories().map(\.name)
        XCTAssertEqual(names, ["Team"])
    }

    func testDifferentCategoriesStay() async throws {
        try addCategory(name: "Vorlesung", created: 100)
        try addCategory(name: "Vorlesung Mathe", created: 200)
        try addCategory(name: "", created: 300)
        try addCategory(name: "", created: 400)
        let report = try await library.mergeDuplicates()
        XCTAssertTrue(report.isEmpty)
        let count = try await library.categories().count
        XCTAssertEqual(count, 4)
    }

    func testSecondRunChangesNothing() async throws {
        try addCategory(name: "Notiz", created: 100)
        try addCategory(name: "Notiz", created: 200)
        _ = try await library.mergeDuplicates()
        let again = try await library.mergeDuplicates()
        XCTAssertTrue(again.isEmpty)
    }

    /// Beide Macs müssen denselben Bereich behalten, egal in welcher Reihenfolge sie ihn sehen
    func testSurvivorDoesNotDependOnOrder() {
        struct Item { let id = UUID(); let created = Date(timeIntervalSince1970: 100) }
        let items = (0..<4).map { _ in Item() }
        let a = LibraryMerge.survivor(items, createdAt: \.created, id: \.id)?.id
        let b = LibraryMerge.survivor(items.reversed(), createdAt: \.created, id: \.id)?.id
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, items.map(\.id).min { $0.uuidString < $1.uuidString })
    }

    func testDefaultCategoriesHaveStableIDs() {
        let ids = RecordingCategory.defaults.map(\.id)
        XCTAssertEqual(Set(ids).count, RecordingCategory.defaults.count)
        XCTAssertEqual(ids.first, RecordingCategory.defaultID(1))
        XCTAssertEqual(ids, RecordingCategory.defaults.map(\.id), "Bei jedem Zugriff dieselben")
    }
}
