import AVFoundation

/// Eine laufende Aufnahme: Mikrofon + (optional) Systemton in getrennten Dateien.
final class RecordingSession {
    let recordingID: UUID
    private let mic = MicRecorder()
    private var tap: SystemAudioTap?
    private(set) var systemAudioActive = false
    private(set) var systemAudioError: String?

    init(recordingID: UUID) { self.recordingID = recordingID }

    var micLevel: Float { mic.level }
    var systemLevel: Float { tap?.level ?? 0 }

    var isPaused: Bool { mic.isPaused }
    private var liveMixer: LiveAudioMixer?

    /// Hängt die Live-Mitschrift ein: Mikrofon und Systemton werden in Echtzeit gemischt weitergereicht.
    func startLiveAudio(format: AVAudioFormat, onMixed: @escaping (AVAudioPCMBuffer) -> Void) {
        let mixer = LiveAudioMixer(format: format)
        mixer.onMixed = onMixed
        liveMixer = mixer
        mic.onAudio = { [weak mixer] in mixer?.addMic($0) }
        tap?.onAudio = { [weak mixer] in mixer?.addSystem($0) }
    }

    /// Beide Quellen werden gemeinsam pausiert, damit sie beim Mischen synchron bleiben.
    func setPaused(_ paused: Bool) throws {
        if paused {
            mic.pause()
        } else {
            try mic.resume()
        }
        tap?.setPaused(paused)
    }

    func start(includeSystemAudio: Bool) throws {
        Storage.createFolder(for: recordingID)
        try mic.start(writingTo: Storage.micURL(recordingID))
        guard includeSystemAudio else { return }
        let tap = SystemAudioTap()
        do {
            try tap.start(writingTo: Storage.systemURL(recordingID))
            self.tap = tap
            systemAudioActive = true
        } catch {
            // Aufnahme läuft trotzdem weiter – nur ohne Systemton
            systemAudioError = error.localizedDescription
            Log.error("Systemaudio nicht verfügbar: \(error.localizedDescription)")
        }
    }

    func stop() {
        mic.onAudio = nil
        tap?.onAudio = nil
        liveMixer = nil
        mic.stop()
        tap?.stop()
        tap = nil
    }
}
