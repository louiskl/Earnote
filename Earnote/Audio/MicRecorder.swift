import EarnoteCore
import AVFoundation
import AudioToolbox
import CoreAudio

/// Nimmt ein bestimmtes Mikrofon auf. Verschwindet das Gerät während der Aufnahme (abgezogen, Bluetooth weg)
/// oder wechselt macOS die Konfiguration, läuft die Aufnahme in derselben Datei mit einem Ersatzgerät weiter.
/// Jeder Start und jeder Wechsel nutzt eine frische `AVAudioEngine`, damit kein halb gestarteter Zustand bleibt.
/// Die alte wird dabei nicht sofort freigegeben, sondern über `retire()` (siehe dort).
final class MicRecorder {
    /// Startfehler eines einzelnen Geräts (technische Details nur fürs Protokoll)
    struct StartFailure: Error, CustomStringConvertible {
        let device: AudioInputDeviceInfo
        let underlying: Error
        let format: String
        var description: String {
            let e = underlying as NSError
            return "„\(device.name)“ [\(device.uid)] \(format): \(e.domain) \(e.code) \(e.localizedDescription)"
        }
    }

    /// Führt einen Audio-Aufruf aus, der eine Obj-C-Ausnahme werfen kann (siehe `AudioExceptions.h`),
    /// und macht daraus einen Swift-Fehler – statt die App zu beenden.
    private func withoutCrashing(_ what: String, _ body: () -> Void) throws {
        var raised: NSError?
        guard EarnoteCatchException(body, &raised) else {
            let reason = raised?.localizedDescription ?? "unbekannt"
            Log.error("Audio-Ausnahme bei \(what): \(reason)")
            throw NSError(domain: AppInfo.name, code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "\(what) ist fehlgeschlagen (\(reason))"])
        }
    }

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var converter: FormatConverter?
    private var configObserver: NSObjectProtocol?
    private var aliveListener: (AudioDeviceID, AudioObjectPropertyListenerBlock)?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var tapFormat: AVAudioFormat?
    private let lock = NSLock()
    /// Wann zuletzt ein Puffer ankam. Bleibt das aus, liefert das Mikrofon nichts mehr –
    /// unabhängig davon, was der Pegel noch anzeigt.
    private var _lastBufferAt: Date?
    /// Hinweis auf Telefonqualität nur einmal je Aufnahme
    private var toldAboutQuality = false
    private var _level: Float = 0
    private var _paused = false
    /// Gerät verloren, noch kein Ersatz gefunden – beim nächsten Geräte-Ereignis erneut versuchen
    private var waitingForDevice = false
    /// Geplanter Neustart nach einer Konfigurationsänderung (siehe `scheduleSwitch`)
    private var pendingSwitch: DispatchWorkItem?
    /// Zeitpunkte der letzten Neustarts je Gerät (siehe `isFlapping`)
    private var restarts: [String: [Date]] = [:]

    /// Gerät, über das gerade aufgenommen wird
    private(set) var device: AudioInputDeviceInfo?
    /// Wird zusätzlich mit jedem Mikrofonpuffer aufgerufen (Live-Mitschrift).
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    /// Hinweise an die Nutzerin / den Nutzer (auf dem Hauptthread)
    /// Meldungen ans Fenster. Beim Start steht der Empfänger noch nicht – deshalb werden Hinweise,
    /// die schon beim ersten Start anfallen, gemerkt und nachgereicht, sobald jemand zuhört.
    var onEvent: ((MicrophoneEvent) -> Void)? {
        didSet {
            guard onEvent != nil, !pendingEvents.isEmpty else { return }
            let pending = pendingEvents
            pendingEvents = []
            pending.forEach { onEvent?($0) }
        }
    }
    private var pendingEvents: [MicrophoneEvent] = []

    private func report(_ event: MicrophoneEvent) {
        if let onEvent { onEvent(event) } else { pendingEvents.append(event) }
    }
    /// Ersatzgeräte in Reihenfolge, wenn das laufende Gerät ausfällt (verlorene UID wird übergeben)
    var replacements: ((String) -> [AudioInputDeviceInfo])?

    var level: Float { lock.lock(); defer { lock.unlock() }; return _level }
    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return _paused }
    /// Wann der letzte Puffer ankam (nil: seit dem Start noch keiner)
    var lastBufferAt: Date? { lock.lock(); defer { lock.unlock() }; return _lastBufferAt }

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    #if DEBUG
    deinit { Log.info("Freigegeben: MicRecorder") }
    #endif

    // MARK: Start

    /// Ein Startversuch auf einem Gerät. Legt die Datei beim ersten erfolgreichen Start an;
    /// schlägt der Start fehl, bleibt keine Datei zurück.
    func start(on device: AudioInputDeviceInfo, writingTo url: URL) throws {
        let createsFile = file == nil
        var formatText = "Format unbekannt"
        var created: AVAudioEngine?
        do {
            let engine = try makeEngine(for: device)
            created = engine
            let format = engine.inputNode.outputFormat(forBus: 0)
            formatText = "\(Int(format.sampleRate)) Hz, \(format.channelCount) Kanäle"
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: AppInfo.name, code: 1, userInfo: [NSLocalizedDescriptionKey: "Gerät liefert kein Eingangsformat"])
            }
            if createsFile {
                let newFile = try AVAudioFile(forWriting: url, settings: format.settings,
                                              commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                lock.lock(); file = newFile; lock.unlock()
                fileURL = url
            }
            try run(engine, device: device)
        } catch {
            created?.retire()
            if createsFile {
                lock.lock(); file = nil; converter = nil; lock.unlock()
                try? FileManager.default.removeItem(at: url)
                fileURL = nil
            }
            throw StartFailure(device: device, underlying: error, format: formatText)
        }
    }

    /// Frische Engine, deren Eingang auf das Gerät gesetzt ist
    private func makeEngine(for device: AudioInputDeviceInfo) throws -> AVAudioEngine {
        guard let id = AudioInputDevices.deviceID(forUID: device.uid) else {
            throw NSError(domain: AppInfo.name, code: 2, userInfo: [NSLocalizedDescriptionKey: "Gerät nicht gefunden"])
        }
        let engine = AVAudioEngine()
        guard let unit = engine.inputNode.audioUnit else {
            engine.retire()
            throw NSError(domain: AppInfo.name, code: 3, userInfo: [NSLocalizedDescriptionKey: "Kein Eingang an der Audio-Engine"])
        }
        var deviceID = id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            engine.retire()
            throw CoreAudioError(what: "Gerät an der Audio-Engine setzen", status: status)
        }
        return engine
    }

    /// Tap anbringen, starten und Beobachter für dieses Gerät einrichten
    private func run(_ engine: AVAudioEngine, device: AudioInputDeviceInfo) throws {
        try installTap(on: engine)
        engine.prepare()
        do {
            #if DEBUG
            // Zum Testen: EARNOTE_SIMULATE_MIC_FAILURE=<Teil des Gerätenamens> lässt dieses Gerät nicht starten
            if let broken = ProcessInfo.processInfo.environment["EARNOTE_SIMULATE_MIC_FAILURE"], !broken.isEmpty,
               device.name.localizedCaseInsensitiveContains(broken) {
                throw NSError(domain: "com.apple.coreaudio.avfaudio", code: 35, userInfo: [NSLocalizedDescriptionKey: "Simulierter Startfehler"])
            }
            #endif
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
        self.engine = engine
        self.device = device
        lock.lock(); _lastBufferAt = Date(); lock.unlock()
        waitingForDevice = false
        // Bluetooth-Kopfhörer fallen auf 16 oder 24 kHz, sobald sie gleichzeitig Ton ausgeben (Call).
        // Whisper hört dann deutlich schlechter – einmal je Aufnahme darauf hinweisen.
        let rate = tapFormat?.sampleRate ?? 0
        if [.bluetooth, .bluetoothLE].contains(device.transport), rate > 0, rate < 32_000, !toldAboutQuality {
            toldAboutQuality = true
            Log.info("Mikrofon „\(device.name)“ läuft mit \(Int(rate)) Hz (Telefonmodus)")
            report(.telephoneQuality(name: device.name, kilohertz: Int(rate / 1000)))
        }
        observe(engine, device: device)
    }

    private func installTap(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Zwischen der Prüfung in `start` und hier kann das Gerät wegfallen – abgezogen, von einer
        // anderen App belegt, Bluetooth weg. Dann steht hier 0 Hz, und `installTap` wirft eine
        // Obj-C-Ausnahme, die Swift nicht fangen kann: Die App stürzt ab. Also vorher prüfen und
        // einen normalen Fehler werfen, damit der Weg über das Ersatzgerät greift.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: AppInfo.name, code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Gerät liefert beim Start kein Eingangsformat mehr"])
        }
        // Sicherheitsgurt: Hängt am Eingang noch ein Tap (etwa weil die alte Engine beim Abräumen
        // mitten in einer Umkonfiguration steckte), wirft `installTap` ebenfalls eine Obj-C-Ausnahme.
        input.removeTap(onBus: 0)
        tapFormat = format
        lock.lock()
        converter = file.map { FormatConverter(target: $0.processingFormat) }
        lock.unlock()
        // `format: nil` heißt „nimm das Format, das der Eingang gerade wirklich hat“. Nach einem
        // Gerätewechsel meldet `outputFormat(forBus:)` mitunter noch das alte Gerät; ein Tap mit
        // diesem Format liefert dann stumm gar nichts mehr – genau so ging bei einem Wechsel auf
        // ein anderes Mikrofon der Ton verloren. Die Umwandlung aufs Dateiformat macht ohnehin
        // `FormatConverter`, der sich auf jedes eingehende Format einstellt.
        try withoutCrashing("Tap anbringen") {
            input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                self?.handle(buffer)
            }
        }
    }

    // MARK: Pause, Fortsetzen, Stopp

    /// Hält das Mikrofon wirklich an: Die Aufnahmeanzeige von macOS (oranger Punkt) erlischt,
    /// damit niemand denkt, es werde weiter mitgehört.
    func pause() {
        pendingSwitch?.cancel()
        pendingSwitch = nil
        lock.lock(); _paused = true; _level = 0; lock.unlock()
        engine?.pause()
    }

    /// Setzt fort – mit demselben Gerät, wenn es noch da ist und startet, sonst mit einem Ersatzgerät.
    func resume() throws {
        lock.lock(); _paused = false; lock.unlock()
        if let engine, let device, !waitingForDevice, AudioInputDevices.isAlive(uid: device.uid),
           engine.inputNode.outputFormat(forBus: 0) == tapFormat {
            engine.prepare()
            do {
                try engine.start()
                return
            } catch {
                Log.error("Mikrofon fortsetzen: \(StartFailure(device: device, underlying: error, format: "wie zuvor"))")
            }
        }
        guard switchDevice(reason: "Fortsetzen") else {
            lock.lock(); _paused = true; lock.unlock()
            throw NSError(domain: AppInfo.name, code: 4, userInfo: [NSLocalizedDescriptionKey: String(localized: "Kein Mikrofon hat reagiert")])
        }
    }

    /// Räumt vollständig auf: Beobachter, Tap, Engine, Datei. Auch aus der Pause heraus.
    func stop() {
        toldAboutQuality = false
        pendingSwitch?.cancel()
        pendingSwitch = nil
        teardownEngine()
        waitingForDevice = false
        lock.lock(); file = nil; converter = nil; _level = 0; lock.unlock()
        fileURL = nil
        onAudio = nil
        onEvent = nil
        replacements = nil
    }

    private func teardownEngine() {
        removeObservers()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.retire()
        }
        engine = nil
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let paused = _paused, file = file, converter = converter
        lock.unlock()
        lock.lock(); _lastBufferAt = Date(); lock.unlock()
        guard !paused, let file else { return }
        do {
            if let converted = converter?.convert(buffer) { try file.write(from: converted) }
        } catch {
            Log.error("Mikrofon schreiben: \(error)")
        }
        onAudio?(buffer)
        let level = buffer.rms
        lock.lock(); if !_paused { _level = level }; lock.unlock()
    }

    // MARK: Gerätewechsel während der Aufnahme

    private func observe(_ engine: AVAudioEngine, device: AudioInputDeviceInfo) {
        removeObservers()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.configurationChanged() }

        if let id = AudioInputDevices.deviceID(forUID: device.uid) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.configurationChanged() }
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr { aliveListener = (id, block) }
        }
        observeDeviceList()
    }

    private func observeDeviceList() {
        guard devicesListener == nil else { return }
        var devices = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.devicesChanged() }
        if AudioObjectAddPropertyListenerBlock(.systemObject, &devices, .main, block) == noErr { devicesListener = block }
    }

    private func removeObservers() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let (id, block) = aliveListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        aliveListener = nil
        if let devicesListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(.systemObject, &address, .main, devicesListener)
        }
        devicesListener = nil
    }

    /// Geräteliste geändert: Wartet die Aufnahme auf ein Mikrofon, jetzt erneut versuchen;
    /// ist das laufende Gerät verschwunden, ersetzen.
    private func devicesChanged() {
        guard file != nil else { return }
        if waitingForDevice {
            if !isPaused { scheduleSwitch(reason: "Neues Gerät") }
        } else if let device, !AudioInputDevices.isAlive(uid: device.uid) {
            configurationChanged()
        }
    }

    /// macOS stoppt die Engine, wenn sich das Gerät oder seine Konfiguration ändert. Weitermachen –
    /// mit demselben Gerät, falls es noch da ist, sonst mit einem Ersatz. In der Pause bleibt das Mikrofon aus;
    /// `resume` prüft das Gerät dann erneut.
    private func configurationChanged() {
        guard file != nil, !isPaused, !waitingForDevice else { return }
        scheduleSwitch(reason: "Konfiguration geändert")
    }

    /// Startet die Aufnahme kurz **nach** der Meldung neu, nicht mitten darin – aus zwei Gründen:
    ///
    /// 1. `AVAudioEngineConfigurationChange` verschickt die Engine aus ihrem eigenen Thread und wartet,
    ///    bis alle Beobachter fertig sind; ihre Sperren hält sie dabei. Eine neue Engine von dort aus zu
    ///    starten lässt AVFoundation eine Obj-C-Ausnahme werfen, die Swift nicht fangen kann – die App
    ///    stürzt ab (beobachtet mit AirPods in einem Teams-Call).
    /// 2. Bluetooth-Kopfhörer melden beim Umschalten ihres Profils im Sekundentakt Änderungen. Ohne
    ///    diesen Aufschub startet die Aufnahme dutzende Male neu, und genau dort fehlt dann Ton.
    private func scheduleSwitch(reason: String, after delay: TimeInterval = 0.6) {
        pendingSwitch?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSwitch = nil
            guard self.file != nil, !self.isPaused, !self.waitingForDevice else { return }
            // Hat sich zwischenzeitlich alles beruhigt, bleibt die laufende Aufnahme unangetastet.
            if let engine = self.engine, engine.isRunning, let device = self.device,
               AudioInputDevices.isAlive(uid: device.uid),
               engine.inputNode.outputFormat(forBus: 0) == self.tapFormat {
                return
            }
            _ = self.switchDevice(reason: reason)
        }
        pendingSwitch = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func noteRestart(_ uid: String) {
        let now = Date()
        restarts[uid] = (restarts[uid] ?? []).filter { now.timeIntervalSince($0) < 60 } + [now]
    }

    /// Ein Gerät, das sich innerhalb einer Minute dreimal neu meldet, ist unruhig – typisch für
    /// Bluetooth-Kopfhörer, die in einem Call zwischen ihren Profilen springen. Jeder Neustart kostet
    /// ein bis zwei Sekunden Ton, deshalb weicht die Aufnahme dann lieber auf ein stabiles Mikrofon aus.
    private func isFlapping(_ uid: String) -> Bool {
        let now = Date()
        return (restarts[uid] ?? []).filter { now.timeIntervalSince($0) < 60 }.count >= 3
    }

    /// Startet mit demselben Gerät neu oder weicht aus. Meldet einen Wechsel an `onEvent`.
    /// - Returns: false, wenn kein Gerät startet (die Aufnahme wartet dann auf ein neues Gerät)
    @discardableResult
    private func switchDevice(reason: String) -> Bool {
        guard let url = fileURL else { return false }
        let previous = device
        teardownEngine()

        var candidates: [AudioInputDeviceInfo] = []
        let unsteady = previous.map { isFlapping($0.uid) } ?? false
        if let previous, AudioInputDevices.isAlive(uid: previous.uid), !unsteady { candidates.append(previous) }
        for d in replacements?(previous?.uid ?? "") ?? [] where !candidates.contains(where: { $0.uid == d.uid }) {
            candidates.append(d)
        }
        // Das unruhige Gerät bleibt als letzte Möglichkeit stehen – besser als gar keine Aufnahme.
        if let previous, unsteady, AudioInputDevices.isAlive(uid: previous.uid),
           !candidates.contains(where: { $0.uid == previous.uid }) {
            candidates.append(previous)
        }
        for candidate in candidates {
            do {
                try start(on: candidate, writingTo: url)
                noteRestart(candidate.uid)
                if let previous, candidate.uid != previous.uid, unsteady {
                    Log.info("„\(previous.name)“ meldet sich ständig neu – Aufnahme läuft auf „\(candidate.name)“ weiter")
                    onEvent?(.switchedDuringRecording(lost: previous.name, used: candidate.name))
                } else if let previous, candidate.uid != previous.uid {
                    Log.info("Mikrofon gewechselt (\(reason)): „\(previous.name)“ → „\(candidate.name)“ [\(candidate.uid)], "
                             + "\(Int(tapFormat?.sampleRate ?? 0)) Hz, Aufnahme läuft in derselben Datei weiter")
                    onEvent?(.switchedDuringRecording(lost: previous.name, used: candidate.name))
                } else {
                    Log.info("Mikrofon neu gestartet (\(reason)): „\(candidate.name)“ [\(candidate.uid)]")
                }
                return true
            } catch {
                Log.error("Mikrofon-Wechsel (\(reason)) fehlgeschlagen: \(error)")
            }
        }
        waitingForDevice = true
        observeDeviceList()   // sobald ein Mikrofon auftaucht, geht die Aufnahme weiter
        lock.lock(); _level = 0; lock.unlock()
        Log.error("Mikrofon (\(reason)): kein Ersatzgerät startet, Aufnahme wartet auf ein Mikrofon")
        if let previous { onEvent?(.lostWithoutReplacement(lost: previous.name)) }
        return false
    }
}

extension AVAudioEngine {
    private final class Hold: @unchecked Sendable {
        let engine: AVAudioEngine
        init(_ engine: AVAudioEngine) { self.engine = engine }
    }

    /// Statt die Engine sofort loszulassen: noch ein paar Sekunden festhalten, dann auf dem Main-Thread freigeben.
    /// Ändert sich die Geräteliste (Kopfhörer an/ab), stellt AVFoundation der IO-Unit Meldungen auf ihrer eigenen
    /// Warteschlange zu. Wird die Engine genau dann freigegeben, greift so eine Meldung ins Leere – die App stürzt
    /// ab (beobachtet im Mikrofontest der Einstellungen, 0.9.14). Aufrufen, nachdem die Engine gestoppt ist.
    // ponytail: feste 3 s statt Abwarten der Warteschlange; reicht, solange Meldungen nicht länger hängen.
    func retire() {
        let hold = Hold(self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withExtendedLifetime(hold) {} }
    }
}
