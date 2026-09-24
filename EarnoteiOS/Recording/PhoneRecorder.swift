import AVFoundation
import EarnoteCore
import Observation

/// Aufnahme am iPhone: läuft mit ausgeschaltetem Bildschirm weiter (Hintergrund-Audio), pausiert bei Anrufen
/// und setzt danach fort, wechselt bei AirPods & Co. in derselben Datei weiter.
@MainActor
@Observable
final class PhoneRecorder {
    private(set) var activeID: UUID?
    private(set) var startedAt: Date?
    private(set) var isPaused = false
    /// Pausiert durch einen Anruf, Wecker o. ä. (nicht vom Nutzer)
    private(set) var isInterrupted = false
    var lastError: String?

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var sink: AudioSink?
    @ObservationIgnored private var pauseStarted: Date?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    /// Nach dem Stopp (die Aufnahme ist eingereiht) – z. B. Hintergrund-Verarbeitung anstoßen
    @ObservationIgnored var onStop: (UUID) -> Void = { _ in }
    /// Was nach dem Stopp mit der Aufnahme geschieht (Weg B: an den Mac übergeben). Ohne: hier verarbeiten.
    @ObservationIgnored var finish: ((UUID) -> Void)?
    /// Beginn, Pause, Ende – für die Live-Aktivität
    @ObservationIgnored var onChange: () -> Void = {}

    init(library: LibraryStore) {
        self.library = library
    }

    var isRecording: Bool { activeID != nil }
    /// Pegel 0…1 – wird von der Anzeige abgefragt, nicht beobachtet (sonst zeichnete alles 20× pro Sekunde neu)
    var level: Float { sink?.level ?? 0 }
    var categoryName: String? { activeID.flatMap { library.recording($0) }.flatMap { library.category($0.categoryID)?.name } }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        let pausing = pauseStarted.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pausedTotal - pausing)
    }

    // MARK: Starten und Stoppen

    func start(category: RecordingCategory?) async {
        guard activeID == nil else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = String(localized: "Earnote darf das Mikrofon nicht verwenden. Erlaube es in den Einstellungen unter Datenschutz › Mikrofon.")
            return
        }
        let space = library.audio.diskSpace
        if case .critical = space {
            lastError = space.message
            return
        }
        let settings = library.settings
        let cat = category ?? library.category(settings.defaultCategoryID)
        let df = DateFormatter()
        df.locale = .current
        df.setLocalizedDateFormatFromTemplate("dMMMHHmm")
        var rec = Recording(title: "\(cat?.name ?? String(localized: "Aufnahme")) – \(df.string(from: Date()))", categoryID: cat?.id)
        rec.language = settings.language
        rec.isTitleCustom = false

        do {
            try Self.activateSession()
            library.audio.createFolder(for: rec.id)
            let sink = try AudioSink(url: library.audio.micURL(for: rec.id))
            self.sink = sink
            try startEngine()
        } catch {
            Log.error("Aufnahme starten: \(error)")
            sink = nil
            library.audio.deleteFolder(for: rec.id)
            lastError = String(localized: "Die Aufnahme konnte nicht starten: \(error.localizedDescription)")
            return
        }
        library.insert(rec)
        activeID = rec.id
        startedAt = rec.startedAt
        pausedTotal = 0
        observeSession()
        watch()
        Log.info("Aufnahme gestartet (iPhone)")
        onChange()
    }

    func stop() {
        guard let id = activeID else { return }
        if isPaused { setPaused(false, keepEngineStopped: true) }
        let paused = pausedTotal
        tearDown()
        library.update(id) {
            $0.endedAt = Date()
            $0.pausedDuration = paused > 0 ? paused : nil
            $0.status = .queued
        }
        if let finish { finish(id) } else { library.enqueue(id) }
        Log.info("Aufnahme beendet (iPhone)")
        onChange()
        onStop(id)
    }

    func togglePause() {
        guard isRecording else { return }
        setPaused(!isPaused)
    }

    private func setPaused(_ paused: Bool, keepEngineStopped: Bool = false) {
        guard paused != isPaused else { return }
        isPaused = paused
        sink?.isPaused = paused
        if paused {
            pauseStarted = Date()
            engine?.pause()
        } else {
            if let pauseStarted { pausedTotal += Date().timeIntervalSince(pauseStarted) }
            pauseStarted = nil
            isInterrupted = false
            if !keepEngineStopped { restartEngine() }
        }
        onChange()
    }

    private func tearDown() {
        watchdog?.cancel()
        watchdog = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        sink = nil   // schließt die Datei
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        activeID = nil
        startedAt = nil
        isPaused = false
        isInterrupted = false
        pauseStarted = nil
    }

    // MARK: Engine

    private static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        // playAndRecord: AirPods-Mikrofon nutzbar und späteres Abspielen ohne Kategoriewechsel
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
    }

    private func startEngine() throws {
        guard let sink else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: AppInfo.name, code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Kein Mikrofon gefunden")])
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tap(into: sink))
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Außerhalb des MainActors gebaut: Der Block läuft auf dem Audio-Thread.
    nonisolated private static func tap(into sink: AudioSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.write(buffer) }
    }

    /// Nach Anruf, Gerätewechsel oder Pause: frische Engine, gleiche Datei
    private func restartEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        do {
            try Self.activateSession()
            try startEngine()
        } catch {
            Log.error("Aufnahme fortsetzen: \(error)")
            isPaused = true
            pauseStarted = pauseStarted ?? Date()
            lastError = String(localized: "Die Aufnahme konnte nicht fortgesetzt werden: \(error.localizedDescription)\nPrüfe das Mikrofon und versuche es erneut, oder stoppe die Aufnahme.")
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.interrupted(type, shouldResume: options.contains(.shouldResume)) }
        })
        // AirPods rein oder raus: iOS stoppt die Engine – mit dem neuen Gerät in derselben Datei weiter
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording, !self.isPaused else { return }
                Log.info("Audio-Gerät gewechselt, Aufnahme läuft weiter")
                self.restartEngine()
            }
        })
    }

    private func interrupted(_ type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        guard isRecording else { return }
        switch type {
        case .began:
            guard !isPaused else { return }
            setPaused(true)
            isInterrupted = true
            Log.info("Aufnahme unterbrochen (Anruf o. ä.)")
        case .ended:
            if isInterrupted && shouldResume {
                setPaused(false)
                Log.info("Aufnahme nach Unterbrechung fortgesetzt")
            } else if isInterrupted {
                Notifier.send(String(localized: "Aufnahme pausiert"),
                              String(localized: "Tippe auf Fortsetzen, um weiter aufzunehmen."))
            }
        default:
            break
        }
    }

    /// Stille, fehlender Ton, voller Speicher – wie am Mac, nur seltener geprüft
    private func watch() {
        watchdog = Task { [weak self] in
            var silentSince: Date?
            var toldSilence = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isRecording, !self.isPaused, let sink = self.sink else { continue }
                if case .critical = self.library.audio.diskSpace {
                    self.lastError = String(localized: "Die Aufnahme wurde beendet, weil der Speicherplatz ausgeht. Das bisher Aufgenommene wird ganz normal verarbeitet.")
                    Notifier.send(String(localized: "Speicherplatz voll"), self.lastError ?? "")
                    self.stop()
                    return
                }
                if sink.peakSinceLastCheck() < 0.0005 {
                    silentSince = silentSince ?? Date()
                    if !toldSilence, let since = silentSince, Date().timeIntervalSince(since) > 60 {
                        toldSilence = true
                        let message = String(localized: "Seit einer Minute ist nichts zu hören. Prüfe, ob das richtige Mikrofon gewählt ist und \(AppInfo.name) es verwenden darf (Einstellungen › Datenschutz & Sicherheit › Mikrofon).")
                        self.lastError = message
                        Notifier.send(String(localized: "Kein Ton"), message)
                    }
                } else {
                    silentSince = nil
                }
            }
        }
    }
}

