import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Pegelanzeige – getrennt vom AppState, damit nicht die ganze Oberfläche 10× pro Sekunde neu zeichnet.
@MainActor
final class LiveMeter: ObservableObject {
    @Published var mic: Float = 0
    @Published var system: Float = 0
    @Published var elapsed: TimeInterval = 0
}

/// Mitschrift während der Aufnahme – ebenfalls getrennt, damit nur die Textanzeige neu gezeichnet wird.
@MainActor
final class LiveTranscript: ObservableObject {
    /// Bereits feststehender Text
    @Published var settled = ""
    /// Noch vorläufiger Text, den die Erkennung gerade anpasst
    @Published var volatile = ""
    /// Nicht verfügbar (z. B. vor macOS 26 oder Sprache nicht unterstützt)
    @Published var unavailable: String?

    var isEmpty: Bool { settled.isEmpty && volatile.isEmpty }

    var text: String {
        settled.isEmpty ? volatile : (volatile.isEmpty ? settled : settled + " " + volatile)
    }

    func reset() { settled = ""; volatile = ""; unavailable = nil }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Zustand
    @Published var settings: AppSettings { didSet { persistSettings(previous: oldValue) } }
    @Published var categories: [RecordingCategory] { didSet { persistCategories() } }
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var activeRecordingID: UUID?
    @Published private(set) var isPaused = false
    @Published var selection: UUID?
    @Published var lastError: String?

    let meter = LiveMeter()
    let live = LiveTranscript()
    let detector = MeetingDetector()

    private var session: RecordingSession?
    private var isStarting = false
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var meterTimer: Timer?
    private var processingQueue: [UUID] = []
    private var processingID: UUID?
    private var processingTask: Task<Void, Never>?
    private var recordingActivity: NSObjectProtocol?
    private var liveTranscriber: AnyObject?
    private var processingActivity: NSObjectProtocol?
    private var recordingStartedByCall = false
    private var cancellables = Set<AnyCancellable>()

    var isRecording: Bool { activeRecordingID != nil }
    var activeRecording: Recording? { activeRecordingID.flatMap(recording) }

    private init() {
        let d = UserDefaults.standard
        settings = d.data(forKey: "settings").flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        categories = RecordingCategory.migrated(
            d.data(forKey: "categories").flatMap { try? JSONDecoder().decode([RecordingCategory].self, from: $0) }
                ?? RecordingCategory.defaults)
        persistCategories()
        loadRecordings()
        repairCategoryAssignments()
        fillMissingPreviews()
        resumeInterruptedWork()

        detector.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        detector.onCallStarted = { [weak self] app in self?.callStarted(app) }
        detector.onCallEnded = { [weak self] app in self?.callEnded(app) }
        if settings.meetingDetection { detector.start() }
    }

    // MARK: Persistenz

