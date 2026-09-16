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
        ProcessingPipeline(repository: folder.repository, transcribers: transcriber,
                           llm: LLMFactory(platform: FakeLLMProvider(client: llm), apiKey: { _ in nil }),
                           destinations: FakeDestinations(destinations: destinations),
                           notify: { title, _ in notes.mutate { $0.append(title) } })
    }

    private func run(_ pipeline: ProcessingPipeline, _ rec: Recording,
                     settings: AppSettings = .testing()) async -> RecordingState {
        let state = RecordingState(rec, repository: folder.repository)
        await pipeline.process(rec, settings: settings, category: nil, events: state.events)
        return state
    }

    func testSuccessWritesFilesAndFinishes() async throws {
        let rec = try folder.importedRecording()
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

        let repository = folder.repository
        XCTAssertEqual(repository.transcript(for: rec.id)?.engine, "Fake")
        XCTAssertEqual(repository.summary(for: rec.id)?.title, "Montagstreffen")
        XCTAssertEqual(repository.loadRecordings().first?.status, .done, "meta.json aktualisiert")
        XCTAssertTrue(repository.hasAudio(done), "Audio bleibt standardmäßig erhalten")
    }

    func testAudioIsDeletedWhenNotKept() async throws {
        let rec = try folder.importedRecording()
        var settings = AppSettings.testing()
        settings.keepAudioFiles = false
        let state = await run(pipeline(), rec, settings: settings)
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertFalse(folder.repository.hasAudio(state.recording))
    }

    func testUnconfiguredDestinationIsSkippedButDone() async throws {
        let rec = try folder.importedRecording()
        let skipped = FakeDestination { throw DestinationNotConfigured(hint: "Noch nicht eingerichtet.") }
        let state = await run(pipeline(destinations: ["a": skipped]), rec)
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertNil(state.recording.errorMessage)
        let export = try XCTUnwrap(state.recording.exports.first)
        XCTAssertFalse(export.success)
        XCTAssertEqual(export.skipped, true)
        XCTAssertEqual(export.message, "Noch nicht eingerichtet.")
    }

    func testExportErrorFailsWithMessage() async throws {
        let rec = try folder.importedRecording()
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
        let rec = try folder.importedRecording()
        let llm = FakeLLMClient(answer: "# X\n\nY")
        let state = await run(pipeline(transcriber: FakeTranscriber { _ in [] }, llm: llm), rec)
        XCTAssertEqual(state.recording.status, .failed)
        XCTAssertEqual(state.recording.errorMessage,
                       "Transkription fehlgeschlagen: \(TranscriptionError.noSpeech.localizedDescription)")
        XCTAssertNil(folder.repository.transcript(for: rec.id))
        XCTAssertTrue(llm.calls.get().isEmpty)
    }

    func testSilentRecordingGivesUnderstandableError() async throws {
        let rec = try folder.importedRecording(silent: true)
        let transcriber = FakeTranscriber()
        let state = await run(pipeline(transcriber: transcriber), rec)
        XCTAssertEqual(state.recording.status, .failed)
        let message = try XCTUnwrap(state.recording.errorMessage)
        XCTAssertTrue(message.hasPrefix("Transkription fehlgeschlagen: Die Aufnahme ist stumm"), message)
        XCTAssertTrue(message.contains("Mikrofon"))
        XCTAssertTrue(transcriber.transcribed.get().isEmpty, "Stumme Aufnahme wird gar nicht erst transkribiert")
    }

    func testCancelDuringSummaryStoresNothingStale() async throws {
        let rec = try folder.importedRecording()
        let started = Locked(false)
        let llm = FakeLLMClient { _, _ in
            started.mutate { $0 = true }
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return "# Zu spät\n\nText"
        }
        let destination = FakeDestination()
        let p = pipeline(llm: llm, destinations: ["a": destination])
        let state = RecordingState(rec, repository: folder.repository)
        let task = Task { await p.process(rec, settings: .testing(), category: nil, events: state.events) }
        let deadline = Date().addingTimeInterval(10)
        while !started.get() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        task.cancel()
        await task.value

        XCTAssertEqual(state.recording.status, .summarizing, "Status bleibt, wie ihn der Abbruch vorgefunden hat")
        XCTAssertNil(state.recording.errorMessage)
        XCTAssertNil(folder.repository.summary(for: rec.id))
        XCTAssertNil(state.recording.summaryTitle)
        XCTAssertEqual(destination.exports.get(), 0)
        XCTAssertNotNil(folder.repository.transcript(for: rec.id), "Fertiges Transkript bleibt")
    }

    func testExistingTranscriptIsNotTranscribedAgain() async throws {
        let rec = Recording(title: "Ohne Audio", status: .queued)
        folder.repository.insert(rec)
        folder.repository.saveTranscript(Transcript(segments: FakeTranscriber.speech, engine: "Vorher"), for: rec.id)
        let transcriber = FakeTranscriber()
        let state = await run(pipeline(transcriber: transcriber), rec)
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertTrue(transcriber.transcribed.get().isEmpty)
        XCTAssertEqual(folder.repository.transcript(for: rec.id)?.engine, "Vorher")
        XCTAssertEqual(state.statuses.get(), [.summarizing, .exporting, .done])
    }

    func testSuccessfulDestinationsAreNotExportedAgain() async throws {
        var rec = try folder.importedRecording()
        rec.exports = [ExportResult(destinationID: "a", destinationName: "A", success: true, message: "Exportiert")]
        let a = FakeDestination(), b = FakeDestination()
        let state = await run(pipeline(destinations: ["a": a, "b": b]), rec, settings: .testing(destinations: ["a", "b"]))
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertEqual(a.exports.get(), 0)
        XCTAssertEqual(b.exports.get(), 1)
        XCTAssertEqual(Set(state.recording.exports.map(\.destinationID)), ["a", "b"])
    }

    func testMissingAIClientSkipsSummaryWithoutError() async throws {
        let rec = try folder.importedRecording()
        var settings = AppSettings.testing()
        settings.ai.provider = .none
        let state = await run(pipeline(), rec, settings: settings)
        XCTAssertEqual(state.recording.status, .done)
        XCTAssertNil(folder.repository.summary(for: rec.id))
    }
}

