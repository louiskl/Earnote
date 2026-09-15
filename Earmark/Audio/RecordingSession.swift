import AVFoundation

/// Eine laufende Aufnahme: Mikrofon + (optional) Systemton in getrennten Dateien.
final class RecordingSession {
    let recordingID: UUID
    private let mic = MicRecorder()
    private var tap: SystemAudioTap?
    private(set) var systemAudioActive = false

    init(recordingID: UUID) { self.recordingID = recordingID }

    var micLevel: Float { mic.level }
    var systemLevel: Float { tap?.level ?? 0 }

    func start(includeSystemAudio: Bool) throws {
        try mic.start(writingTo: Storage.micURL(recordingID))
        guard includeSystemAudio else { return }
        let tap = SystemAudioTap()
        do {
            try tap.start(writingTo: Storage.systemURL(recordingID))
            self.tap = tap
            systemAudioActive = true
        } catch {
            // Aufnahme läuft trotzdem weiter – nur ohne Systemton
            Log.error("Systemaudio nicht verfügbar: \(error.localizedDescription)")
        }
    }

    func stop() {
        mic.stop()
        tap?.stop()
        tap = nil
    }
}
