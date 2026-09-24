import AVFoundation
import CoreAudio
import EarnoteCore

/// Eine laufende Aufnahme: Mikrofon + (optional) Systemton in getrennten Dateien.
final class RecordingSession {
    /// Kein Mikrofon ließ sich starten
    struct MicrophoneUnavailable: LocalizedError {
        let event: MicrophoneEvent
        var errorDescription: String? { event.message }
    }

    let recordingID: UUID
    private let audio: any AudioStore
    private let mic = MicRecorder()
    private var tap: SystemAudioTap?
    private var liveMixer: LiveAudioMixer?
    private(set) var systemAudioActive = false
    private(set) var systemAudioError: String?

    init(recordingID: UUID, audio: any AudioStore) {
        self.recordingID = recordingID
        self.audio = audio
    }

    #if DEBUG
    deinit { Log.info("Freigegeben: RecordingSession") }
    #endif

    var micLevel: Float { mic.level }
    var systemLevel: Float { tap?.level ?? 0 }
    var isPaused: Bool { mic.isPaused }
    /// Wann zuletzt Ton vom Mikrofon ankam (für den Wächter in `RecordingController`)
    var lastMicBufferAt: Date? { mic.lastBufferAt }
    /// Gerät, über das gerade aufgenommen wird
    var microphone: AudioInputDeviceInfo? { mic.device }

    /// Hinweise zum Mikrofon während der Aufnahme (Gerät gewechselt oder verloren)
    var onMicrophoneEvent: ((MicrophoneEvent) -> Void)? {
        get { mic.onEvent }
        set { mic.onEvent = newValue }
    }

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

    /// Startet das Mikrofon nach Plan: erstes Gerät (mit einem zweiten Versuch), dann Ausweichgeräte.
    /// - Returns: Hinweis für die Nutzerin / den Nutzer, falls nicht das gewünschte Gerät läuft
    func start(includeSystemAudio: Bool, plan: MicrophonePlan.Start, preferredName: String?,
               preferredUID: String?) async throws -> MicrophoneEvent? {
        guard let primary = plan.candidates.first else {
            Log.error("Mikrofon: kein Eingabegerät vorhanden")
            throw MicrophoneUnavailable(event: .noDevices)
        }
        audio.createFolder(for: recordingID)
        let url = audio.micURL(for: recordingID)
        var attempts: [String] = []
        var started: AudioInputDeviceInfo?

        startLoop: for (index, device) in plan.candidates.enumerated() {
            let tries = index == 0 ? 2 : 1
            for attempt in 1...tries {
                do {
                    try mic.start(on: device, writingTo: url)
                    attempts.append("„\(device.name)“ Versuch \(attempt): ok")
                    started = device
                    break startLoop
                } catch {
                    attempts.append("„\(device.name)“ Versuch \(attempt): fehlgeschlagen")
                    Log.error("Mikrofon-Start fehlgeschlagen (Versuch \(attempt)): \(error)")
                    if attempt < tries { try? await Task.sleep(nanoseconds: 400_000_000) }
                }
            }
        }

        guard let started else {
            Log.error("Mikrofon: kein Gerät startet – \(attempts.joined(separator: "; "))")
            throw MicrophoneUnavailable(event: .allFailed)
        }

        let wanted = preferredUID == nil ? "Systemstandard" : "„\(preferredName ?? preferredUID!)“"
        Log.info("Mikrofon: gewählt \(wanted), benutzt „\(started.name)“ [\(started.uid)], "
                 + "\(Int(started.sampleRate)) Hz, \(started.channels) Kanäle – \(attempts.joined(separator: "; "))")

        // Fällt das Gerät später aus: gewähltes Gerät, Systemstandard, dann echte Mikrofone
        mic.replacements = { lost in
            MicrophonePlan.replacement(devices: AudioInputDevices.readInputDevices(), lostUID: lost,
                                       preferredUID: preferredUID, defaultUID: Self.currentDefaultUID())
        }

        if includeSystemAudio {
            let tap = SystemAudioTap()
            do {
                try tap.start(writingTo: audio.systemURL(for: recordingID))
                self.tap = tap
                systemAudioActive = true
            } catch {
                // Aufnahme läuft trotzdem weiter – nur ohne Systemton
                systemAudioError = error.localizedDescription
                Log.error("Systemaudio nicht verfügbar: \(error.localizedDescription)")
            }
        }

        if started.uid != primary.uid { return .fellBack(failed: primary.name, used: started.name) }
        if plan.preferredMissing { return .preferredMissing(preferred: preferredName ?? String(localized: "Gewähltes Mikrofon"), used: started.name) }
        return nil
    }

    private static func currentDefaultUID() -> String? {
        guard let id = try? AudioObjectID.systemObject.read(kAudioHardwarePropertyDefaultInputDevice, default: AudioDeviceID.unknown),
              id != .unknown else { return nil }
        return id.readString(kAudioDevicePropertyDeviceUID)
    }

    /// Räumt in fester Reihenfolge auf: Live-Mitschrift abhängen, Mikrofon (Beobachter, Tap, Engine, Datei),
    /// Systemton (IOProc, Aggregat-Gerät, Process-Tap, Datei), zuletzt den Mischer. Funktioniert auch aus der Pause.
    func stop() {
        mic.onAudio = nil
        tap?.onAudio = nil
        mic.stop()
        tap?.stop()
        tap = nil
        liveMixer = nil
    }
}
