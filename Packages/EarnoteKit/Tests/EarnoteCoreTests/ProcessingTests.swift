import XCTest
@testable import EarnoteCore

final class ProcessingPipelineTests: XCTestCase {
    private var folder: TestFolder!
    override func setUpWithError() throws { folder = try TestFolder() }
    override func tearDown() { folder = nil }

    private func pipeline(transcriber: FakeTranscriber = FakeTranscriber(),
                          llm: FakeLLMClient = FakeLLMClient(answer: "# Montagstreffen\n\nTreffen vereinbart.\n\n- [ ] Raum buchen"),
                          destinations: [String: FakeDestination] = ["a": FakeDestination()],
                          notes: Locked<[String]> = Locked([])) -> ProcessingPipeline {
        ProcessingPipeline(library: folder.library, audio: folder.audio, transcribers: transcriber,
                           llm: LLMFactory(platform: FakeLLMProvider(client: llm), apiKey: { _ in nil }),
                           destinations: FakeDestinations(destinations: destinations),
                           notify: { title, _ in notes.mutate { $0.append(title) } })
    }

    private func run(_ pipeline: ProcessingPipeline, _ rec: Recording,
                     settings: AppSettings = .testing()) async -> RecordingState {
        let state = RecordingState(rec, library: folder.library)
        await pipeline.process(rec, settings: settings, category: nil, events: state.events)
        return state
    }

    func testSuccessWritesLibraryAndFinishes() async throws {
        let rec = try await folder.importedRecording()
        let destination = FakeDestination()
        let notes = Locked<[String]>([])
        let state = await run(pipeline(destinations: ["a": destination], notes: notes), rec)

        let done = state.recording
        XCTAssertEqual(done.status, .done)
        XCTAssertEqual(done.progress, 1)
        XCTAssertNil(done.errorMessage)
        XCTAssertEqual(done.summaryTitle, "Montagstreffen")
        XCTAssertEqual(done.summaryPreview, "Treffen vereinbart.")
        XCTAssertEqual(done.taskCount, 1)
        XCTAssertEqual(done.exports.map(\.destinationID), ["a"])
        XCTAssertEqual(done.exports.first?.success, true)
        XCTAssertEqual(done.exports.first?.url, "fake://ok")
        XCTAssertEqual(destination.exports.get(), 1)
        XCTAssertEqual(state.statuses.get(), [.transcribing, .summarizing, .exporting, .done])
        XCTAssertEqual(notes.get(), [t("Notizen fertig")])

        let library = folder.library
        let transcript = try await library.transcript(for: rec.id)
        XCTAssertEqual(transcript?.engine, "Fake")
        let note = try await library.note(for: rec.id)
        XCTAssertEqual(note?.title, "Montagstreffen")
        let stored = try await library.recording(rec.id)
        XCTAssertEqual(stored?.status, .done, "In der Bibliothek gespeichert")
        XCTAssertEqual(stored?.summaryTitle, "Montagstreffen")
        XCTAssertEqual(stored?.exports.map(\.destinationID), ["a"])
        XCTAssertTrue(folder.audio.hasAudio(done), "Audio bleibt standardmäßig erhalten")
    }

    /// Übersicht eines Bereichs: keine Aufnahme, kein Transkript, nur eine Notiz. „Neu zusammenfassen“ schrieb vorher
    /// ins Leere (keine Audiodatei) – und weil die Notiz vorab gelöscht war, war sie danach weg.
    private func overview(_ markdown: String) async throws -> Recording {
        let rec = Recording(title: "Übersicht", startedAt: Date(), endedAt: Date(), status: .done)
        try await folder.library.insertRecording(rec)
        try await folder.library.saveNote(Summary(title: "Übersicht", markdown: markdown, taskCount: 0, provider: "P"), for: rec.id)
        return rec
    }

