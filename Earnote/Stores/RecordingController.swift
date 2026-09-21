import AppKit
import EarnoteCore
import Observation

/// Pegelanzeige – getrennt vom übrigen Zustand, damit nicht die ganze Oberfläche 10× pro Sekunde neu zeichnet.
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

/// Die laufende Aufnahme: Start, Pause, Fortsetzen, Stopp, Abbrechen, Pegel, Live-Mitschrift
/// und die Reaktion auf erkannte Calls.
@MainActor
@Observable
final class RecordingController {
    private(set) var activeRecordingID: UUID?
    private(set) var isPaused = false
    /// Mikrofon, über das die laufende Aufnahme gerade aufnimmt
    private(set) var microphoneName: String?
    /// Läuft der Systemton mit? (für die Anzeige auf der Aufnahme-Bühne)
    private(set) var isCapturingSystemAudio = false
    var lastError: String?

    @ObservationIgnored let meter = LiveMeter()
    @ObservationIgnored let live = LiveTranscript()
    @ObservationIgnored let detector: MeetingDetector
    @ObservationIgnored let audioInputs: AudioInputDevices

    /// Hinweis „Call erkannt“ zeigen bzw. ausblenden (schwebendes Fenster der App)
    @ObservationIgnored var showCallPrompt: (String) -> Void = { _ in }
    @ObservationIgnored var hideCallPrompt: () -> Void = {}

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let transcribers: any TranscriberProvider
    @ObservationIgnored private let notify: (String, String) -> Void
    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var recordingActivity: NSObjectProtocol?
    @ObservationIgnored private var liveTranscriber: AnyObject?
    /// Transkribiert schon während der Aufnahme abschnittsweise mit (siehe `LiveTranscription`)
    @ObservationIgnored private var chunked: LiveTranscription?
    /// Verdichtet das Transkript schon während der Aufnahme (siehe `LiveCondenser`)
    @ObservationIgnored private var condenser: LiveCondenser?
    @ObservationIgnored private let llm: LLMFactory
    @ObservationIgnored private let precondensed: PreCondensedStore
    @ObservationIgnored private var chunkLoop: Task<Void, Never>?
    @ObservationIgnored private var recordingStartedByCall = false
    /// Hinweis „gewähltes Mikrofon nicht verbunden“ nur einmal je Gerät und App-Start
    @ObservationIgnored private var toldAboutMissingMicrophone: Set<String> = []
    /// Seit wann das Mikrofon nichts mehr liefert (für den Hinweis „kein Ton“)
    @ObservationIgnored private var silentSince: Date?
    @ObservationIgnored private var toldAboutSilence = false
    @ObservationIgnored private var lastDiskCheck = Date.distantPast
    @ObservationIgnored private var toldAboutLowSpace = false
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?

    var isRecording: Bool { activeRecordingID != nil }
    var activeRecording: Recording? { activeRecordingID.flatMap(library.recording) }

    init(library: LibraryStore, detector: MeetingDetector, audioInputs: AudioInputDevices,
         transcribers: any TranscriberProvider, llm: LLMFactory = LLMFactory(),
         precondensed: PreCondensedStore = PreCondensedStore(),
         notify: @escaping (String, String) -> Void) {
        self.library = library
        self.detector = detector
        self.audioInputs = audioInputs
        self.transcribers = transcribers
        self.llm = llm
        self.precondensed = precondensed
        self.notify = notify
        detector.onCallStarted = { [weak self] app in self?.callStarted(app) }
        detector.onCallEnded = { [weak self] app in self?.callEnded(app) }
    }

