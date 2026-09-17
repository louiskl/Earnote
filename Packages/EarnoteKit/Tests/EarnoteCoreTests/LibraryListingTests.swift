import XCTest
@testable import EarnoteCore

final class LibraryListingTests: XCTestCase {
    private let bio = UUID(), chem = UUID()
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    /// Donnerstag, 17. September 2026, 15:00
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 15))! }

    private func item(_ title: String, daysAgo: Int, hour: Int = 10, category: UUID? = nil,
                      status: RecordingStatus = .done, tasks: Int = 0) -> Recording {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        var r = Recording(title: title, categoryID: category, startedAt: date, status: status)
        r.taskCount = tasks
        return r
    }

    private var sample: [Recording] {
        [item("Heute früh", daysAgo: 0, hour: 8, category: bio, tasks: 2),
         item("Heute Mittag", daysAgo: 0, hour: 12),
         item("Gestern", daysAgo: 1, category: chem, status: .failed),
         item("Letzte Woche", daysAgo: 6, category: bio),
         item("Letztes Jahr", daysAgo: 400, status: .transcribing, tasks: 1)]
    }

    func testFilterRawValuesSurviveSceneStorage() {
        for filter in [LibraryFilter.all, .openTasks, .uncategorized, .problems, .category(bio)] {
            XCTAssertEqual(LibraryFilter(rawValue: filter.rawValue), filter)
        }
        XCTAssertNil(LibraryFilter(rawValue: "category:kaputt"))
        XCTAssertNil(LibraryFilter(rawValue: ""))
    }

    func testSidebarFilters() {
        func titles(_ filter: LibraryFilter) -> [String] { sample.filter(filter.matches).map(\.title) }
        XCTAssertEqual(titles(.all).count, 5)
        XCTAssertEqual(titles(.openTasks), ["Heute früh", "Letztes Jahr"])
        XCTAssertEqual(titles(.uncategorized), ["Heute Mittag", "Letztes Jahr"])
        XCTAssertEqual(titles(.problems), ["Gestern"])
        XCTAssertEqual(titles(.category(bio)), ["Heute früh", "Letzte Woche"])
        XCTAssertEqual(titles(.category(UUID())), [])
    }

    func testCounts() {
        let counts = LibraryListing.counts(sample)
        XCTAssertEqual(counts.all, 5)
        XCTAssertEqual(counts.openTasks, 2)
        XCTAssertEqual(counts.uncategorized, 2)
        XCTAssertEqual(counts.problems, 1)
        XCTAssertEqual(counts.perCategory, [bio: 2, chem: 1])
        XCTAssertEqual(counts.count(for: .category(chem)), 1)
        XCTAssertEqual(counts.count(for: .category(UUID())), 0)
        XCTAssertEqual(LibraryListing.counts([Recording]()), LibraryCounts())
    }

    func testGroupedByDay() {
        let sections = LibraryListing.groupedByDay(sample.shuffled(), now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Heute", "Gestern", "Freitag, 11. September", "Mittwoch, 13. August 2025"])
        XCTAssertEqual(sections[0].items.map(\.title), ["Heute Mittag", "Heute früh"], "Innerhalb des Tages neueste zuerst")
        XCTAssertTrue(LibraryListing.groupedByDay([Recording](), now: now, calendar: calendar).isEmpty)
    }

    func testSearchVariantsAreTolerant() {
        XCTAssertEqual(SearchText.variants("  "), [])
        XCTAssertEqual(SearchText.normalized("  Eigen   werte "), "Eigen werte")
        XCTAssertTrue(SearchText.variants("Mueller").contains("Müller"))
        XCTAssertTrue(SearchText.variants("Strasse").contains("Straße"))
        XCTAssertTrue(SearchText.variants("Straße").contains("Strasse"))
        XCTAssertTrue(SearchText.matches("Besprechung mit Frau Müller", query: "mueller"))
        XCTAssertTrue(SearchText.matches("Besprechung mit Frau Müller", query: "MÜLLER"))
        XCTAssertTrue(SearchText.matches("Besprechung mit Frau Müller", query: "muller"), "Ohne Umlaut-Punkte")
        XCTAssertTrue(SearchText.matches("Café am Markt", query: "cafe"))
        XCTAssertFalse(SearchText.matches("Besprechung", query: "Budget"))
        XCTAssertTrue(SearchText.matches("irgendwas", query: ""), "Leere Suche passt immer")
    }
}

final class NoteMarkdownTests: XCTestCase {
    private let note = """
    Kurzfassung der **Sitzung**.
    Zweite Zeile desselben Absatzes.

    ## Budget [00:14:05]
    - Mehr Geld für Hardware
      - Unterpunkt
    1. Erstens

    ## Aufgaben
    - [ ] Anna: Angebot einholen
    - [x] Tom: Raum buchen
    * [X] Lea: Protokoll

    > Ein Zitat
    ---
    ### Offene Fragen
    """