    func testRewritesAnOverviewFromItsNote() async throws {
        let rec = try await overview("Der Bereich behandelte Speicher und Prozesse.")
        let llm = FakeLLMClient(answer: "# Neue Übersicht\n\nSpeicher und Prozesse, einfach erklärt.")
        let state = RecordingState(rec, library: folder.library)
        await pipeline(llm: llm).process(rec, settings: .testing(), category: nil, events: state.events, request: .again)

        XCTAssertEqual(state.recording.status, .done)
        XCTAssertTrue(llm.calls.get().last?.prompt.contains("Der Bereich behandelte Speicher und Prozesse.") == true,
                      "Grundlage ist die bisherige Notiz")
        let note = try await folder.library.note(for: rec.id)
        XCTAssertEqual(note?.title, "Neue Übersicht")
    }

    /// Karteikarten bleiben beim Neuschreiben erhalten, gehen aber nicht als Material an die KI;
    /// eine Übersicht wird dabei nicht plötzlich exportiert.
    func testRewriteKeepsFlashcardsAndDoesNotExportAnOverview() async throws {
        let rec = try await overview("Speicher und Prozesse.\n\n## Karteikarten\n\n- Was prüft die MMU? :: Jeden Speicherzugriff.")
        let llm = FakeLLMClient(answer: "# Neu\n\nSpeicher und Prozesse, einfach erklärt.")
        let destination = FakeDestination()
        let state = RecordingState(rec, library: folder.library)
        await pipeline(llm: llm, destinations: ["a": destination])
            .process(rec, settings: .testing(), category: nil, events: state.events, request: .fromNote)

        XCTAssertFalse(llm.calls.get().last?.prompt.contains("MMU") == true, "Karteikarten sind kein Material")
        let note = try await folder.library.note(for: rec.id)
        XCTAssertEqual(Flashcards.parse(note?.markdown ?? ""), [Flashcard(question: "Was prüft die MMU?", answer: "Jeden Speicherzugriff.")])
        XCTAssertTrue(note?.markdown.hasPrefix("Speicher und Prozesse, einfach erklärt.") == true)
        XCTAssertEqual(destination.exports.get(), 0, "Übersichten werden nie exportiert")
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertEqual(state.recording.isNoteEdited, false)
    }

    /// Weder Ton noch Transkript noch Notiz: verständlich sagen, statt mit einem Audiofehler abzubrechen
    func testNothingToWorkWithFailsWithAClearMessage() async throws {
        let rec = Recording(title: "Leer", startedAt: Date(), endedAt: Date(), status: .done)
        try await folder.library.insertRecording(rec)
        let state = await run(pipeline(), rec)
        XCTAssertEqual(state.recording.status, .failed)
        let message = t("Für diese Aufnahme gibt es weder Ton noch Transkript oder Notiz – daraus kann keine Notiz entstehen.")
        XCTAssertTrue(state.recording.errorMessage?.contains(message) == true,
                      state.recording.errorMessage ?? "")
    }

    func testKeepsTheOldNoteWhenRewritingFails() async throws {
        let rec = try await overview("Alte, gute Notiz.")
        let llm = FakeLLMClient { _, _ in throw LLMError(message: "KI nicht erreichbar") }
        let state = RecordingState(rec, library: folder.library)
        await pipeline(llm: llm).process(rec, settings: .testing(), category: nil, events: state.events, request: .again)

        XCTAssertEqual(state.recording.status, .failed)
        let note = try await folder.library.note(for: rec.id)
        XCTAssertEqual(note?.markdown, "Alte, gute Notiz.", "Nichts geht verloren")
    }

    /// Vereinfachen schreibt die Notiz um – auch wenn ein Transkript da ist, wird es nicht noch einmal gelesen.
    func testSimplifyUsesTheNoteNotTheTranscript() async throws {
        let rec = try await folder.importedRecording()
        let first = RecordingState(rec, library: folder.library)
        await pipeline().process(rec, settings: .testing(), category: nil, events: first.events)

        let llm = FakeLLMClient(answer: "# Einfach\n\nKurz und einfach.")
        let state = RecordingState(first.recording, library: folder.library)
        await pipeline(llm: llm).process(first.recording, settings: .testing(), category: nil, events: state.events,
                                         extraInstructions: "Einfache Sprache", request: .fromNote)
        let prompt = llm.calls.get().last?.prompt ?? ""
        XCTAssertTrue(prompt.contains("Treffen vereinbart."), "die bisherige Notiz")
        XCTAssertFalse(prompt.contains("Transkript:"), "nicht das Transkript")
        XCTAssertEqual(state.statuses.get().first, .summarizing, "keine neue Transkription")
    }

