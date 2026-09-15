import AVFoundation

/// Nimmt das Standard-Mikrofon auf.
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var _level: Float = 0
    var level: Float { lock.lock(); defer { lock.unlock() }; return _level }

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(writingTo url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Earmark", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon gefunden oder kein Zugriff erlaubt."])
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        self.file = file
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            do { try self.file?.write(from: buffer) } catch { Log.error("Mikrofon schreiben: \(error)") }
            let level = buffer.rms
            self.lock.lock(); self._level = level; self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
        Log.info("Mikrofon-Aufnahme gestartet (\(format.sampleRate) Hz)")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
    }
}