    private func persistSettings(previous: AppSettings? = nil) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
        if settings.meetingDetection { detector.start() } else { detector.stop() }
        // Wird der KI-Anbieter gewechselt, während gerade zusammengefasst wird: mit dem neuen Anbieter neu beginnen,
        // statt den alten (womöglich minutenlang) zu Ende laufen zu lassen.
        if let previous, previous.ai != settings.ai, let id = processingID, recording(id)?.status == .summarizing {
            enqueue(id, next: true)
        }
    }

    private func persistCategories() {
        if let data = try? JSONEncoder().encode(categories) { UserDefaults.standard.set(data, forKey: "categories") }
    }

    private func loadRecordings() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Storage.recordingsDir, includingPropertiesForKeys: nil)) ?? []
        recordings = dirs.compactMap { dir in
            if let r = Storage.load(Recording.self, from: dir.appendingPathComponent("meta.json")) { return r }
            // Leere Überbleibsel gelöschter Aufnahmen entfernen
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            if contents.allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(at: dir) }
            return nil
        }.sorted { $0.startedAt > $1.startedAt }
    }

    /// Früher wurden die Standardkategorien erst beim ersten Bearbeiten gespeichert und bekamen bei jedem Start
    /// neue IDs – Aufnahmen verloren so ihre Kategorie. Zuordnung über den automatischen Namen wiederherstellen.
    private func repairCategoryAssignments() {
        for r in recordings where r.categoryID != nil && category(r.categoryID) == nil {
            if let match = categories.first(where: { r.title.hasPrefix("\($0.name) – ") }) {
                update(r.id) { $0.categoryID = match.id }
            }
        }
    }

    /// Aufnahmen aus älteren Versionen haben noch keine Vorschau für die Liste.
    private func fillMissingPreviews() {
        for r in recordings where r.summaryPreview == nil {
            if let preview = summary(r.id)?.preview { update(r.id) { $0.summaryPreview = preview } }
        }
    }

    /// Nach einem Absturz oder erzwungenem Beenden: unterbrochene Aufnahmen/Verarbeitungen wieder aufnehmen.
    private func resumeInterruptedWork() {
        for r in recordings where r.status == .recording || r.status.isBusy {
            if r.status == .recording {
                // Ende aus der tatsächlich aufgenommenen Länge ableiten, nicht aus dem Zeitpunkt des Neustarts
                let recorded = Self.recordedDuration(r.id)
                update(r.id) {
                    if let recorded {
                        $0.endedAt = $0.startedAt.addingTimeInterval(recorded)
                        $0.pausedDuration = nil
                    } else {
                        $0.endedAt = $0.endedAt ?? Date()
                    }
                }
            }
            enqueue(r.id)
        }
    }

    /// Länge der Mikrofonaufnahme in Sekunden (ohne Pausen).
    private static func recordedDuration(_ id: UUID) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: Storage.micURL(id)), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    func recording(_ id: UUID) -> Recording? { recordings.first { $0.id == id } }
    func category(_ id: UUID?) -> RecordingCategory? { id.flatMap { cid in categories.first { $0.id == cid } } }

    func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
        Storage.save(recordings[i], to: Storage.metaURL(id))
    }

    /// Fortschritt nur im Speicher ändern – wird oft aufgerufen und landet beim nächsten Statuswechsel mit auf der Platte.
    /// Läuft nur vorwärts, damit verspätet eintreffende Meldungen den Balken nicht zurückwerfen
    /// (zurückgesetzt wird er beim Einreihen über `update`).
    private func setProgress(_ id: UUID, _ progress: Double) {
        guard let i = recordings.firstIndex(where: { $0.id == id }), progress > recordings[i].progress else { return }
        recordings[i].progress = progress
    }

    /// Fortschritt eines Schritts (0…1) auf seinen Abschnitt des Gesamtbalkens abbilden.
    private func setProgress(_ id: UUID, _ progress: Double, in span: ClosedRange<Double>) {
        setProgress(id, span.lowerBound + (span.upperBound - span.lowerBound) * min(max(progress, 0), 1))
    }

    private func insert(_ r: Recording) {
        recordings.insert(r, at: 0)
        Storage.save(r, to: Storage.metaURL(r.id))
    }

    // MARK: Aufnahme

    func startRecording(category: RecordingCategory?, title: String = "", sourceApp: String? = nil, byCall: Bool = false) {
        // isStarting verhindert Doppelstarts (Doppelklick, Call-Pop-up + Menü gleichzeitig)
        guard !isRecording, !isStarting else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            if MicRecorder.permission != .authorized {
                guard await MicRecorder.requestPermission() else {
                    lastError = "\(AppInfo.name) hat keinen Zugriff auf das Mikrofon. Bitte in den Systemeinstellungen erlauben."
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
            isPaused = false
            pausedAt = nil
            pausedTotal = 0
            recordingActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Aufnahme läuft")
            startMeter(startedAt: rec.startedAt)
            startLiveTranscript(session: session, language: rec.language)
            FloatingPanels.shared.hideCallPrompt()
            Log.info("Aufnahme gestartet: \(name) (Systemton: \(session.systemAudioActive))")
        }
    }

    func pauseRecording() {
        guard let session, !isPaused else { return }
        try? session.setPaused(true)
        pausedAt = Date()
        isPaused = true
        Log.info("Aufnahme pausiert")
    }

    func resumeRecording() {
        guard let session, isPaused else { return }
        do {
            try session.setPaused(false)
        } catch {
            // Z. B. Mikrofon inzwischen abgezogen: pausiert lassen, damit nichts stillschweigend fehlt
            lastError = "Die Aufnahme konnte nicht fortgesetzt werden: \(error.localizedDescription)\n"
                + "Prüfe das Mikrofon und versuche es erneut, oder stoppe die Aufnahme."
            Log.error("Fortsetzen fehlgeschlagen: \(error.localizedDescription)")
            return
        }
        if let pausedAt { pausedTotal += Date().timeIntervalSince(pausedAt) }
        pausedAt = nil
        isPaused = false
        Log.info("Aufnahme fortgesetzt")
    }

    func togglePause() {
        if isPaused { resumeRecording() } else { pauseRecording() }
    }

    /// Pausen insgesamt, einschließlich einer gerade laufenden Pause.
    private var totalPaused: TimeInterval {
        pausedTotal + (pausedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    func stopRecording() {
        guard let id = activeRecordingID else { return }
        let paused = totalPaused
        endRecordingSession()
        update(id) {
            $0.endedAt = Date()
            $0.pausedDuration = paused > 0 ? paused : nil
            $0.status = .queued
        }
        Log.info("Aufnahme beendet")
        enqueue(id)
    }

    func cancelRecording() {
        guard let id = activeRecordingID else { return }
        endRecordingSession()
        delete(id)
    }

    /// Läuft während der Aufnahme mit und zeigt an, was gerade gesprochen wird.
    /// Das endgültige Transkript entsteht danach weiterhin aus der Audiodatei.
    private func startLiveTranscript(session: RecordingSession, language: String) {
        live.reset()
        guard #available(macOS 26.0, *) else {
            live.unavailable = "Die Live-Mitschrift benötigt macOS 26 oder neuer."
            return
        }
        #if canImport(FoundationModels)
        let transcriber = LiveTranscriber()
        liveTranscriber = transcriber
        Task { [weak self] in
            do {
                try await transcriber.start(language: language) { settled, volatile in
                    self?.live.settled = settled
                    self?.live.volatile = volatile
                }
                guard let format = transcriber.audioFormat else { return }
                session.startLiveAudio(format: format) { [weak transcriber] buffer in
                    transcriber?.append(buffer)
                }
            } catch {
                self?.live.unavailable = "Live-Mitschrift nicht möglich: \(error.localizedDescription)"
                Log.error("Live-Mitschrift: \(error.localizedDescription)")
            }
        }
        #endif
    }

    private func stopLiveTranscript() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let transcriber = liveTranscriber as? LiveTranscriber {
            Task { await transcriber.stop() }
        }
        #endif
        liveTranscriber = nil
    }

    private func endRecordingSession() {
        stopLiveTranscript()
        session?.stop()
        session = nil
        activeRecordingID = nil
        recordingStartedByCall = false
        isPaused = false
        pausedAt = nil
        pausedTotal = 0
        if let recordingActivity { ProcessInfo.processInfo.endActivity(recordingActivity) }
        recordingActivity = nil
        stopMeter()
    }

    private func startMeter(startedAt: Date) {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.session else { return }
                self.meter.mic = s.micLevel
                self.meter.system = s.systemLevel
                self.meter.elapsed = max(0, Date().timeIntervalSince(startedAt) - self.totalPaused)
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
                Storage.createFolder(for: rec.id)
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                try? FileManager.default.removeItem(at: Storage.folder(for: rec.id))
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

    func enqueue(_ id: UUID, next: Bool = false) {
        guard recording(id) != nil else { return }
        // Wird die Aufnahme gerade verarbeitet (z. B. „Neu zusammenfassen“ während der Transkription),
        // den laufenden Durchgang abbrechen und mit dem neuen Stand von vorn beginnen.
        if processingID == id { processingTask?.cancel() }
        processingQueue.removeAll { $0 == id }
        processingQueue.insert(id, at: next ? 0 : processingQueue.endIndex)
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

    /// Arbeitet die Warteschlange nacheinander ab. Ein Fehler bei einer Aufnahme hält die übrigen nicht auf.
    private func processNext() {
        guard processingID == nil else { return }
        guard !processingQueue.isEmpty else {
            queueDidDrain()
            return
        }
        let id = processingQueue.removeFirst()
        processingID = id
        if processingActivity == nil {
            // Verhindert Ruhezustand und App Nap, solange verarbeitet wird
            processingActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Aufnahmen werden verarbeitet")
        }
        processingTask = Task {
            await process(id)
            processingID = nil
            processingTask = nil
            processNext()
        }
    }

    private func queueDidDrain() {
        if let processingActivity { ProcessInfo.processInfo.endActivity(processingActivity) }
        processingActivity = nil
        Task {
            await WhisperKitCache.shared.release()
            await LocalLLMCache.shared.release()
        }
    }

    private func setStep(_ id: UUID, _ status: RecordingStatus, _ progress: Double) {
        update(id) { $0.status = status; $0.progress = progress }
    }

    private func process(_ id: UUID) async {
        guard let rec = recording(id) else { return }
        let settings = self.settings
        let category = self.category(rec.categoryID)
        var step = "Transkription"
        do {
            // 1) Transkript (falls noch nicht vorhanden)
            var transcript = Storage.load(Transcript.self, from: Storage.transcriptURL(id))
            // Ein durchgehender Balken für die ganze Verarbeitung statt einem neuen pro Schritt:
            // Transkription bis 60 %, Zusammenfassung bis 95 %, der Rest ist der Export.
            let summarySpan = (transcript == nil ? 0.6 : 0.0)...0.95
            if transcript == nil {
                let fresh = try await transcribe(rec, settings: settings, span: 0...0.6)
                // Nach jedem längeren Schritt prüfen, ob die Aufnahme inzwischen gelöscht oder neu gestartet wurde,
                // damit kein veralteter Stand gespeichert wird.
                try Task.checkCancellation()
                Storage.save(fresh, to: Storage.transcriptURL(id))
                transcript = fresh
            }
            guard let transcript else { return }
            let text = transcript.formatted(includeSpeakers: settings.speakerLabels)

            // 2) Zusammenfassung
            step = "Zusammenfassung"
            var summary = Storage.load(Summary.self, from: Storage.summaryURL(id).appendingPathExtension("json"))
            if summary == nil, let client = try LLMFactory.make(settings.ai) {
                setStep(id, .summarizing, summarySpan.lowerBound)
                let summarizer = Summarizer(client: client, chunkCharacters: settings.ai.provider.chunkCharacters,
                                            providerName: settings.ai.provider.label)
                // Automatische Namen („Meeting – 15. Sept., 19:58“) sind kein Kontext – das Modell würde sie nur als Titel übernehmen
                let context = SummaryContext(category: category, titleHint: rec.hasAutoTitle ? "" : rec.title, sourceApp: rec.sourceApp,
                                             date: rec.startedAt, duration: rec.duration,
                                             hasSpeakers: settings.speakerLabels && rec.hasSystemAudio,
                                             language: settings.ai.summaryLanguage)
                let s = try await summarizer.summarize(transcript: text, context: context) { p in
                    Task { @MainActor in self.setProgress(id, p, in: summarySpan) }
                }
                try Task.checkCancellation()
                Storage.save(s, to: Storage.summaryURL(id).appendingPathExtension("json"))
                try? ("# \(s.title)\n\n" + s.markdown).write(to: Storage.summaryURL(id), atomically: true, encoding: .utf8)
                summary = s
            }
            if let summary {
                update(id) { $0.summaryTitle = summary.title; $0.summaryPreview = summary.preview; $0.taskCount = summary.taskCount }
            }

            // 3) Export
            step = "Export"
            setStep(id, .exporting, summarySpan.upperBound)
            var ids = settings.destinations.enabled
            if let c = category, !c.destinationIDs.isEmpty { ids = c.destinationIDs }
            let already = Set((recording(id)?.exports ?? []).filter(\.success).map(\.destinationID))
            let payload = ExportPayload(recording: recording(id) ?? rec, category: category, summary: summary,
                                        transcript: text, settings: settings.destinations)
            var failures: [String] = []
            for destID in ids.sorted() where !already.contains(destID) {
                try Task.checkCancellation()
                guard let dest = Destinations.make(destID), let info = Destinations.info(destID) else { continue }
                var result = ExportResult(destinationID: destID, destinationName: info.name, success: false, message: "")
                do {
                    result.url = try await dest.export(payload)
                    result.success = true
                    result.message = "Exportiert"
                } catch let error as DestinationNotConfigured {
                    // Nicht eingerichtet ist kein Fehler: Die Notizen bleiben fertig, das Ziel wird übersprungen.
                    result.message = error.hint
                    result.skipped = true
                    Log.info("Export \(info.name) übersprungen: \(error.hint)")
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
        } catch let error where Task.isCancelled || error is CancellationError {
            // Gelöscht oder neu eingereiht – der Status wurde dort bereits gesetzt
            Log.info("Verarbeitung abgebrochen: \(rec.title)")
        } catch {
            let msg = "\(step) fehlgeschlagen: \(error.localizedDescription)"
            update(id) { $0.status = .failed; $0.errorMessage = msg }
            Notifier.send("Verarbeitung fehlgeschlagen", "\(rec.title): \(msg)")
            Log.error("Verarbeitung \(id): \(msg)")
        }
    }

    private func transcribe(_ rec: Recording, settings: AppSettings, span: ClosedRange<Double>) async throws -> Transcript {
        let id = rec.id
        setStep(id, .transcribing, span.lowerBound)
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
                    Task { @MainActor in AppState.shared.setProgress(id, p * 0.1, in: span) }
                }
            }.value
            source = out
        }

        let peak = await Task.detached { AudioMixer.peakDecibels(of: source) }.value
        Log.info("Pegel der Aufnahme: \(peak) dB")
        if peak < -50 {
            throw TranscriptionError.unavailable(
                "Die Aufnahme ist stumm (Pegel \(Int(peak)) dB). Prüfe in den Systemeinstellungen, ob \(AppInfo.name) das Mikrofon verwenden darf und das richtige Eingabegerät ausgewählt ist.")
        }

        let language = rec.language
        let offset = envelope == nil ? 0.0 : 0.1
        var segments = try await transcriber.transcribe(audio: source, language: language) { p in
            Task { @MainActor in AppState.shared.setProgress(id, offset + p * (1 - offset), in: span) }
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

    /// Übernimmt eine im Fenster geänderte Notiz (z. B. abgehakte Aufgabe).
    func updateSummaryText(_ id: UUID, markdown: String) {
        guard var summary = summary(id) else { return }
        summary.markdown = markdown
        summary.taskCount = markdown.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") }.count
        Storage.save(summary, to: Storage.summaryURL(id).appendingPathExtension("json"))
        try? ("# \(summary.title)\n\n" + summary.markdown)
            .write(to: Storage.summaryURL(id), atomically: true, encoding: .utf8)
        update(id) { $0.taskCount = summary.taskCount }
    }

    func setCategory(_ id: UUID, _ categoryID: UUID?) { update(id) { $0.categoryID = categoryID } }

    func deleteAudio(_ id: UUID) {
        for url in [Storage.micURL(id), Storage.systemURL(id), Storage.mixURL(id)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func delete(_ id: UUID) {
        if activeRecordingID == id { endRecordingSession() }
        processingQueue.removeAll { $0 == id }
        // Läuft die Verarbeitung gerade, abbrechen – sonst wartet die restliche Warteschlange,
        // bis die gelöschte Aufnahme fertig (oder an fehlenden Dateien gescheitert) ist.
        if processingID == id { processingTask?.cancel() }
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