    /// Übersicht über einen Bereich: läuft in der Warteschlange, schreibt aus den Notizen, prüft die Aufgaben dagegen
    func testOverviewIsMadeFromTheNotesOfTheArea() async throws {
        let area = UUID()
        let category = RecordingCategory(id: area, name: "Betriebssysteme", symbol: "book.fill", colorHex: "#000000", instructions: "")
        try await folder.library.insertCategory(category, sortIndex: nil)
        for (title, note) in [("Vorlesung 1", "Die MMU prüft jeden Zugriff.\n\n- [ ] Übungsblatt 1 rechnen"),
                              ("Vorlesung 2", "SATA gegen NVMe.")] {
            let rec = Recording(title: title, categoryID: area, startedAt: Date(timeIntervalSinceNow: -3_600),
                                endedAt: Date(), status: .done)
            try await folder.library.insertRecording(rec)
            try await folder.library.saveNote(Summary(title: title, markdown: note, taskCount: 0, provider: "P"), for: rec.id)
        }
        let placeholder = Recording(title: "Übersicht – Betriebssysteme", categoryID: area, startedAt: Date(), endedAt: Date(),
                                    status: .queued)
        try await folder.library.insertRecording(placeholder)
        let llm = FakeLLMClient(answer: "# Betriebssysteme bis heute\n\n## Überblick\nDie MMU prüft jeden Zugriff, dazu SATA gegen NVMe.\n\n"
                                + "## Offene Aufgaben\n- [ ] Übungsblatt 1 rechnen\n- [ ] Team: Referat vorbereiten über NVMe-Leistung")
        let destination = FakeDestination()
        let state = RecordingState(placeholder, library: folder.library)
        await pipeline(llm: llm, destinations: ["a": destination])
            .process(placeholder, settings: .testing(), category: category, events: state.events, request: .overview(since: nil))

        XCTAssertEqual(state.recording.status, .done, state.recording.errorMessage ?? "")
        XCTAssertEqual(state.recording.title, "Betriebssysteme bis heute")
        let prompt = llm.calls.get().last?.prompt ?? ""
        XCTAssertTrue(prompt.contains("Die MMU prüft jeden Zugriff.") && prompt.contains("SATA gegen NVMe."))
        XCTAssertFalse(prompt.contains("Übersicht – Betriebssysteme"), "die Übersicht ist nicht ihre eigene Quelle")
        let note = try await folder.library.note(for: placeholder.id)
        XCTAssertTrue(note?.markdown.contains("- [ ] Übungsblatt 1 rechnen") == true, "steht so in einer Notiz")
        XCTAssertFalse(note?.markdown.contains("Referat") == true, "erfunden – fällt weg")
        XCTAssertEqual(destination.exports.get(), 0, "Übersichten werden nicht exportiert")
    }

    func testOverviewNeedsTwoNotes() async throws {
        let area = UUID()
        let placeholder = Recording(title: "Übersicht", categoryID: area, startedAt: Date(), endedAt: Date(), status: .queued)
        try await folder.library.insertRecording(placeholder)
        let state = RecordingState(placeholder, library: folder.library)
        let category = RecordingCategory(id: area, name: "Leer", symbol: "book.fill", colorHex: "#000000", instructions: "")
        await pipeline().process(placeholder, settings: .testing(), category: category, events: state.events,
                                 request: .overview(since: nil))
        XCTAssertEqual(state.recording.status, .failed)
    }

    func testAudioIsDeletedWhenNotKept() async throws {
        let rec = try await folder.importedRecording()
        var settings = AppSettings.testing()
        settings.keepAudioFiles = false
        let state = await run(pipeline(), rec, settings: settings)
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertFalse(folder.audio.hasAudio(state.recording))
    }

