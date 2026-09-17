import SwiftData
import XCTest
@testable import EarnoteCore

final class LibrarySchemaTests: XCTestCase {
    /// Regeln, die CloudKit später verlangt – so weit sie über die Schema-API prüfbar sind.
    func testSchemaIsCloudKitCompatible() {
        let schema = Schema(versionedSchema: EarnoteSchemaV1.self)
        XCTAssertEqual(Set(schema.entities.map(\.name)),
                       ["LibraryRecording", "LibraryTranscript", "LibraryNote", "LibraryCategory", "LibraryGlossaryTerm", "LibraryExport"])
        for entity in schema.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name): keine #Unique-Regeln")
            for attribute in entity.attributes {
                XCTAssertFalse(attribute.isUnique, "\(entity.name).\(attribute.name) darf nicht eindeutig sein")
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil,
                              "\(entity.name).\(attribute.name) braucht einen Standardwert oder muss optional sein")
            }
            for relationship in entity.relationships {
                XCTAssertTrue(relationship.isOptional, "\(entity.name).\(relationship.name) muss optional sein")
                XCTAssertNotNil(relationship.inverseName, "\(entity.name).\(relationship.name) braucht eine Inverse")
                XCTAssertNotEqual(relationship.deleteRule, .deny, "\(entity.name).\(relationship.name): keine deny-Regel")
            }
        }
        let recording = schema.entities.first { $0.name == "LibraryRecording" }!
        let rules = Dictionary(uniqueKeysWithValues: recording.relationships.map { ($0.name, $0.deleteRule) })
        XCTAssertEqual(rules["transcript"], .cascade)
        XCTAssertEqual(rules["note"], .cascade)
        XCTAssertEqual(rules["exports"], .cascade)
        XCTAssertEqual(rules["category"], .nullify)
        let category = schema.entities.first { $0.name == "LibraryCategory" }!
        let categoryRules = Dictionary(uniqueKeysWithValues: category.relationships.map { ($0.name, $0.deleteRule) })
        XCTAssertEqual(categoryRules["recordings"], .nullify)
        XCTAssertEqual(categoryRules["glossary"], .cascade)
    }
}

final class LibraryRepositoryTests: XCTestCase {
    private var library: SwiftDataLibraryRepository!

    override func setUpWithError() throws {
        library = SwiftDataLibraryRepository(modelContainer: try LibraryContainer.makeInMemory())
        Log.url = FileManager.default.temporaryDirectory.appendingPathComponent("EarnoteCoreTests.log")
    }

    override func tearDown() { library = nil }

    private func fullRecording(category: UUID? = nil) -> Recording {
        var r = Recording(title: "Meeting – 3. Sept., 10:00", categoryID: category, sourceApp: "Zoom",
                          startedAt: Date(timeIntervalSince1970: 1_000_000), endedAt: Date(timeIntervalSince1970: 1_003_600),
                          status: .failed)
        r.hasSystemAudio = true
        r.errorMessage = "Export teilweise fehlgeschlagen"
        r.language = "en"
        r.pausedDuration = 42
        r.exports = [
            ExportResult(destinationID: "markdown", destinationName: "Markdown", success: true, message: "Exportiert",
                         url: "file:///a.md", date: Date(timeIntervalSince1970: 1_003_700)),
            ExportResult(destinationID: "notion", destinationName: "Notion", success: false, message: "Nicht verbunden",
                         date: Date(timeIntervalSince1970: 1_003_701), skipped: true),
            ExportResult(destinationID: "obsidian", destinationName: "Obsidian", success: false, message: "Kaputt",
                         date: Date(timeIntervalSince1970: 1_003_702)),
        ]
        return r
    }

    // MARK: CRUD

