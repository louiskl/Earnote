import AVFoundation

/// Nimmt das Standard-Mikrofon auf. Wechselt das Eingabegerät während der Aufnahme
/// (z. B. AirPods verbunden), läuft die Aufnahme mit dem neuen Gerät in derselben Datei weiter.
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: FormatConverter?
    /// Wird zusätzlich mit jedem Mikrofonpuffer aufgerufen (Live-Mitschrift).
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    private var configObserver: NSObjectProtocol?
    private var tapFormat: AVAudioFormat?
    private let lock = NSLock()
    private var _level: Float = 0
    private var _paused = false
    var level: Float { lock.lock(); defer { lock.unlock() }; return _level }

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return _paused }

    /// Hält das Mikrofon wirklich an: Die Aufnahmeanzeige von macOS (oranger Punkt) erlischt,
    /// damit niemand denkt, es werde weiter mitgehört.
    func pause() {
        lock.lock(); _paused = true; _level = 0; lock.unlock()
        engine.pause()
    }

    func resume() throws {
        lock.lock(); _paused = false; lock.unlock()
        // Wurde währenddessen das Eingabegerät gewechselt, passt das Format nicht mehr zur Datei
        if engine.inputNode.outputFormat(forBus: 0) != tapFormat {
            engine.inputNode.removeTap(onBus: 0)
            installTap()
        }
        engine.prepare()
        try engine.start()
    }

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(writingTo url: URL) throws {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: AppInfo.name, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon gefunden oder kein Zugriff erlaubt."])
        }
        file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        installTap()
        engine.prepare()
        try engine.start()

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restartAfterDeviceChange() }
        Log.info("Mikrofon-Aufnahme gestartet (\(format.sampleRate) Hz)")
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); file = nil; converter = nil; lock.unlock()
    }

    private func installTap() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        tapFormat = format
        lock.lock()
        converter = file.map { FormatConverter(target: $0.processingFormat) }
        lock.unlock()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let paused = _paused, file = file, converter = converter
        lock.unlock()
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

    /// macOS stoppt die Engine, wenn sich das Eingabegerät ändert. Mit dem neuen Gerät weitermachen.
    private func restartAfterDeviceChange() {
        guard file != nil, !isPaused else { return }   // in der Pause bleibt das Mikrofon aus
        engine.inputNode.removeTap(onBus: 0)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.error("Mikrofon nach Gerätewechsel nicht verfügbar")
            return
        }
        installTap()
        engine.prepare()
        do {
            try engine.start()
            Log.info("Mikrofon gewechselt, Aufnahme läuft weiter (\(format.sampleRate) Hz)")
        } catch {
            Log.error("Mikrofon nach Gerätewechsel nicht neu gestartet: \(error.localizedDescription)")
        }
    }
}