    /// Call-Erkennung passend zur Einstellung ein- oder ausschalten
    func updateDetection(enabled: Bool) {
        if enabled { detector.start() } else { detector.stop() }
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
                    lastError = MicrophoneEvent.permissionDenied.message
                    SystemSettingsLink.microphone()
                    return
                }
            }
            // Zu wenig Platz: Eine Aufnahme, die nach zehn Minuten abbricht, hilft niemandem.
            let space = library.audio.diskSpace
            if case .critical = space {
                lastError = space.message
                return
            }
            let settings = library.settings
            let df = DateFormatter()
            df.locale = Locale(identifier: "de_DE")
            df.dateFormat = "d. MMM, HH:mm"
            let cat = category ?? library.category(settings.defaultCategoryID) ?? library.categories.first
            // Läuft gerade ein Termin, heißt die Aufnahme wie er – das ist der Titel, den man sucht.
            let fromCalendar = settings.calendarTitles ? CalendarTitles.current(in: settings.calendarIDs)?.title : nil
            let name = title.isEmpty
                ? (fromCalendar ?? "\(cat?.name ?? "Aufnahme") – \(df.string(from: Date()))")
                : title
            var rec = Recording(title: name, categoryID: cat?.id, sourceApp: sourceApp)
            rec.language = settings.language
            rec.isTitleCustom = !Recording.looksAutomatic(name)

            audioInputs.refresh()
            let plan = MicrophonePlan.start(devices: audioInputs.devices, preferredUID: settings.microphoneDeviceUID,
                                            defaultUID: audioInputs.defaultUID)
            let session = RecordingSession(recordingID: rec.id, audio: library.audio)
            let notice: MicrophoneEvent?
            do {
                notice = try await session.start(includeSystemAudio: settings.recordSystemAudio, plan: plan,
                                                 preferredName: settings.microphoneDeviceName,
                                                 preferredUID: settings.microphoneDeviceUID)
            } catch {
                // Technische Details stehen bereits im Protokoll; hier nur ein verständlicher nächster Schritt
                session.stop()
                let event = (error as? RecordingSession.MicrophoneUnavailable)?.event ?? .allFailed
                lastError = event.message
                Log.error("Aufnahme konnte nicht starten: \(error)")
                library.audio.deleteFolder(for: rec.id)
                return
            }
            microphoneName = session.microphone?.name
            session.onMicrophoneEvent = { [weak self, weak session] event in
                self?.microphoneName = session?.microphone?.name
                self?.lastError = event.message
                self?.notify("Mikrofon", event.message)
            }
            rec.hasSystemAudio = session.systemAudioActive
            isCapturingSystemAudio = session.systemAudioActive
            library.insert(rec)
            self.session = session
            activeRecordingID = rec.id
            if let notice {
                switch notice {
                case .preferredMissing:
                    let uid = settings.microphoneDeviceUID ?? ""
                    if toldAboutMissingMicrophone.insert(uid).inserted { lastError = notice.message }
                default:
                    lastError = notice.message
                }
            }
            if let error = session.systemAudioError {
                lastError = "Die Aufnahme läuft nur mit Mikrofon. Systemton konnte nicht gestartet werden: \(error) Prüfe die Systemaudio-Berechtigung für \(AppInfo.name) in den Systemeinstellungen."
            }
            if case .low = space { lastError = space.message }
            recordingStartedByCall = byCall
            silentSince = nil
            toldAboutSilence = false
            lastDiskCheck = Date()
            toldAboutLowSpace = false
            startSleepWatch()
            isPaused = false
            pausedAt = nil
            pausedTotal = 0
            recordingActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Aufnahme läuft")
            startMeter(startedAt: rec.startedAt)
            startLiveTranscript(session: session, language: rec.language)
            startChunkedTranscription(for: rec, settings: settings)
            hideCallPrompt()
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
        // Vor dem Aufräumen sichern: Der Rest des Transkripts wird gleich noch fertig gemacht.
        let worker = chunked
        endRecordingSession()
        library.update(id) {
            $0.endedAt = Date()
            $0.pausedDuration = paused > 0 ? paused : nil
            $0.status = worker == nil ? .queued : .transcribing
        }
        Log.info("Aufnahme beendet")
        guard let worker else {
            library.enqueue(id)
            return
        }
        let condenser = self.condenser
        self.condenser = nil
        let precondensed = self.precondensed
        // Während der Aufnahme lief schon fast alles; jetzt fehlt nur noch der letzte Abschnitt.
        Task { @MainActor in
            if let transcript = await worker.finish() {
                await library.saveTranscript(id, transcript)
                Log.info("Transkript war beim Stopp schon fertig (\(transcript.segments.count) Abschnitte)")
                if let condenser, let ready = await condenser.finish(fullText: transcript.formatted(includeSpeakers: false)) {
                    await precondensed.set(ready, for: id)
                    Log.info("Vorverdichtet übergeben: \(ready.notes.count) Zeichen Notizen, \(ready.tail.count) Zeichen Rest")
                }
            }
            library.enqueue(id)
        }
    }

    func cancelRecording() {
        guard let id = activeRecordingID else { return }
        endRecordingSession()
        library.delete(id)
    }

    /// Wird eine Aufnahme gelöscht, während sie noch läuft: Aufnahme beenden.
    func endIfActive(_ id: UUID) {
        if activeRecordingID == id { endRecordingSession() }
    }

    /// Transkribiert den Ton schon während der Aufnahme abschnittsweise, damit nach dem Stopp
    /// nur noch der Rest übrig ist. Schlägt etwas fehl, wird danach einfach normal transkribiert.
    private func startChunkedTranscription(for recording: Recording, settings: AppSettings) {
        chunked = nil
        chunkLoop?.cancel()
        guard settings.transcribeWhileRecording else { return }
        let library = self.library
        let transcribers = self.transcribers
        Task { @MainActor in
            do {
                let transcriber = try await transcribers.makeTranscriber(for: settings)
                let terms = Glossary.forCategory(recording.categoryID, in: library.glossary)
                let worker = LiveTranscription(recordingID: recording.id, hasSystemAudio: recording.hasSystemAudio,
                                               language: recording.language, hints: Glossary.speechHints(terms),
                                               audio: library.audio, transcriber: transcriber)
                guard activeRecordingID == recording.id else { return }
                chunked = worker
                let condenser = makeCondenser(for: recording, settings: settings)
                self.condenser = condenser
                chunkLoop = Task.detached(priority: .utility) {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        guard !Task.isCancelled else { return }
                        await worker.advance()
                        // Verdichten erst nach dem Transkribieren: Der Text von eben zählt schon mit.
                        if let condenser { await condenser.advance(fullText: await worker.textSoFar) }
                    }
                }
                Log.info("Transkribiere schon während der Aufnahme")
            } catch {
                // Kein Modell geladen o. Ä.: Nach der Aufnahme meldet die Warteschlange den Fehler verständlich.
                Log.info("Kein Mitschreiben während der Aufnahme: \(error.localizedDescription)")
            }
        }
    }

    /// Verdichtet das Transkript schon während der Aufnahme – dann ist die Notiz nach dem Stopp
    /// viel schneller fertig. Nur auf Macs mit genug Arbeitsspeicher: Sonst liegen Whisper und das
    /// Sprachmodell gleichzeitig im Speicher und der Mac lagert aus.
    private func makeCondenser(for recording: Recording, settings: AppSettings) -> LiveCondenser? {
        guard DeviceCapabilities.memoryGB >= 15.5 else { return nil }
        guard let client = (try? llm.make(settings.ai)) ?? nil else { return nil }
        let category = library.category(recording.categoryID)
        let context = SummaryContext(category: category, titleHint: recording.hasAutoTitle ? "" : recording.title,
                                     sourceApp: recording.sourceApp, date: recording.startedAt,
                                     duration: recording.duration, hasSpeakers: false,
                                     language: settings.ai.summaryLanguage,
                                     glossary: Glossary.forCategory(recording.categoryID, in: library.glossary),
                                     simpleLanguage: settings.ai.simpleNotes)
        let summarizer = Summarizer(client: client, chunkCharacters: settings.ai.provider.chunkCharacters,
                                    providerName: settings.ai.provider.label)
        // Ein Block sind grob 25 Minuten Vorlesung – kleiner lohnt den Modellstart nicht,
        // größer wäre am Ende wieder zu viel auf einmal.
        return LiveCondenser(summarizer: summarizer, context: context,
                             blockCharacters: min(settings.ai.provider.chunkCharacters, 20_000))
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
        let live = live
        Task {
            do {
                try await transcriber.start(language: language) { settled, volatile in
                    live.settled = settled
                    live.volatile = volatile
                }
                guard let format = transcriber.audioFormat else { return }
                session.startLiveAudio(format: format) { [weak transcriber] buffer in
                    transcriber?.append(buffer)
                }
            } catch {
                live.unavailable = "Live-Mitschrift nicht möglich: \(error.localizedDescription)"
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
        stopSleepWatch()
        stopLiveTranscript()
        chunkLoop?.cancel()
        chunkLoop = nil
        chunked = nil
        condenser = nil
        session?.stop()
        session = nil
        activeRecordingID = nil
        microphoneName = nil
        isCapturingSystemAudio = false
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
                self.watchForSilence(level: s.micLevel, isPaused: s.isPaused)
                self.watchDiskSpace()
            }
        }
    }

    /// Ein echtes Mikrofon rauscht immer ein wenig. Kommt eine Minute lang exakt nichts, stimmt etwas nicht
    /// (Berechtigung entzogen, Gerät stummgeschaltet) – dann lieber früh Bescheid sagen als hinterher.
    private func watchForSilence(level: Float, isPaused: Bool) {
        guard !isPaused else { silentSince = nil; return }
        guard level < 0.0002 else { silentSince = nil; return }
        let since = silentSince ?? Date()
        silentSince = since
        guard !toldAboutSilence, Date().timeIntervalSince(since) > 60 else { return }
        toldAboutSilence = true
        let message = "Seit einer Minute ist nichts zu hören. Prüfe, ob das richtige Mikrofon gewählt ist und "
            + "\(AppInfo.name) es verwenden darf (Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon)."
        lastError = message
        notify("Kein Ton", message)
        Log.error("Aufnahme ohne Pegel seit 60 s")
    }

    /// Läuft die Platte während der Aufnahme voll, wird sauber beendet – das Aufgenommene bleibt erhalten.
    private func watchDiskSpace() {
        guard Date().timeIntervalSince(lastDiskCheck) > 30 else { return }
        lastDiskCheck = Date()
        let space = library.audio.diskSpace
        switch space {
        case .fine:
            return
        case .low:
            if !toldAboutLowSpace, let message = space.message {
                toldAboutLowSpace = true
                lastError = message
                notify("Wenig Speicherplatz", message)
            }
        case .critical:
            let message = "Die Aufnahme wurde beendet, weil der Speicherplatz ausgeht. Das bisher Aufgenommene "
                + "wird ganz normal verarbeitet."
            Log.error("Aufnahme wegen Speicherplatz beendet")
            stopRecording()
            lastError = message
            notify("Speicherplatz voll", message)
        }
    }

    /// Klappt der Mac zu, schläft er – mitten in der Aufnahme. Lieber sauber beenden und verarbeiten,
    /// als eine halb geschriebene Datei zu hinterlassen.
    private func startSleepWatch() {
        guard sleepObserver == nil else { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRecording else { return }
                    Log.info("Mac schläft ein – Aufnahme wird beendet")
                    self.stopRecording()
                    let message = "Der Mac ist eingeschlafen, deshalb wurde die Aufnahme beendet und gespeichert. "
                        + "Lass den Deckel offen, wenn weiter mitgeschrieben werden soll."
                    self.lastError = message
                    self.notify("Aufnahme beendet", message)
                }
            }
    }

    private func stopSleepWatch() {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        meter.mic = 0; meter.system = 0; meter.elapsed = 0
    }

    // MARK: Call-Erkennung

    private func callStarted(_ app: String) {
        guard library.settings.meetingDetection, !isRecording else { return }
        showCallPrompt(app)
    }

    private func callEnded(_ app: String) {
        hideCallPrompt()
        if isRecording, recordingStartedByCall, library.settings.autoStopWhenCallEnds {
            stopRecording()
            notify("Call beendet", "Die Aufnahme aus \(app) wird jetzt verarbeitet.")
        }
    }
}
