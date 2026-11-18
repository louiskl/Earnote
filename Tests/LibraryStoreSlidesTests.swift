import CoreText
import EarnoteCore
import SwiftData
import XCTest
@testable import Earnote

/// Folien anhängen wie über „Notiz › Folien“: kopieren, Text je Seite lesen, zählen, entfernen.
@MainActor
final class LibraryStoreSlidesTests: XCTestCase {
    private func makeStore() async throws -> LibraryStore {
        // Eigener Ordner statt des echten Datenordners
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("earnote-slides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let audio = FileAudioStore(storage: Storage(root: root))
        let container = try LibraryContainer.makeInMemory()
        let repository = SwiftDataLibraryRepository(modelContainer: container)
        let pipeline = ProcessingPipeline(library: repository, audio: audio,
                                          transcribers: PlatformTranscribers(), llm: LLMFactory(platform: PlatformLLMClients()),
                                          destinations: AppDestinations(), notify: { _, _ in })
        let suite = "app.earnote.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(library: repository, audio: audio,
                                 settingsRepository: UserDefaultsSettingsRepository(defaults: defaults),
                                 queue: ProcessingQueue(pipeline: pipeline))
        await store.load()
        return store
    }

    /// PDF mit echtem Text je Seite, wie es PowerPoint oder Keynote exportieren
    private func makePDF(_ pages: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for text in pages {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 24, nil)]))
            context.textPosition = CGPoint(x: 20, y: 150)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAttachReadsEveryPageAndRemoveClears() async throws {
        let store = try await makeStore()
        let id = UUID()
        XCTAssertEqual(store.slideCount(id), 0)
        XCTAssertNil(store.slidesURL(id))

        let count = try await store.attachSlides(id, from: makePDF(["Eigenwerte", "Determinante", "Basiswechsel"]))
        XCTAssertEqual(count, 3)
        XCTAssertEqual(store.slideCount(id), 3)
        let url = try XCTUnwrap(store.slidesURL(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let pages = Slides.pages(in: url.deletingLastPathComponent())
        XCTAssertTrue(pages[1].contains("Determinante"), "Text der zweiten Seite: \(pages)")

        // Neue Folien ersetzen die alten
        let replaced = try await store.attachSlides(id, from: makePDF(["Nur eine"]))
        XCTAssertEqual(replaced, 1)
        XCTAssertEqual(store.slideCount(id), 1)

        store.removeSlides(id)
        XCTAssertEqual(store.slideCount(id), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testNotAPDFIsRefusedAndKeepsOldSlides() async throws {
        let store = try await makeStore()
        let id = UUID()
        try await store.attachSlides(id, from: makePDF(["Eigenwerte", "Determinante"]))

        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data("kein PDF".utf8).write(to: broken)
        addTeardownBlock { try? FileManager.default.removeItem(at: broken) }
        do {
            try await store.attachSlides(id, from: broken)
            XCTFail("Kaputte Datei angenommen")
        } catch {}
        XCTAssertEqual(store.slideCount(id), 2, "Die alten Folien bleiben")
    }
}