    func testRecordingRoundTrip() async throws {
        let category = RecordingCategory(name: "Meeting", emoji: "💼", symbol: "person.3.fill", colorHex: "#4F7CFF", instructions: "")
        try await library.insertCategory(category, sortIndex: nil)
        var original = fullRecording(category: category.id)
        original.progress = 0.7
        try await library.insertRecording(original)

        let loaded = try await library.recording(original.id)
        var expected = original
        expected.progress = 0          // Fortschritt wird nicht gespeichert
        expected.isTitleCustom = false // automatischer Name
        XCTAssertEqual(loaded, expected)
        XCTAssertEqual(loaded?.hasAutoTitle, true)
        let all = try await library.recordings()
        XCTAssertEqual(all.map(\.id), [original.id])

        try await library.updateRecording(original.id) {
            $0.title = "Eigener Name"
            $0.isTitleCustom = true
            $0.status = .done
            $0.categoryID = nil
            $0.exports.removeLast()
            $0.pausedDuration = nil
        }
        let updated = try await library.recording(original.id)
        XCTAssertEqual(updated?.title, "Eigener Name")
        XCTAssertEqual(updated?.hasAutoTitle, false)
        XCTAssertEqual(updated?.status, .done)
        XCTAssertNil(updated?.categoryID)
        XCTAssertNil(updated?.pausedDuration)
        XCTAssertEqual(updated?.exports.map(\.destinationID), ["markdown", "notion"])

        try await library.deleteRecording(original.id)
        let afterDelete = try await library.recordings()
        XCTAssertTrue(afterDelete.isEmpty)
        let categories = try await library.categories()
        XCTAssertEqual(categories.count, 1, "Bereich bleibt beim Löschen einer Aufnahme")
    }

    func testRecordingsAreSortedNewestFirstAndInsertIsIdempotent() async throws {
        let old = Recording(title: "alt", startedAt: Date(timeIntervalSince1970: 10))
        let new = Recording(title: "neu", startedAt: Date(timeIntervalSince1970: 20))
        try await library.insertRecording(old)
        try await library.insertRecording(new)
        try await library.insertRecording(old)
        let ids = try await library.recordings().map(\.id)
        XCTAssertEqual(ids, [new.id, old.id])
        let set = try await library.recordingIDs()
        XCTAssertEqual(set, [old.id, new.id])
    }