@MainActor
final class ProcessingQueueTests: XCTestCase {
    private var folder: TestFolder!
    override func setUp() async throws { folder = try TestFolder() }
    override func tearDown() async throws { folder = nil }

    private func makeQueue(_ transcriber: FakeTranscriber, library: TestLibrary, drained: Locked<Int> = Locked(0)) -> ProcessingQueue {
        let pipeline = ProcessingPipeline(repository: folder.repository, transcribers: transcriber,
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

    func testProcessesInOrderAndReleasesWhenDrained() async throws {
        let recs = try (0..<3).map { try folder.importedRecording(title: "R\($0)") }
        let library = TestLibrary(repository: folder.repository, settings: .testing())
        let transcriber = FakeTranscriber()
        let drained = Locked(0)
        let queue = makeQueue(transcriber, library: library, drained: drained)
        for r in recs { queue.enqueue(r.id) }
        await waitUntil { recs.allSatisfy { library.recording($0.id)?.status == .done } }
        XCTAssertEqual(transcriber.transcribed.get(), recs.map(\.id.uuidString))
        await waitUntil { drained.get() == 1 }
        XCTAssertNil(queue.processingID)
    }

    func testEnqueueNextGoesToFront() async throws {
        let recs = try (0..<3).map { try folder.importedRecording(title: "R\($0)") }
        let library = TestLibrary(repository: folder.repository, settings: .testing())
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
        let running = try folder.importedRecording(title: "läuft")
        let waiting = try folder.importedRecording(title: "wartet")
        let library = TestLibrary(repository: folder.repository, settings: .testing())
        let blocked = Locked<Set<String>>([running.id.uuidString])
        let queue = makeQueue(gatedTranscriber(blocked: blocked), library: library)
        queue.enqueue(running.id)
        queue.enqueue(waiting.id)
        await waitUntil { library.recording(running.id)?.status == .transcribing }

        library.delete(running.id, queue: queue)
        await waitUntil { library.recording(waiting.id)?.status == .done }
        XCTAssertNil(library.recording(running.id))
        XCTAssertFalse(folder.repository.exists(running.id), "Gelöschte Aufnahme wird nicht wieder angelegt")
        XCTAssertNil(folder.repository.transcript(for: running.id))
    }

    func testEnqueueAgainRestartsRunningRecording() async throws {
        let rec = try folder.importedRecording()
        let library = TestLibrary(repository: folder.repository, settings: .testing())
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
        var busy = try folder.importedRecording(title: "unterbrochen")
        busy.status = .summarizing
        busy.progress = 0.7
        folder.repository.update(busy)
        let queued = try folder.importedRecording(title: "wartend")
        var finished = try folder.importedRecording(title: "fertig")
        finished.status = .done
        folder.repository.update(finished)
        var crashed = Recording(title: "abgestürzte Aufnahme", startedAt: Date(timeIntervalSinceNow: -60), status: .recording)
        folder.repository.createFolder(for: crashed.id)
        try TestFolder.writeAudio(to: folder.repository.micURL(for: crashed.id), amplitude: 0.5, seconds: 2)
        folder.repository.insert(crashed)
        crashed = folder.repository.loadRecordings().first { $0.id == crashed.id }!

        // „Neustart“: neue Bibliothek und Warteschlange lesen den gespeicherten Stand
        let library = TestLibrary(repository: folder.repository, settings: .testing())
        let transcriber = FakeTranscriber()
        let queue = makeQueue(transcriber, library: library)
        queue.resumeInterruptedWork()

        await waitUntil { [busy, queued, crashed].allSatisfy { library.recording($0.id)?.status == .done } }
        XCTAssertFalse(transcriber.transcribed.get().contains(finished.id.uuidString), "Fertige bleiben unberührt")
        let resumed = try XCTUnwrap(library.recording(crashed.id))
        XCTAssertEqual(try XCTUnwrap(resumed.endedAt).timeIntervalSince(resumed.startedAt), 2, accuracy: 0.1,
                       "Ende aus der aufgenommenen Länge")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.repository.mixURL(for: crashed.id).path), "Mikrofon wurde gemischt")
    }
}