    func testBlocks() {
        let blocks = NoteMarkdown.blocks(note)
        XCTAssertEqual(blocks, [
            .paragraph(id: 0, text: "Kurzfassung der **Sitzung**. Zweite Zeile desselben Absatzes."),
            .heading(id: 1, level: 2, text: "Budget", timestamp: "00:14:05"),
            .bullet(id: 2, text: "Mehr Geld für Hardware", indent: 0),
            .bullet(id: 3, text: "Unterpunkt", indent: 1),
            .numbered(id: 4, number: "1", text: "Erstens", indent: 0),
            .heading(id: 5, level: 2, text: "Aufgaben", timestamp: nil),
            .task(id: 6, text: "Anna: Angebot einholen", isDone: false, line: 9),
            .task(id: 7, text: "Tom: Raum buchen", isDone: true, line: 10),
            .task(id: 8, text: "Lea: Protokoll", isDone: true, line: 11),
            .quote(id: 9, text: "Ein Zitat"),
            .heading(id: 10, level: 3, text: "Offene Fragen", timestamp: nil),
        ])
        XCTAssertEqual(NoteMarkdown.blocks(""), [])
    }

    func testToggleTaskChangesOnlyThatLine() throws {
        let checked = try XCTUnwrap(NoteMarkdown.togglingTask(in: note, line: 9))
        XCTAssertTrue(checked.contains("- [x] Anna: Angebot einholen"))
        XCTAssertEqual(checked.components(separatedBy: "\n").count, note.components(separatedBy: "\n").count)
        XCTAssertEqual(NoteMarkdown.openTaskCount(checked), 0)
        let unchecked = try XCTUnwrap(NoteMarkdown.togglingTask(in: checked, line: 9))
        XCTAssertEqual(unchecked, note, "Zweimal umschalten ergibt wieder das Original")
        XCTAssertEqual(NoteMarkdown.togglingTask(in: note, line: 11)?.contains("* [ ] Lea: Protokoll"), true)
        XCTAssertNil(NoteMarkdown.togglingTask(in: note, line: 3), "Überschrift ist keine Aufgabe")
        XCTAssertNil(NoteMarkdown.togglingTask(in: note, line: 999))
    }

    func testShareText() {
        XCTAssertEqual(NoteMarkdown.shareText(title: "Titel", markdown: "Text"), "# Titel\n\nText")
    }
}

final class LibrarySearchTests: XCTestCase {
    func testSearchFindsTitleNoteAndTranscript() async throws {
        let library = SwiftDataLibraryRepository(modelContainer: try LibraryContainer.makeInMemory())
        let a = Recording(title: "Budgetrunde"), b = Recording(title: "Vorlesung"), c = Recording(title: "Sprachnotiz")
        for r in [a, b, c] { try await library.insertRecording(r) }
        try await library.saveNote(Summary(title: "Treffen", markdown: "Frau Müller stellt den Plan vor.", taskCount: 0, provider: "P"), for: b.id)
        try await library.saveTranscript(Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: "Die Eigenwertzerlegung ist wichtig.")],
                                                    engine: "E"), for: c.id)

        let byTitle = try await library.searchRecordingIDs(matching: "budget")
        XCTAssertEqual(byTitle, [a.id])
        let byNote = try await library.searchRecordingIDs(matching: "mueller")
        XCTAssertEqual(byNote, [b.id])
        let byTranscript = try await library.searchRecordingIDs(matching: "EIGENWERT")
        XCTAssertEqual(byTranscript, [c.id], "Nur im Transkript")
        let none = try await library.searchRecordingIDs(matching: "Quantenphysik")
        XCTAssertTrue(none.isEmpty)
        let empty = try await library.searchRecordingIDs(matching: "  ")
        XCTAssertTrue(empty.isEmpty)
    }

    func testSearchPerformanceWithThousandRecordings() async throws {
        let library = SwiftDataLibraryRepository(modelContainer: try LibraryContainer.makeInMemory())
        let words = (0..<200).map { "Satz \($0) über Eigenwerte, Matrizen und die Übung am Donnerstag." }.joined(separator: " ")
        var items: [LibraryImportItem] = []
        for i in 0..<1_000 {
            let r = Recording(title: "Aufnahme \(i)", startedAt: Date(timeIntervalSince1970: Double(i) * 60), status: .done)
            let text = i == 777 ? words + " Das Wort Zauberwürfel kommt nur hier vor." : words
            items.append(LibraryImportItem(recording: r, transcript: Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: text)], engine: "E"),
                                           note: Summary(title: "Notiz \(i)", markdown: "Inhalt \(i)", taskCount: 0, provider: "P")))
        }
        for start in stride(from: 0, to: items.count, by: 100) {
            _ = try await library.importItems(Array(items[start..<min(start + 100, items.count)]))
        }
        let clock = ContinuousClock()
        var found = Set<UUID>()
        let duration = try await clock.measure { found = try await library.searchRecordingIDs(matching: "zauberwuerfel") }
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        print("LEISTUNG: Suche in 1000 Aufnahmen (je ~13 000 Zeichen Transkript) \(String(format: "%.3f", seconds)) s")
        XCTAssertEqual(found, [items[777].recording.id])
        XCTAssertLessThan(seconds, 1.0)
    }
}
