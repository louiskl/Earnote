import AppKit
import Combine
import SwiftUI

/// Pegelanzeige – getrennt vom AppState, damit nicht die ganze Oberfläche 10× pro Sekunde neu zeichnet.
@MainActor
final class LiveMeter: ObservableObject {
    @Published var mic: Float = 0
    @Published var system: Float = 0
    @Published var elapsed: TimeInterval = 0
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Zustand
    @Published var settings: AppSettings { didSet { persistSettings() } }
    @Published var categories: [RecordingCategory] { didSet { persistCategories() } }
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var activeRecordingID: UUID?
    @Published var selection: UUID?
    @Published var lastError: String?

    let meter = LiveMeter()
    let detector = MeetingDetector()

    private var session: RecordingSession?
    private var meterTimer: Timer?
    private var processingQueue: [UUID] = []
    private var isProcessing = false
    private var recordingStartedByCall = false
    private var cancellables = Set<AnyCancellable>()

    var isRecording: Bool { activeRecordingID != nil }
    var activeRecording: Recording? { activeRecordingID.flatMap(recording) }

    private init() {
        let d = UserDefaults.standard
        settings = d.data(forKey: "settings").flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        categories = d.data(forKey: "categories").flatMap { try? JSONDecoder().decode([RecordingCategory].self, from: $0) }
            ?? RecordingCategory.defaults
        loadRecordings()
        resumeInterruptedWork()

        detector.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        detector.onCallStarted = { [weak self] app in self?.callStarted(app) }
        detector.onCallEnded = { [weak self] app in self?.callEnded(app) }
        if settings.meetingDetection { detector.start() }
    }

