import EarnoteCore
import AVFoundation
import CoreAudio

/// Nimmt den gesamten Systemton (Zoom, Teams, Browser …) auf – ohne virtuelles Audiogerät.
/// Nutzt Core Audio Process Taps (macOS 14.2+). Beim ersten Start fragt macOS nach der
/// Berechtigung "Systemaudio aufnehmen".
final class SystemAudioTap {
    /// Name des Process-Taps – daran erkennt der Start der App Überbleibsel früherer Sitzungen
    static let tapName = "\(AppInfo.name) Systemaudio"

    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).systemtap", qos: .userInitiated)
    private let lock = NSLock()
    private var _level: Float = 0
    private var _paused = false
    private(set) var framesWritten: Int64 = 0

    var level: Float { lock.lock(); defer { lock.unlock() }; return _level }

    /// Wird zusätzlich mit jedem Systemton-Puffer aufgerufen (Live-Mitschrift).
    var onAudio: ((AVAudioPCMBuffer) -> Void)?

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return _paused }

    /// Hält auch die Systemton-Aufnahme an, damit die Aufnahmeanzeige von macOS erlischt.
    func setPaused(_ paused: Bool) {
        lock.lock(); _paused = paused; if paused { _level = 0 }; lock.unlock()
        guard aggregateID != .unknown, let procID else { return }
        if paused { AudioDeviceStop(aggregateID, procID) } else { AudioDeviceStart(aggregateID, procID) }
    }

    func start(writingTo url: URL?) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.name = Self.tapName

        var newTap: AudioObjectID = .unknown
        var status = AudioHardwareCreateProcessTap(description, &newTap)
        guard status == noErr else { throw CoreAudioError(what: "Systemaudio-Tap konnte nicht erstellt werden", status: status) }
        tapID = newTap

        let outputID = try AudioObjectID.defaultOutputDevice()
        guard let outputUID = outputID.readString(kAudioDevicePropertyDeviceUID) else {
            stop(); throw CoreAudioError(what: "Ausgabegerät nicht gefunden", status: -1)
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "\(AppInfo.name) Systemaudio",
            kAudioAggregateDeviceUIDKey: "\(AppInfo.bundleIdentifier).aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var newAggregate: AudioObjectID = .unknown
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate)
        guard status == noErr else { stop(); throw CoreAudioError(what: "Aggregat-Gerät konnte nicht erstellt werden", status: status) }
        aggregateID = newAggregate

        var asbd = try tapID.read(kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            stop(); throw CoreAudioError(what: "Unbekanntes Audioformat", status: -1)
        }

        if let url {
            file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        }
        framesWritten = 0

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inInputData, _, _, _ in
            guard let self, !self.isPaused,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil)
            else { return }
            if let file = self.file {
                do { try file.write(from: buffer); self.framesWritten += Int64(buffer.frameLength) }
                catch { Log.error("Systemaudio schreiben: \(error)") }
            }
            self.onAudio?(buffer)
            let level = buffer.rms
            self.lock.lock(); if !self._paused { self._level = level }; self.lock.unlock()
        }
        guard status == noErr else { stop(); throw CoreAudioError(what: "Audio-Callback konnte nicht erstellt werden", status: status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { stop(); throw CoreAudioError(what: "Systemaudio konnte nicht gestartet werden", status: status) }
        Log.info("Systemaudio-Aufnahme gestartet (\(format.sampleRate) Hz, \(format.channelCount) Kanäle)")
    }

    /// Reihenfolge: Callback anhalten und entfernen, dann Aggregat-Gerät, dann Process-Tap, zuletzt die Datei schließen.
    func stop() {
        onAudio = nil
        if aggregateID != .unknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != .unknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = .unknown
        tapID = .unknown
        queue.sync { file = nil }
        lock.lock(); _level = 0; lock.unlock()
    }

    deinit {
        stop()
        #if DEBUG
        Log.info("Freigegeben: SystemAudioTap")
        #endif
    }

    /// Startet kurz einen Tap, damit macOS die Berechtigungsabfrage anzeigt.
    static func requestPermission() async {
        let tap = SystemAudioTap()
        do {
            try tap.start(writingTo: nil)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } catch {
            Log.error("Systemaudio-Berechtigung: \(error.localizedDescription)")
        }
        tap.stop()
    }
}