    func testUnconfiguredDestinationIsSkippedButDone() async throws {
        let rec = try await folder.importedRecording()
        let skipped = FakeDestination { throw DestinationNotConfigured(hint: "Noch nicht eingerichtet.") }
        let state = await run(pipeline(destinations: ["a": skipped]), rec)
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertNil(state.recording.errorMessage)
        let export = try XCTUnwrap(state.recording.exports.first)
        XCTAssertFalse(export.success)
        XCTAssertEqual(export.skipped, true)
        XCTAssertEqual(export.message, "Noch nicht eingerichtet.")
        let stored = try await folder.library.recording(rec.id)
        XCTAssertEqual(stored?.exports.first?.skipped, true, "Übersprungen bleibt nach dem Speichern erkennbar")
    }

    func testExportErrorFailsWithMessage() async throws {
        let rec = try await folder.importedRecording()
        let broken = FakeDestination { throw LLMError(message: "kaputt") }
        let notes = Locked<[String]>([])
        let state = await run(pipeline(destinations: ["a": broken, "b": FakeDestination()], notes: notes),
                              rec, settings: .testing(destinations: ["a", "b"]))
        XCTAssertEqual(state.recording.status, .failed)
        XCTAssertEqual(state.recording.errorMessage, t("Export teilweise fehlgeschlagen:") + "\nA: kaputt")
        XCTAssertEqual(state.recording.exports.filter(\.success).map(\.destinationID), ["b"], "Übrige Ziele laufen weiter")
        XCTAssertEqual(notes.get(), [t("Notizen fertig (mit Export-Fehlern)")])
    }

    func testEmptyTranscriptReportsNoSpeech() async throws {
        let rec = try await folder.importedRecording()
        let llm = FakeLLMClient(answer: "# X\n\nY")
        let state = await run(pipeline(transcriber: FakeTranscriber { _ in [] }, llm: llm), rec)
        XCTAssertEqual(state.recording.status, .failed)
        XCTAssertEqual(state.recording.errorMessage,
                       ProcessingPipeline.failure("Transkription", TranscriptionError.noSpeech))
        let transcript = try await folder.library.transcript(for: rec.id)
        XCTAssertNil(transcript)
        XCTAssertTrue(llm.calls.get().isEmpty)
    }

    func testSilentRecordingGivesUnderstandableError() async throws {
        let rec = try await folder.importedRecording(silent: true)
        let transcriber = FakeTranscriber()
        let state = await run(pipeline(transcriber: transcriber), rec)
        XCTAssertEqual(state.recording.status, .failed)
        let message = try XCTUnwrap(state.recording.errorMessage)
        XCTAssertTrue(message.hasPrefix(t("Transkription")), message)
        XCTAssertTrue(message.contains("-160 dB"), message)
        XCTAssertTrue(transcriber.transcribed.get().isEmpty, "Stumme Aufnahme wird gar nicht erst transkribiert")
    }

    func testCancelDuringSummaryStoresNothingStale() async throws {
        let rec = try await folder.importedRecording()
        let started = Locked(false)
        let llm = FakeLLMClient { _, _ in
            started.mutate { $0 = true }
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return "# Zu spät\n\nText"
        }
        let destination = FakeDestination()
        let p = pipeline(llm: llm, destinations: ["a": destination])
        let state = RecordingState(rec, library: folder.library)
        let task = Task { await p.process(rec, settings: .testing(), category: nil, events: state.events) }
        let deadline = Date().addingTimeInterval(10)
        while !started.get() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        task.cancel()
        await task.value

        XCTAssertEqual(state.recording.status, .summarizing, "Status bleibt, wie ihn der Abbruch vorgefunden hat")
        XCTAssertNil(state.recording.errorMessage)
        let note = try await folder.library.note(for: rec.id)
        XCTAssertNil(note)
        XCTAssertNil(state.recording.summaryTitle)
        XCTAssertEqual(destination.exports.get(), 0)
        let transcript = try await folder.library.transcript(for: rec.id)
        XCTAssertNotNil(transcript, "Fertiges Transkript bleibt")
    }

