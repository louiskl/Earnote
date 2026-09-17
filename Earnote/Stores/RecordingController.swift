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
    var lastError: String?

    @ObservationIgnored let meter = LiveMeter()
    @ObservationIgnored let live = LiveTranscript()
    @ObservationIgnored let detector: MeetingDetector
    @ObservationIgnored let audioInputs: AudioInputDevices

    /// Hinweis „Call erkannt“ zeigen bzw. ausblenden (schwebendes Fenster der App)
    @ObservationIgnored var showCallPrompt: (String) -> Void = { _ in }
    @ObservationIgnored var hideCallPrompt: () -> Void = {}

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let notify: (String, String) -> Void
    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var recordingActivity: NSObjectProtocol?
    @ObservationIgnored private var liveTranscriber: AnyObject?
    @ObservationIgnored private var recordingStartedByCall = false
    /// Hinweis „gewähltes Mikrofon nicht verbunden“ nur einmal je Gerät und App-Start
    @ObservationIgnored private var toldAboutMissingMicrophone: Set<String> = []

    var isRecording: Bool { activeRecordingID != nil }
    var activeRecording: Recording? { activeRecordingID.flatMap(library.recording) }

    init(library: LibraryStore, detector: MeetingDetector, audioInputs: AudioInputDevices,
         notify: @escaping (String, String) -> Void) {
        self.library = library
        self.detector = detector
        self.audioInputs = audioInputs
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
            let settings = library.settings
            let df = DateFormatter()
            df.locale = Locale(identifier: "de_DE")
            df.dateFormat = "d. MMM, HH:mm"
            let cat = category ?? library.category(settings.defaultCategoryID) ?? library.categories.first
            let name = title.isEmpty ? "\(cat?.name ?? "Aufnahme") – \(df.string(from: Date()))" : title
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
            session.onMicrophoneEvent = { [weak self] event in
                self?.lastError = event.message
                self?.notify("Mikrofon", event.message)
            }
            rec.hasSystemAudio = session.systemAudioActive
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
            recordingStartedByCall = byCall
            isPaused = false
            pausedAt = nil
            pausedTotal = 0
            recordingActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Aufnahme läuft")
            startMeter(startedAt: rec.startedAt)
            startLiveTranscript(session: session, language: rec.language)
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
        endRecordingSession()
        library.update(id) {
            $0.endedAt = Date()
            $0.pausedDuration = paused > 0 ? paused : nil
            $0.status = .queued
        }
        Log.info("Aufnahme beendet")
        library.enqueue(id)
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