/// Schreibt auf dem Audio-Thread in die Datei: wandelt jedes Eingangsformat (eingebautes Mikrofon, AirPods mit
/// 16/24 kHz) in 24 kHz Mono um. PCM statt AAC: Eine CAF mit PCM bleibt auch nach einem Absturz lesbar.
// ponytail: ~170 MB pro Stunde; für die Übergabe an den Mac (Weg B) wird vorher komprimiert
final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private var _level: Float = 0
    private var _peak: Float = 0
    private var _paused = false

    init(url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24_000, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    var level: Float { lock.withLock { _level } }
    var isPaused: Bool {
        get { lock.withLock { _paused } }
        set { lock.withLock { _paused = newValue } }
    }

    /// Lautester Wert seit dem letzten Aufruf
    func peakSinceLastCheck() -> Float {
        lock.withLock { defer { _peak = 0 }; return _peak }
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        let rms = Self.rms(buffer)
        _level = min(1, rms * 8)
        _peak = max(_peak, rms)
        guard !_paused, let file else { return }
        if converterInput != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterInput = buffer.format
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 256
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        // Der Konverter fragt so lange nach Eingabe, bis er „keine Daten“ hört – genau einen Puffer liefern
        let source = PendingBuffer(buffer)
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            guard let next = source.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return next
        }
        if out.frameLength > 0 {
            do { try file.write(from: out) } catch { Log.error("Audio schreiben: \(error)") }
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }
}

/// Übergibt dem Konverter einen Puffer genau einmal
private final class PendingBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