    func testExistingTranscriptIsNotTranscribedAgain() async throws {
        let rec = Recording(title: "Ohne Audio", status: .queued)
        try await folder.library.insertRecording(rec)
        try await folder.library.saveTranscript(Transcript(segments: FakeTranscriber.speech, engine: "Vorher"), for: rec.id)
        let transcriber = FakeTranscriber()
        let state = await run(pipeline(transcriber: transcriber), rec)
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertTrue(transcriber.transcribed.get().isEmpty)
        let transcript = try await folder.library.transcript(for: rec.id)
        XCTAssertEqual(transcript?.engine, "Vorher")
        XCTAssertEqual(state.statuses.get(), [.summarizing, .exporting, .done])
    }

    func testSuccessfulDestinationsAreNotExportedAgain() async throws {
        var rec = try await folder.importedRecording()
        rec.exports = [ExportResult(destinationID: "a", destinationName: "A", success: true, message: "Exportiert")]
        let a = FakeDestination(), b = FakeDestination()
        let state = await run(pipeline(destinations: ["a": a, "b": b]), rec, settings: .testing(destinations: ["a", "b"]))
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertEqual(a.exports.get(), 0)
        XCTAssertEqual(b.exports.get(), 1)
        XCTAssertEqual(Set(state.recording.exports.map(\.destinationID)), ["a", "b"])
    }

    func testMissingAIClientSkipsSummaryWithoutError() async throws {
        let rec = try await folder.importedRecording()
        var settings = AppSettings.testing()
        settings.ai.provider = .none
        let state = await run(pipeline(), rec, settings: settings)
        XCTAssertEqual(state.recording.status, .done)
        let note = try await folder.library.note(for: rec.id)
        XCTAssertNil(note)
    }
}

@MainActor
final class ProcessingQueueTests: XCTestCase {
    private var folder: TestFolder!
    override func setUp() async throws { folder = try TestFolder() }
    override func tearDown() async throws { folder = nil }

    private func makeQueue(_ transcriber: FakeTranscriber, library: TestLibrary, drained: Locked<Int> = Locked(0)) -> ProcessingQueue {
        let pipeline = ProcessingPipeline(library: folder.library, audio: folder.audio, transcribers: transcriber,
                                          llm: LLMFactory(platform: FakeLLMProvider(client: FakeLLMClient(answer: "# T\n\nX")),
                                                          apiKey: { _ in nil }),
                                          destinations: FakeDestinations(destinations: ["a": FakeDestination()]),
                                          notify: { _, _ in })
        let queue = ProcessingQueue(pipeline: pipeline) { drained.mutate { $0 += 1 } }
        queue.library = library
        return queue
    }

    /// Transcriber, der bei bestimmten Aufnahmen wartet, bis sie freigegeben (oder abgebrochen) werden
    private func gatedTranscriber(blocked: Locked<Set<String>>) -> FakeTranscriber {
        FakeTranscriber { url in
            let id = url.deletingLastPathComponent().lastPathComponent
            while blocked.get().contains(id) { try await Task.sleep(nanoseconds: 5_000_000) }
            return FakeTranscriber.speech
        }
    }

    private func importedRecordings(_ count: Int) async throws -> [Recording] {
        var recs: [Recording] = []
        for i in 0..<count { recs.append(try await folder.importedRecording(title: "R\(i)")) }
        return recs
    }

    func testProcessesInOrderAndReleasesWhenDrained() async throws {
        let recs = try await importedRecordings(3)
        let library = try await TestLibrary(folder: folder, settings: .testing())
        let transcriber = FakeTranscriber()
        let drained = Locked(0)
        let queue = makeQueue(transcriber, library: library, drained: drained)
        for r in recs { queue.enqueue(r.id) }
        await waitUntil { recs.allSatisfy { library.recording($0.id)?.status == .done } }
        XCTAssertEqual(transcriber.transcribed.get(), recs.map(\.id.uuidString))
        await waitUntil { drained.get() == 1 }
        XCTAssertNil(queue.processingID)
    }

