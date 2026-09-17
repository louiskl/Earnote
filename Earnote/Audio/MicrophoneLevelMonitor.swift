import AVFoundation
import AudioToolbox
import EarnoteCore
import Observation

/// Pegel eines Mikrofons zum Ausprobieren in den Einstellungen. Nimmt nichts auf und läuft nur,
/// solange jemand hinschaut (und keine Aufnahme läuft).
@MainActor
@Observable
final class MicrophoneLevelMonitor {
    private(set) var level: Float = 0
    /// Das Gerät hat nicht reagiert
    private(set) var failed = false
    private(set) var isRunning = false
    /// Earnote darf das Mikrofon (noch) nicht verwenden
    private(set) var needsPermission = false

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let box = LevelBox()

    private final class LevelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Float = 0
        func set(_ v: Float) { lock.lock(); value = v; lock.unlock() }
        func get() -> Float { lock.lock(); defer { lock.unlock() }; return value }
    }

    func start(device: AudioInputDeviceInfo?) {
        stop()
        // Ohne Erlaubnis liefert macOS nur Stille – dann lieber gar nicht erst starten und es sagen
        needsPermission = MicRecorder.permission != .authorized
        if needsPermission {
            Log.info("Mikrofontest: keine Erlaubnis für das Mikrofon (Status \(MicRecorder.permission.rawValue))")
            return
        }
        guard let device, let id = AudioInputDevices.deviceID(forUID: device.uid) else { failed = device != nil; return }
        let engine = AVAudioEngine()
        var deviceID = id
        if let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { failed = true; return }
        let box = box
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in box.set(buffer.rms) }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            failed = true
            Log.info("Mikrofontest: „\(device.name)“ startet nicht (\((error as NSError).domain) \((error as NSError).code))")
            return
        }
        self.engine = engine
        failed = false
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Dezibel-Skala: −50 dB (Stille) bis 0 dB. So ist normales Sprechen deutlich sichtbar.
                let rms = self.box.get()
                let db = rms > 0 ? 20 * log10(rms) : -100
                self.level = min(1, max(0, (db + 50) / 50))
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isRunning = false
        level = 0
        box.set(0)
    }
}
