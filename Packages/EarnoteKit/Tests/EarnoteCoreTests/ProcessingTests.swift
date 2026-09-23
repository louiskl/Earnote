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
        XCTAssertEqual(notes.get(), ["Notizen fertig"])

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
        XCTAssertEqual(state.recording.errorMessage, "Export teilweise fehlgeschlagen:\nA: kaputt")
        XCTAssertEqual(state.recording.exports.filter(\.success).map(\.destinationID), ["b"], "Übrige Ziele laufen weiter")
        XCTAssertEqual(notes.get(), ["Notizen fertig (mit Export-Fehlern)"])
    }

    func testEmptyTranscriptReportsNoSpeech() async throws {
        let rec = try await folder.importedRecording()
        let llm = FakeLLMClient(answer: "# X\n\nY")
        let state = await run(pipeline(transcriber: FakeTranscriber { _ in [] }, llm: llm), rec)
        XCTAssertEqual(state.recording.status, .failed)
        XCTAssertEqual(state.recording.errorMessage,
                       "Transkription fehlgeschlagen: \(TranscriptionError.noSpeech.localizedDescription)")
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
        XCTAssertTrue(message.hasPrefix("Transkription fehlgeschlagen: Die Aufnahme ist stumm"), message)
        XCTAssertTrue(message.contains("Mikrofon"))
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