    /// „Erst am Netzteil“: Nichts beginnt, solange die Warteschlange zurückgehalten wird
    func testHeldQueueWaitsUntilResumed() async throws {
        let recs = try await importedRecordings(2)
        let library = try await TestLibrary(folder: folder, settings: .testing())
        let transcriber = FakeTranscriber()
        let queue = makeQueue(transcriber, library: library)
        let onBattery = Locked(true)
        queue.isHeld = { onBattery.get() }
        for r in recs { queue.enqueue(r.id) }
        XCTAssertTrue(queue.isWaitingForPower)
        XCTAssertNil(queue.processingID)
        XCTAssertEqual(queue.pending, recs.map(\.id))
        XCTAssertEqual(library.recording(recs[0].id)?.status, .queued)

        onBattery.mutate { $0 = false }
        queue.resume()
        await waitUntil { recs.allSatisfy { library.recording($0.id)?.status == .done } }
        XCTAssertFalse(queue.isWaitingForPower)
        XCTAssertEqual(transcriber.transcribed.get(), recs.map(\.id.uuidString))
    }

    /// „Jetzt verarbeiten“ arbeitet alles ab, obwohl weiter zurückgehalten würde
    func testProcessNowIgnoresHold() async throws {
        let recs = try await importedRecordings(2)
        let library = try await TestLibrary(folder: folder, settings: .testing())
        let queue = makeQueue(FakeTranscriber(), library: library)
        queue.isHeld = { true }
        for r in recs { queue.enqueue(r.id) }
        XCTAssertTrue(queue.isWaitingForPower)
        queue.processNow()
        await waitUntil { recs.allSatisfy { library.recording($0.id)?.status == .done } }
        XCTAssertFalse(queue.isWaitingForPower)

        // Danach gilt die Zurückhaltung wieder
        let later = try await folder.importedRecording(title: "später")
        library.recordings = try await folder.library.recordings()
        queue.enqueue(later.id)
        XCTAssertTrue(queue.isWaitingForPower)
        XCTAssertEqual(library.recording(later.id)?.status, .queued)
    }

    func testEnqueueNextGoesToFront() async throws {
        let recs = try await importedRecordings(3)
        let library = try await TestLibrary(folder: folder, settings: .testing())
        let blocked = Locked<Set<String>>([recs[0].id.uuidString])
        let transcriber = gatedTranscriber(blocked: blocked)
        let queue = makeQueue(transcriber, library: library)
        queue.enqueue(recs[0].id)
        queue.enqueue(recs[1].id)
        queue.enqueue(recs[2].id, next: true)
        XCTAssertEqual(queue.pending, [recs[2].id, recs[1].id])
        blocked.mutate { $0.removeAll() }
        await waitUntil { recs.allSatisfy { library.recording($0.id)?.status == .done } }
        XCTAssertEqual(transcriber.transcribed.get(), [recs[0], recs[2], recs[1]].map(\.id.uuidString))
    }