    func testTranscriptNoteAndExportsCRUD() async throws {
        let rec = Recording(title: "Test")
        try await library.insertRecording(rec)
        let transcript = Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: "Hallo Welt", speaker: "Ich")], engine: "E")
        try await library.saveTranscript(transcript, for: rec.id)
        let loadedTranscript = try await library.transcript(for: rec.id)
        XCTAssertEqual(loadedTranscript?.segments, transcript.segments)
        XCTAssertEqual(loadedTranscript?.engine, "E")
        try await library.deleteTranscript(for: rec.id)
        let deletedTranscript = try await library.transcript(for: rec.id)
        XCTAssertNil(deletedTranscript)

        let note = Summary(title: "Titel", markdown: "Erster Satz.\n- [ ] Aufgabe", taskCount: 1, provider: "P")
        try await library.saveNote(note, for: rec.id)
        let loadedNote = try await library.note(for: rec.id)
        XCTAssertEqual(loadedNote?.title, "Titel")
        XCTAssertEqual(loadedNote?.markdown, note.markdown)
        let withNote = try await library.recording(rec.id)
        XCTAssertEqual(withNote?.summaryTitle, "Titel")
        XCTAssertEqual(withNote?.summaryPreview, "Erster Satz.")
        XCTAssertEqual(withNote?.taskCount, 1)
        try await library.deleteNote(for: rec.id)
        let deletedNote = try await library.note(for: rec.id)
        XCTAssertNil(deletedNote)

        let exports = [ExportResult(destinationID: "markdown", destinationName: "M", success: true, message: "ok")]
        try await library.setExports(exports, for: rec.id)
        let withExports = try await library.recording(rec.id)
        XCTAssertEqual(withExports?.exports, exports)
        try await library.setExports([], for: rec.id)
        let withoutExports = try await library.recording(rec.id)
        XCTAssertEqual(withoutExports?.exports, [])

        // Deleted recordings get no orphaned children
        let ghost = UUID()
        try await library.saveTranscript(transcript, for: ghost)
        try await library.saveNote(note, for: ghost)
        let ghostTranscript = try await library.transcript(for: ghost)
        XCTAssertNil(ghostTranscript)
    }

    func testCategoriesAndGlossaryCRUD() async throws {
        let a = RecordingCategory(name: "A", emoji: "🅰️", symbol: "star.fill", colorHex: "#111111", instructions: "a",
                                  destinationIDs: ["notion", "markdown"])
        let b = RecordingCategory(name: "B", symbol: "star.fill", colorHex: "#222222", instructions: "b")
        let c = RecordingCategory(name: "C", symbol: "star.fill", colorHex: "#333333", instructions: "c")
        for category in [a, b, c] { try await library.insertCategory(category, sortIndex: nil) }
        let inserted = try await library.categories()
        XCTAssertEqual(inserted, [a, b, c])

        var changed = b
        changed.name = "B2"
        changed.destinationIDs = ["markdown"]
        try await library.updateCategory(changed)
        try await library.reorderCategories([c.id, changed.id, a.id])
        let reordered = try await library.categories()
        XCTAssertEqual(reordered, [c, changed, a])

        let global = GlossaryTerm(term: "WhisperKit", variants: ["Whisper Kit", "Wisperkit"])
        var scoped = GlossaryTerm(term: "Eigenwert", variants: ["Eigen Wert"], note: "Lineare Algebra", categoryID: a.id)
        try await library.insertGlossaryTerm(global)
        try await library.insertGlossaryTerm(scoped)
        let terms = try await library.glossaryTerms()
        XCTAssertEqual(terms, [scoped, global])
        scoped.variants.append("Eigenwerd")
        scoped.categoryID = nil
        try await library.updateGlossaryTerm(scoped)
        try await library.deleteGlossaryTerm(global.id)
        let remaining = try await library.glossaryTerms()
        XCTAssertEqual(remaining, [scoped])

        try await library.deleteCategory(c.id)
        let afterDelete = try await library.categories()
        XCTAssertEqual(afterDelete.map(\.id), [changed.id, a.id])
    }

    // MARK: Löschregeln

    func testDeletingRecordingRemovesTranscriptNoteAndExports() async throws {
        let rec = fullRecording()
        try await library.insertRecording(rec)
        try await library.saveTranscript(Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: "x")], engine: "E"), for: rec.id)
        try await library.saveNote(Summary(title: "T", markdown: "M", taskCount: 0, provider: "P"), for: rec.id)
        try await library.deleteRecording(rec.id)

        let context = ModelContext(library.modelContainer)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryRecording>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryTranscript>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryNote>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryExport>()), 0)
    }

    func testDeletingCategoryKeepsRecordingsAndRemovesItsGlossary() async throws {
        let category = RecordingCategory(name: "Bio", symbol: "leaf.fill", colorHex: "#10B981", instructions: "")
        let other = RecordingCategory(name: "Chemie", symbol: "star.fill", colorHex: "#10B981", instructions: "")
        try await library.insertCategory(category, sortIndex: nil)
        try await library.insertCategory(other, sortIndex: nil)
        let recs = [Recording(title: "Eins", categoryID: category.id), Recording(title: "Zwei", categoryID: category.id),
                    Recording(title: "Drei", categoryID: other.id)]
        for r in recs { try await library.insertRecording(r) }
        try await library.insertGlossaryTerm(GlossaryTerm(term: "Mitochondrium", categoryID: category.id))
        try await library.insertGlossaryTerm(GlossaryTerm(term: "Enzym"))

        try await library.deleteCategory(category.id)

        let remaining = try await library.recordings()
        XCTAssertEqual(remaining.count, 3, "Aufnahmen werden nie mit dem Bereich gelöscht")
        XCTAssertEqual(remaining.filter { $0.categoryID == nil }.count, 2)
        XCTAssertEqual(remaining.first { $0.title == "Drei" }?.categoryID, other.id)
        let terms = try await library.glossaryTerms()
        XCTAssertEqual(terms.map(\.term), ["Enzym"], "Wörterbuch des Bereichs ist weg, globale Einträge bleiben")
    }

    // MARK: Notiz

    func testNoteKeepsGeneratedOriginalWhenEdited() async throws {
        let rec = Recording(title: "Test")
        try await library.insertRecording(rec)
        try await library.saveNote(Summary(title: "KI-Titel", markdown: "- [ ] A\n- [ ] B", taskCount: 2, provider: "Lokale KI"), for: rec.id)

        let context = ModelContext(library.modelContainer)
        var stored = try XCTUnwrap(context.fetch(FetchDescriptor<LibraryNote>()).first)
        XCTAssertEqual(stored.generatedTitle, "KI-Titel")
        XCTAssertEqual(stored.generatedMarkdown, "- [ ] A\n- [ ] B")
        XCTAssertNil(stored.editedAt)

        try await library.updateNoteText("- [x] A\n- [ ] B", taskCount: 1, for: rec.id)
        stored = try XCTUnwrap(ModelContext(library.modelContainer).fetch(FetchDescriptor<LibraryNote>()).first)
        XCTAssertEqual(stored.markdown, "- [x] A\n- [ ] B")
        XCTAssertEqual(stored.taskCount, 1)
        XCTAssertNotNil(stored.editedAt)
        XCTAssertEqual(stored.generatedMarkdown, "- [ ] A\n- [ ] B", "KI-Original bleibt")
        let note = try await library.note(for: rec.id)
        XCTAssertEqual(note?.markdown, "- [x] A\n- [ ] B", "Gelesen wird die aktuelle Fassung")
    }

    // MARK: Transkript und Leistung

    private static func longTranscript(segments: Int) -> Transcript {
        Transcript(segments: (0..<segments).map { i in
            TranscriptSegment(start: Double(i) * 3.6, end: Double(i) * 3.6 + 3.4,
                              text: "Satz \(i): In der Vorlesung geht es heute um Eigenwerte und ihre Bedeutung.",
                              speaker: i % 7 == 0 ? "Andere" : "Ich")
        }, engine: "Whisper large-v3")
    }

    func testThreeHourTranscriptRoundTrip() async throws {
        let rec = Recording(title: "Vorlesung")
        try await library.insertRecording(rec)
        let transcript = Self.longTranscript(segments: 3_000)
        try await library.saveTranscript(transcript, for: rec.id)
        let loaded = try await library.transcript(for: rec.id)
        XCTAssertEqual(loaded?.segments, transcript.segments)

        let context = ModelContext(library.modelContainer)
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<LibraryTranscript>()).first)
        XCTAssertEqual(stored.wordCount, transcript.plainText.split(whereSeparator: \.isWhitespace).count)
        XCTAssertTrue(stored.plainText.hasPrefix("Satz 0: In der Vorlesung"))
    }

    func testLoadingThousandRecordingsSkipsTranscripts() async throws {
        let transcript = Self.longTranscript(segments: 200)
        var items: [LibraryImportItem] = []
        for i in 0..<1_000 {
            var r = Recording(title: "Aufnahme \(i)", startedAt: Date(timeIntervalSince1970: Double(i) * 60), status: .done)
            r.exports = [ExportResult(destinationID: "markdown", destinationName: "M", success: true, message: "ok")]
            items.append(LibraryImportItem(recording: r, transcript: transcript,
                                           note: Summary(title: "Notiz \(i)", markdown: "Inhalt \(i)", taskCount: 0, provider: "P")))
        }
        for start in stride(from: 0, to: items.count, by: 100) {
            _ = try await library.importItems(Array(items[start..<min(start + 100, items.count)]))
        }

        // Frischer Repository-Actor, damit nichts mehr im Speicher des Kontexts liegt
        let fresh = SwiftDataLibraryRepository(modelContainer: library.modelContainer)
        let clock = ContinuousClock()
        var list: [Recording] = []
        let listDuration = try await clock.measure { list = try await fresh.recordings() }
        XCTAssertEqual(list.count, 1_000)
        XCTAssertEqual(list.first?.summaryTitle, "Notiz 999")
        XCTAssertEqual(list.first?.exports.count, 1)

        let other = SwiftDataLibraryRepository(modelContainer: library.modelContainer)
        let transcriptDuration = try await clock.measure {
            for r in list.prefix(1_000) { _ = try await other.transcript(for: r.id) }
        }
        let listSeconds = Double(listDuration.components.seconds) + Double(listDuration.components.attoseconds) / 1e18
        let transcriptSeconds = Double(transcriptDuration.components.seconds) + Double(transcriptDuration.components.attoseconds) / 1e18
        print("LEISTUNG: Liste mit 1000 Aufnahmen \(String(format: "%.3f", listSeconds)) s; "
              + "alle 1000 Transkripte (je 200 Segmente) \(String(format: "%.3f", transcriptSeconds)) s")
        XCTAssertLessThan(listSeconds, 0.5)
        XCTAssertLessThan(listSeconds, transcriptSeconds, "Die Liste lädt keine Transkripte")
    }
}