    // MARK: Persistenz

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
        if settings.meetingDetection { detector.start() } else { detector.stop() }
    }

    private func persistCategories() {
        if let data = try? JSONEncoder().encode(categories) { UserDefaults.standard.set(data, forKey: "categories") }
    }

    private func loadRecordings() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Storage.recordingsDir, includingPropertiesForKeys: nil)) ?? []
        recordings = dirs.compactMap { dir in
            Storage.load(Recording.self, from: dir.appendingPathComponent("meta.json"))
        }.sorted { $0.startedAt > $1.startedAt }
    }

    /// Nach einem Absturz: unterbrochene Aufnahmen/Verarbeitungen wieder aufnehmen.
    private func resumeInterruptedWork() {
        for r in recordings where r.status == .recording || r.status.isBusy {
            update(r.id) {
                if $0.status == .recording { $0.endedAt = $0.endedAt ?? Date() }
                $0.status = .queued
            }
            enqueue(r.id)
        }
    }

    func recording(_ id: UUID) -> Recording? { recordings.first { $0.id == id } }
    func category(_ id: UUID?) -> RecordingCategory? { id.flatMap { cid in categories.first { $0.id == cid } } }

    func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
        Storage.save(recordings[i], to: Storage.metaURL(id))
    }

    private func insert(_ r: Recording) {
        recordings.insert(r, at: 0)
        Storage.save(r, to: Storage.metaURL(r.id))
    }

    // MARK: Aufnahme

    func startRecording(category: RecordingCategory?, title: String = "", sourceApp: String? = nil, byCall: Bool = false) {
        guard !isRecording else { return }
        Task {
            if MicRecorder.permission != .authorized {
                guard await MicRecorder.requestPermission() else {
                    lastError = "Earmark hat keinen Zugriff auf das Mikrofon. Bitte in den Systemeinstellungen erlauben."
                    SystemSettingsLink.microphone()
                    return
                }
            }
            let df = DateFormatter()
            df.locale = Locale(identifier: "de_DE")
            df.dateFormat = "d. MMM, HH:mm"
            let cat = category ?? self.category(settings.defaultCategoryID) ?? categories.first
            let name = title.isEmpty ? "\(cat?.name ?? "Aufnahme") – \(df.string(from: Date()))" : title
            var rec = Recording(title: name, categoryID: cat?.id, sourceApp: sourceApp)
            rec.language = settings.language

            let session = RecordingSession(recordingID: rec.id)
            do {
                try session.start(includeSystemAudio: settings.recordSystemAudio)
            } catch {
                lastError = "Aufnahme konnte nicht starten: \(error.localizedDescription)"
                Log.error(lastError!)
                try? FileManager.default.removeItem(at: Storage.folder(for: rec.id))
                return
            }
            rec.hasSystemAudio = session.systemAudioActive
            insert(rec)
            self.session = session
            activeRecordingID = rec.id
            recordingStartedByCall = byCall
            startMeter(startedAt: rec.startedAt)
            FloatingPanels.shared.hideCallPrompt()
            Log.info("Aufnahme gestartet: \(name) (Systemton: \(session.systemAudioActive))")
        }
    }

    func stopRecording() {
        guard let id = activeRecordingID else { return }
        session?.stop()
        session = nil
        activeRecordingID = nil
        recordingStartedByCall = false
        stopMeter()
        update(id) {
            $0.endedAt = Date()
            $0.status = .queued
        }
        Log.info("Aufnahme beendet")
        enqueue(id)
    }

    func cancelRecording() {
        guard let id = activeRecordingID else { return }
        session?.stop()
        session = nil
        activeRecordingID = nil
        stopMeter()
        delete(id)
    }

    private func startMeter(startedAt: Date) {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.session else { return }
                self.meter.mic = s.micLevel
                self.meter.system = s.systemLevel
                self.meter.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        meter.mic = 0; meter.system = 0; meter.elapsed = 0
    }

    // MARK: Call-Erkennung

    private func callStarted(_ app: String) {
        guard settings.meetingDetection, !isRecording else { return }
        FloatingPanels.shared.showCallPrompt(app: app)
    }

    private func callEnded(_ app: String) {
        FloatingPanels.shared.hideCallPrompt()
        if isRecording, recordingStartedByCall, settings.autoStopWhenCallEnds {
            stopRecording()
            Notifier.send("Call beendet", "Die Aufnahme aus \(app) wird jetzt verarbeitet.")
        }
    }

    // MARK: Import

    func importAudio(_ urls: [URL], category: RecordingCategory?) {
        for url in urls {
            var rec = Recording(title: url.deletingPathExtension().lastPathComponent, categoryID: category?.id)
            let dest = Storage.folder(for: rec.id).appendingPathComponent("import.\(url.pathExtension)")
            do {
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                lastError = "Import fehlgeschlagen: \(error.localizedDescription)"
                continue
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            rec.startedAt = (attrs?[.creationDate] as? Date) ?? Date()
            if let reader = try? ResamplingReader(url: dest) {
                rec.endedAt = rec.startedAt.addingTimeInterval(reader.duration)
            }
            rec.importedFileName = dest.lastPathComponent
            rec.status = .queued
            rec.language = settings.language
            insert(rec)
            enqueue(rec.id)
        }
    }

    // MARK: Verarbeitung

    func enqueue(_ id: UUID) {
        guard !processingQueue.contains(id) else { return }
        processingQueue.append(id)
        update(id) { $0.status = .queued; $0.errorMessage = nil; $0.progress = 0 }
        processNext()
    }

    /// Alles neu: Transkription, Zusammenfassung, Export.
    func reprocess(_ id: UUID, retranscribe: Bool) {
        if retranscribe { try? FileManager.default.removeItem(at: Storage.transcriptURL(id)) }
        try? FileManager.default.removeItem(at: Storage.summaryURL(id))
        try? FileManager.default.removeItem(at: Storage.summaryURL(id).appendingPathExtension("json"))
        update(id) { $0.exports = [] }
        enqueue(id)
    }

    func reexport(_ id: UUID) {
        update(id) { $0.exports = [] }
        enqueue(id)
    }

    private func processNext() {
        guard !isProcessing, !processingQueue.isEmpty else { return }
        let id = processingQueue.removeFirst()
        isProcessing = true
        Task {
            await process(id)
            isProcessing = false
            processNext()
        }
    }

    private func setStep(_ id: UUID, _ status: RecordingStatus, _ progress: Double) {
        update(id) { $0.status = status; $0.progress = progress }
    }

    private func process(_ id: UUID) async {
        guard let rec = recording(id) else { return }
        let settings = self.settings
        let category = self.category(rec.categoryID)
        do {
            // 1) Transkript (falls noch nicht vorhanden)
            var transcript = Storage.load(Transcript.self, from: Storage.transcriptURL(id))
            if transcript == nil {
                transcript = try await transcribe(rec, settings: settings)
                Storage.save(transcript!, to: Storage.transcriptURL(id))
            }
            guard let transcript else { return }
            let text = transcript.formatted(includeSpeakers: settings.speakerLabels)

            // 2) Zusammenfassung
            var summary = Storage.load(Summary.self, from: Storage.summaryURL(id).appendingPathExtension("json"))
            if summary == nil, let client = try LLMFactory.make(settings.ai) {
                setStep(id, .summarizing, 0)
                let summarizer = Summarizer(client: client, chunkCharacters: settings.ai.provider.chunkCharacters,
                                            providerName: settings.ai.provider.label)
                let context = SummaryContext(category: category, titleHint: rec.title, sourceApp: rec.sourceApp,
                                             date: rec.startedAt, duration: rec.duration,
                                             hasSpeakers: settings.speakerLabels && rec.hasSystemAudio,
                                             language: settings.ai.summaryLanguage)
                let s = try await summarizer.summarize(transcript: text, context: context) { p in
                    Task { @MainActor in self.update(id) { $0.progress = p } }
                }
                Storage.save(s, to: Storage.summaryURL(id).appendingPathExtension("json"))
                try? ("# \(s.title)\n\n" + s.markdown).write(to: Storage.summaryURL(id), atomically: true, encoding: .utf8)
                summary = s
            }
            if let summary {
                update(id) { $0.summaryTitle = summary.title; $0.taskCount = summary.taskCount }
            }

            // 3) Export
            setStep(id, .exporting, 0)
            var ids = settings.destinations.enabled
            if let c = category, !c.destinationIDs.isEmpty { ids = c.destinationIDs }
            let already = Set((recording(id)?.exports ?? []).filter(\.success).map(\.destinationID))
            let payload = ExportPayload(recording: recording(id) ?? rec, category: category, summary: summary,
                                        transcript: text, settings: settings.destinations)
            var failures: [String] = []
            for destID in ids.sorted() where !already.contains(destID) {
                guard let dest = Destinations.make(destID), let info = Destinations.info(destID) else { continue }
                var result = ExportResult(destinationID: destID, destinationName: info.name, success: false, message: "")
                do {
                    result.url = try await dest.export(payload)
                    result.success = true
                    result.message = "Exportiert"
                } catch {
                    result.message = error.localizedDescription
                    failures.append("\(info.name): \(error.localizedDescription)")
                    Log.error("Export \(info.name): \(error.localizedDescription)")
                }
                update(id) { r in
                    r.exports.removeAll { $0.destinationID == destID }
                    r.exports.append(result)
                }
            }

            // 4) Aufräumen
            if !settings.keepAudioFiles { deleteAudio(id) }
            update(id) {
                $0.status = failures.isEmpty ? .done : .failed
                $0.progress = 1
                $0.errorMessage = failures.isEmpty ? nil : "Export teilweise fehlgeschlagen:\n" + failures.joined(separator: "\n")
            }
            let title = summary?.title ?? rec.title
            Notifier.send(failures.isEmpty ? "Notizen fertig" : "Notizen fertig (mit Export-Fehlern)", title)
            Log.info("Fertig verarbeitet: \(title)")
        } catch {
            let msg = error.localizedDescription
            update(id) { $0.status = .failed; $0.errorMessage = msg }
            Notifier.send("Verarbeitung fehlgeschlagen", msg)
            Log.error("Verarbeitung \(id): \(msg)")
        }
    }

    private func transcribe(_ rec: Recording, settings: AppSettings) async throws -> Transcript {
        let id = rec.id
        setStep(id, .transcribing, 0)
        let transcriber = try TranscriberFactory.make(for: settings)

        // Audio vorbereiten (mischen, 16 kHz)
        let source: URL
        var envelope: EnergyEnvelope?
        if let imported = rec.importedFileName {
            source = Storage.folder(for: id).appendingPathComponent(imported)
        } else {
            let mic = Storage.micURL(id)
            let system: URL? = rec.hasSystemAudio ? Storage.systemURL(id) : nil
            let out = Storage.mixURL(id)
            envelope = try await Task.detached(priority: .userInitiated) {
                try AudioMixer.mix(mic: mic, system: system, output: out) { p in
                    Task { @MainActor in AppState.shared.update(id) { $0.progress = p * 0.1 } }
                }
            }.value
            source = out
        }

        let peak = await Task.detached { AudioMixer.peakDecibels(of: source) }.value
        Log.info("Pegel der Aufnahme: \(peak) dB")
        if peak < -50 {
            throw TranscriptionError.unavailable(
                "Die Aufnahme ist stumm (Pegel \(Int(peak)) dB). Prüfe in den Systemeinstellungen, ob Earmark das Mikrofon verwenden darf und das richtige Eingabegerät ausgewählt ist.")
        }

        let language = rec.language
        let offset = envelope == nil ? 0.0 : 0.1
        var segments = try await transcriber.transcribe(audio: source, language: language) { p in
            Task { @MainActor in AppState.shared.update(id) { $0.progress = offset + p * (1 - offset) } }
        }
        guard !segments.isEmpty else { throw TranscriptionError.noSpeech }

        if let envelope, rec.hasSystemAudio {
            for i in segments.indices {
                segments[i].speaker = envelope.speaker(from: segments[i].start, to: segments[i].end)
            }
        }
        let engine = settings.transcriptionEngine == .apple ? "Apple" : "Whisper \(settings.whisperModel)"
        return Transcript(segments: segments, engine: engine)
    }

    // MARK: Verwaltung

    func rename(_ id: UUID, to title: String) { update(id) { $0.title = title } }

    func setCategory(_ id: UUID, _ categoryID: UUID?) { update(id) { $0.categoryID = categoryID } }

    func deleteAudio(_ id: UUID) {
        for url in [Storage.micURL(id), Storage.systemURL(id), Storage.mixURL(id)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func delete(_ id: UUID) {
        processingQueue.removeAll { $0 == id }
        try? FileManager.default.removeItem(at: Storage.folder(for: id))
        recordings.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    func transcript(_ id: UUID) -> Transcript? { Storage.load(Transcript.self, from: Storage.transcriptURL(id)) }
    func summary(_ id: UUID) -> Summary? { Storage.load(Summary.self, from: Storage.summaryURL(id).appendingPathExtension("json")) }
    func hasAudio(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: Storage.micURL(id).path)
            || FileManager.default.fileExists(atPath: Storage.mixURL(id).path)
            || recording(id)?.importedFileName != nil
    }

    func revealInFinder(_ id: UUID) {
        NSWorkspace.shared.activateFileViewerSelecting([Storage.folder(for: id)])
    }
}