    func testDeletingRunningRecordingCancelsAndQueueContinues() async throws {
        let running = try await folder.importedRecording(title: "läuft")
        let waiting = try await folder.importedRecording(title: "wartet")
        let library = try await TestLibrary(folder: folder, settings: .testing())
        let blocked = Locked<Set<String>>([running.id.uuidString])
        let queue = makeQueue(gatedTranscriber(blocked: blocked), library: library)
        queue.enqueue(running.id)
        queue.enqueue(waiting.id)
        await waitUntil { library.recording(running.id)?.status == .transcribing }

        await library.delete(running.id, queue: queue)
        await waitUntil { library.recording(waiting.id)?.status == .done }
        XCTAssertNil(library.recording(running.id))
        let stored = try await folder.library.recording(running.id)
        XCTAssertNil(stored, "Gelöschte Aufnahme wird nicht wieder angelegt")
        let transcript = try await folder.library.transcript(for: running.id)
        XCTAssertNil(transcript)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.audio.folderURL(for: running.id).path))
    }

    func testEnqueueAgainRestartsRunningRecording() async throws {
        let rec = try await folder.importedRecording()
        let library = try await TestLibrary(folder: folder, settings: .testing())
        let blocked = Locked<Set<String>>([rec.id.uuidString])
        let transcriber = gatedTranscriber(blocked: blocked)
        let queue = makeQueue(transcriber, library: library)
        queue.enqueue(rec.id)
        await waitUntil { library.recording(rec.id)?.status == .transcribing }
        queue.enqueue(rec.id, next: true)
        XCTAssertEqual(library.recording(rec.id)?.status, .queued)
        blocked.mutate { $0.removeAll() }
        await waitUntil { library.recording(rec.id)?.status == .done }
        XCTAssertEqual(transcriber.transcribed.get().count, 2, "Erster Durchgang abgebrochen, zweiter vollständig")
    }

    func testResumesInterruptedWorkAfterRestart() async throws {
        let busy = try await folder.importedRecording(title: "unterbrochen")
        try await folder.library.updateRecording(busy.id) { $0.status = .summarizing }
        let queued = try await folder.importedRecording(title: "wartend")
        let finished = try await folder.importedRecording(title: "fertig")
        try await folder.library.updateRecording(finished.id) { $0.status = .done }
        let crashed = Recording(title: "abgestürzte Aufnahme", startedAt: Date(timeIntervalSinceNow: -60), status: .recording)
        folder.audio.createFolder(for: crashed.id)
        try TestFolder.writeAudio(to: folder.audio.micURL(for: crashed.id), amplitude: 0.5, seconds: 2)
        try await folder.library.insertRecording(crashed)

        // „Neustart“: neue Bibliothek und Warteschlange lesen den gespeicherten Stand
        let library = try await TestLibrary(folder: folder, settings: .testing())
        let transcriber = FakeTranscriber()
        let queue = makeQueue(transcriber, library: library)
        queue.resumeInterruptedWork()

        await waitUntil { [busy, queued, crashed].allSatisfy { library.recording($0.id)?.status == .done } }
        XCTAssertFalse(transcriber.transcribed.get().contains(finished.id.uuidString), "Fertige bleiben unberührt")
        let resumed = try XCTUnwrap(library.recording(crashed.id))
        XCTAssertEqual(try XCTUnwrap(resumed.endedAt).timeIntervalSince(resumed.startedAt), 2, accuracy: 0.1,
                       "Ende aus der aufgenommenen Länge")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.audio.mixURL(for: crashed.id).path), "Mikrofon wurde gemischt")
        let stored = try await folder.library.recording(crashed.id)
        XCTAssertEqual(stored?.status, .done)
    }

    /// Weg B: Aufnahmen, die ein anderes Gerät bearbeitet, setzt dieses Gerät nach einem Neustart nicht fort
    func testResumeSkipsRecordingsAnotherDeviceProcesses() async throws {
        let mine = try await folder.importedRecording(title: "meine")
        let onMac = try await folder.importedRecording(title: "beim Mac")
        try await folder.library.updateRecording(onMac.id) { $0.status = .transcribing }
        let waiting = try await folder.importedRecording(title: "übergeben")
        try await folder.library.updateRecording(waiting.id) { $0.status = .waitingForMac }

        let library = try await TestLibrary(folder: folder, settings: .testing())
        let transcriber = FakeTranscriber()
        let queue = makeQueue(transcriber, library: library)
        let onMacID = onMac.id
        queue.resumes = { $0.id != onMacID }
        queue.resumeInterruptedWork()

        await waitUntil { library.recording(mine.id)?.status == .done }
        XCTAssertEqual(library.recording(onMac.id)?.status, .transcribing, "Gehört dem Mac")
        XCTAssertEqual(library.recording(waiting.id)?.status, .waitingForMac, "Übergeben ist nicht beschäftigt")
        XCTAssertFalse(transcriber.transcribed.get().contains(onMac.id.uuidString))
    }

    /// Über iCloud gekommen, ohne Audio hier: Das andere Gerät nimmt noch auf oder schreibt die Notiz selbst
    func testResumeSkipsSyncedRecordingsWithoutLocalAudio() async throws {
        let summarizing = Recording(title: "vom iPhone, wird dort zusammengefasst", startedAt: Date(), status: .summarizing)
        let recording = Recording(title: "nimmt am iPhone noch auf", startedAt: Date(), status: .recording)
        try await folder.library.insertRecording(summarizing)
        try await folder.library.insertRecording(recording)

        let library = try await TestLibrary(folder: folder, settings: .testing())
        let queue = makeQueue(FakeTranscriber(), library: library)
        queue.resumeInterruptedWork()

        XCTAssertNil(queue.processingID)
        XCTAssertEqual(library.recording(summarizing.id)?.status, .summarizing)
        XCTAssertEqual(library.recording(recording.id)?.status, .recording)
    }
}

