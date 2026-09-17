import CoreAudio
import EarnoteCore
import Foundation
import Observation

/// Die Eingabegeräte des Macs (Core Audio): Liste, Systemstandard und Änderungen
/// (Gerät angesteckt/abgezogen, Standard gewechselt).
@MainActor
@Observable
final class AudioInputDevices {
    private(set) var devices: [AudioInputDeviceInfo] = []
    private(set) var defaultUID: String?

    @ObservationIgnored private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init() {
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(.systemObject, &address, DispatchQueue.main, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    /// Geräte in Anzeige-Reihenfolge (echte Mikrofone zuerst)
    var sorted: [AudioInputDeviceInfo] { MicrophonePlan.sortedForDisplay(devices) }

    var defaultDevice: AudioInputDeviceInfo? { defaultUID.flatMap(device) }

    func device(_ uid: String) -> AudioInputDeviceInfo? { devices.first { $0.uid == uid } }

    func refresh() {
        let current = Self.readInputDevices()
        if current != devices { devices = current }
        let defaultID = (try? AudioObjectID.systemObject.read(kAudioHardwarePropertyDefaultInputDevice, default: AudioDeviceID.unknown)) ?? .unknown
        let uid = defaultID == .unknown ? nil : defaultID.readString(kAudioDevicePropertyDeviceUID)
        if uid != defaultUID { defaultUID = uid }
    }

    // MARK: Core Audio

    /// Alle Geräte mit Eingangskanälen, direkt aus Core Audio gelesen (auch außerhalb des Hauptthreads nutzbar)
    nonisolated static func readInputDevices() -> [AudioInputDeviceInfo] {
        AudioObjectID.systemObject.readIDs(kAudioHardwarePropertyDevices).compactMap { id in
            let channels = inputChannels(of: id)
            guard channels > 0, let uid = id.readString(kAudioDevicePropertyDeviceUID) else { return nil }
            let name = id.readString(kAudioObjectPropertyName) ?? uid
            let transportCode = (try? id.read(kAudioDevicePropertyTransportType, default: UInt32(0))) ?? 0
            let rate = (try? id.read(kAudioDevicePropertyNominalSampleRate, default: Float64(0))) ?? 0
            return AudioInputDeviceInfo(uid: uid, name: name, transport: transport(transportCode), sampleRate: rate, channels: channels)
        }
    }

    /// Geräte-ID zu einer UID (IDs ändern sich, wenn ein Gerät neu angesteckt wird)
    nonisolated static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var qualifier = uid as CFString
        var id = AudioDeviceID.unknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) { ptr in
            AudioObjectGetPropertyData(.systemObject, &address, UInt32(MemoryLayout<CFString>.size), ptr, &size, &id)
        }
        return status == noErr && id != .unknown ? id : nil
    }

    /// Ist das Gerät noch da und benutzbar?
    nonisolated static func isAlive(uid: String) -> Bool {
        guard let id = deviceID(forUID: uid) else { return false }
        return ((try? id.read(kAudioDevicePropertyDeviceIsAlive, default: UInt32(0))) ?? 0) != 0
    }

    private nonisolated static func inputChannels(of id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private nonisolated static func transport(_ code: UInt32) -> AudioInputDeviceInfo.Transport {
        switch code {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth: return .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE: return .bluetoothLE
        case kAudioDeviceTransportTypeVirtual: return .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return .aggregate
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return .continuity
        case kAudioDeviceTransportTypeThunderbolt: return .thunderbolt
        case kAudioDeviceTransportTypeHDMI: return .hdmi
        case kAudioDeviceTransportTypeDisplayPort: return .displayPort
        case kAudioDeviceTransportTypePCI: return .pci
        case kAudioDeviceTransportTypeFireWire: return .fireWire
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        default: return .unknown
        }
    }

    // MARK: Aufräumen nach Absturz

    /// Entfernt Aggregat-Geräte und Process-Taps, die eine frühere, abgestürzte Earnote-Instanz hinterlassen hat.
    /// Earnote legt beides als „privat“ an; solche Objekte sieht nur der erzeugende Prozess, und Core Audio entfernt
    /// sie, wenn der Prozess endet. Diese Suche findet deshalb normalerweise nichts – sie greift nur,
    /// falls doch einmal ein öffentliches Überbleibsel existiert.
    nonisolated static func removeLeftoversFromEarlierRuns() {
        var removed = 0
        for id in AudioObjectID.systemObject.readIDs(kAudioHardwarePropertyDevices) {
            guard let uid = id.readString(kAudioDevicePropertyDeviceUID), uid.hasPrefix(AudioInputDeviceInfo.ownAggregatePrefix) else { continue }
            if AudioHardwareDestroyAggregateDevice(id) == noErr { removed += 1 }
        }
        for tap in AudioObjectID.systemObject.readIDs(kAudioHardwarePropertyTapList) {
            guard let description = tap.readObject(kAudioTapPropertyDescription) as? CATapDescription,
                  description.name.hasPrefix(SystemAudioTap.tapName) else { continue }
            if AudioHardwareDestroyProcessTap(tap) == noErr { removed += 1 }
        }
        if removed > 0 { Log.info("Aufgeräumt: \(removed) zurückgelassene Audio-Objekte einer früheren Sitzung") }
    }
}