final class FileLibraryImporterTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var library: SwiftDataLibraryRepository!

    private let meeting = UUID(uuidString: "C1C1C1C1-0000-4000-8000-000000000001")!
    private let lecture = UUID(uuidString: "C2C2C2C2-0000-4000-8000-000000000002")!
    private let math = UUID(uuidString: "C3C3C3C3-0000-4000-8000-000000000003")!
    private let withNote = UUID(uuidString: "A0000000-0000-4000-8000-00000000000A")!
    private let imported = UUID(uuidString: "B0000000-0000-4000-8000-00000000000B")!
    private let transcribing = UUID(uuidString: "C0000000-0000-4000-8000-00000000000C")!
    private let broken = "D0000000-0000-4000-8000-00000000000D"
    private let oldFormat = UUID(uuidString: "E0000000-0000-4000-8000-00000000000E")!
    private let repaired = UUID(uuidString: "F0000000-0000-4000-8000-00000000000F")!
    private let interrupted = UUID(uuidString: "A1000000-0000-4000-8000-0000000000A1")!

    override func setUpWithError() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/LegacyLibrary", withExtension: nil))
        root = FileManager.default.temporaryDirectory.appendingPathComponent("EarnoteImport-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixture, to: root)
        suite = "app.earnote.tests.import.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.set(try Data(contentsOf: root.appendingPathComponent("categories.json")), forKey: "categories")
        library = SwiftDataLibraryRepository(modelContainer: try LibraryContainer.makeInMemory())
        Log.url = root.appendingPathComponent("test.log")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func importer() -> FileLibraryImporter {
        let storage = Storage(root: root)
        return FileLibraryImporter(reader: LegacyFileLibraryReader(storage: storage), library: library,
                                   audio: FileAudioStore(storage: storage), defaults: defaults)
    }

    /// Prüfsummen aller Dateien, um zu zeigen, dass die Übernahme nichts verändert
    private func fileFingerprint() throws -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where !url.hasDirectoryPath && url.pathExtension != "log" {
            result[url.path.replacingOccurrences(of: root.path, with: "")] = try Data(contentsOf: url)
        }
        return result
    }

    func testImportsLegacyLibrary() async throws {
        let before = try fileFingerprint()
        let report = await importer().runIfNeeded()

        XCTAssertEqual(report.categories, 3)
        XCTAssertEqual(report.recordings, 6)
        XCTAssertEqual(report.transcripts, 2)
        XCTAssertEqual(report.notes, 2)
        XCTAssertEqual(report.orphanedCategories, 1)
        XCTAssertEqual(report.repairedCategories, 1)
        XCTAssertEqual(report.errors.count, 1, "Kaputte meta.json")
        XCTAssertTrue(report.errors[0].contains(broken))
        XCTAssertEqual(defaults.integer(forKey: FileLibraryImporter.versionKey), 0, "Mit Fehlern bleibt das Flag ungesetzt")
        XCTAssertEqual(try fileFingerprint(), before, "Alte Dateien bleiben unverändert")

        let categories = try await library.categories()
        XCTAssertEqual(categories.map(\.id), [meeting, lecture, math], "IDs und Reihenfolge bleiben")
        XCTAssertEqual(categories[2].destinationIDs, ["markdown", "notion"])
        XCTAssertNil(categories[2].emoji)

        let recordings = try await library.recordings()
        XCTAssertEqual(recordings.count, 6)
        func rec(_ id: UUID) throws -> Recording { try XCTUnwrap(recordings.first { $0.id == id }) }

        // Aufnahme mit Notiz und Transkript
        let a = try rec(withNote)
        XCTAssertEqual(a.categoryID, meeting)
        XCTAssertEqual(a.hasAutoTitle, true)
        XCTAssertEqual(a.displayTitle, "Budgetplanung")
        XCTAssertEqual(a.status, .done)
        XCTAssertEqual(a.pausedDuration, 12)
        XCTAssertEqual(a.sourceApp, "Zoom")
        XCTAssertTrue(a.hasSystemAudio)
        XCTAssertEqual(a.summaryPreview, "Budget besprochen.")
        XCTAssertEqual(a.taskCount, 1)
        XCTAssertEqual(a.exports.map(\.destinationID), ["markdown", "notion"])
        XCTAssertEqual(a.exports[1].skipped, true)
        XCTAssertEqual(a.exports[0].url, "file:///tmp/a.md")
        let aTranscript = try await library.transcript(for: withNote)
        XCTAssertEqual(aTranscript?.segments.count, 3)
        XCTAssertEqual(aTranscript?.segments[1].speaker, "Andere")
        let aNote = try await library.note(for: withNote)
        XCTAssertEqual(aNote?.markdown, "Budget besprochen.\n\n## Aufgaben\n- [ ] Anna: Angebot einholen")

        // Importierte Datei ohne Notiz, Fehlerstatus bleibt
        let b = try rec(imported)
        XCTAssertEqual(b.importedFileName, "import.m4a")
        XCTAssertEqual(b.origin, .importedFile)
        XCTAssertEqual(b.status, .failed)
        XCTAssertEqual(b.errorMessage, "Zusammenfassung fehlgeschlagen: Zeitüberschreitung")
        XCTAssertEqual(b.hasAutoTitle, false)
        XCTAssertEqual(b.progress, 0)
        let bNote = try await library.note(for: imported)
        XCTAssertNil(bNote)

        // Unterbrochen: wieder eingereiht; verwaiste Zuordnung gelöst
        let c = try rec(transcribing)
        XCTAssertEqual(c.status, .queued)
        XCTAssertNil(c.categoryID)
        let h = try rec(interrupted)
        XCTAssertEqual(h.status, .queued)
        XCTAssertNotNil(h.endedAt, "Abgebrochene Aufnahme bekommt ein Ende")

        // Älteres Format ohne optionale Felder: Vorschau aus der Notiz
        let e = try rec(oldFormat)
        XCTAssertEqual(e.language, "en")
        XCTAssertNil(e.pausedDuration)
        XCTAssertEqual(e.summaryPreview, "Erster richtiger Absatz.")
        XCTAssertEqual(e.summaryTitle, "Alter Titel")

        // Frühere Namens-Reparatur
        XCTAssertEqual(try rec(repaired).categoryID, lecture)
    }

    func testSecondRunCreatesNoDuplicatesAndFlagFollowsSuccess() async throws {
        _ = await importer().runIfNeeded()
        let second = await importer().runIfNeeded()
        XCTAssertEqual(second.recordings, 0)
        XCTAssertEqual(second.categories, 0)
        XCTAssertEqual(second.skipped, 6)
        XCTAssertEqual(second.errors.count, 1)
        let afterSecond = try await library.recordings()
        XCTAssertEqual(afterSecond.count, 6)
        let categories = try await library.categories()
        XCTAssertEqual(categories.count, 3)

        // Kaputte Datei repariert (hier: entfernt) → nächster Lauf fehlerfrei, Flag gesetzt, danach nichts mehr
        try FileManager.default.removeItem(at: root.appendingPathComponent("Recordings/\(broken)"))
        let third = await importer().runIfNeeded()
        XCTAssertTrue(third.errors.isEmpty)
        XCTAssertEqual(defaults.integer(forKey: FileLibraryImporter.versionKey), 1)
        let fourth = await importer().runIfNeeded()
        XCTAssertTrue(fourth.alreadyDone)
        let final = try await library.recordings()
        XCTAssertEqual(final.count, 6)
    }

    func testFreshInstallGetsDefaultCategories() async throws {
        defaults.removeObject(forKey: "categories")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Recordings"))
        let report = await importer().runIfNeeded()
        XCTAssertEqual(report.categories, RecordingCategory.defaults.count)
        XCTAssertEqual(report.recordings, 0)
        XCTAssertTrue(report.errors.isEmpty)
        let categories = try await library.categories()
        XCTAssertEqual(categories.map(\.name), RecordingCategory.defaults.map(\.name))
        XCTAssertEqual(defaults.integer(forKey: FileLibraryImporter.versionKey), 1)
    }
}