/// Transkribieren während der Aufnahme (Phase 4a)
final class LiveTranscriptionTests: XCTestCase {
    private var folder: TestFolder!

    override func setUpWithError() throws {
        folder = try TestFolder()
    }

    override func tearDownWithError() throws {
        folder = nil
    }

    /// Der Transcriber liefert pro Abschnitt zwei Sätze, deren Zeiten immer bei 0 beginnen –
    /// genau wie eine echte Engine, die nur ihr Stück Audio kennt.
    private func chunkTranscriber() -> FakeTranscriber {
        let counter = Locked<Int>(0)
        return FakeTranscriber { _ in
            let n = counter.mutate { value -> Int in value += 1; return value }
            return [TranscriptSegment(start: 0, end: 1, text: "Satz A\(n)"),
                    TranscriptSegment(start: 1, end: 2, text: "Satz B\(n)")]
        }
    }

    func testTranscribesWhileRecordingAndStitchesTheParts() async throws {
        let id = UUID()
        folder.audio.createFolder(for: id)
        try TestFolder.writeAudio(to: folder.audio.micURL(for: id), amplitude: 0.5, seconds: 4)

        let live = LiveTranscription(recordingID: id, hasSystemAudio: false, language: "de", hints: [],
                                     audio: folder.audio, transcriber: chunkTranscriber(), chunkSeconds: 2)
        await live.advance()
        // Vom ersten Abschnitt bleibt nur der erste Satz: Der letzte könnte mitten im Wort enden.
        var covered = await live.coveredSeconds
        XCTAssertEqual(covered, 1, accuracy: 0.001)

        let finished = await live.finish()
        let transcript = try XCTUnwrap(finished)
        XCTAssertEqual(transcript.segments.map(\.text), ["Satz A1", "Satz A2", "Satz B2"])
        // Der zweite Abschnitt beginnt bei Sekunde 1, seine Zeiten sind entsprechend verschoben.
        XCTAssertEqual(transcript.segments[1].start, 1, accuracy: 0.001)
        XCTAssertEqual(transcript.segments[2].end, 3, accuracy: 0.001)
        covered = await live.coveredSeconds
        XCTAssertEqual(covered, 4, accuracy: 0.05, "Nach dem Stopp ist alles abgedeckt")
    }

    func testWithoutEnoughNewAudioNothingHappens() async throws {
        let id = UUID()
        folder.audio.createFolder(for: id)
        try TestFolder.writeAudio(to: folder.audio.micURL(for: id), amplitude: 0.5, seconds: 1)

        let live = LiveTranscription(recordingID: id, hasSystemAudio: false, language: "de", hints: [],
                                     audio: folder.audio, transcriber: chunkTranscriber(), chunkSeconds: 60)
        await live.advance()
        let covered = await live.coveredSeconds
        XCTAssertEqual(covered, 0, "Erst ab einem vollen Abschnitt lohnt sich ein Durchgang")
    }

    func testAFailingEngineFallsBackToTheNormalWay() async throws {
        let id = UUID()
        folder.audio.createFolder(for: id)
        try TestFolder.writeAudio(to: folder.audio.micURL(for: id), amplitude: 0.5, seconds: 4)
        struct Boom: Error {}
        let live = LiveTranscription(recordingID: id, hasSystemAudio: false, language: "de", hints: [],
                                     audio: folder.audio, transcriber: FakeTranscriber { _ in throw Boom() },
                                     chunkSeconds: 2)
        await live.advance()
        let failed = await live.hasFailed
        XCTAssertTrue(failed)
        let transcript = await live.finish()
        XCTAssertNil(transcript, "Ohne brauchbares Zwischenergebnis wird nach der Aufnahme normal transkribiert")
    }
}
