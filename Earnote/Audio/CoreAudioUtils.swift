import EarnoteCore
import AVFoundation
import CoreAudio

struct CoreAudioError: LocalizedError {
    let what: String
    let status: OSStatus
    var errorDescription: String? { "\(what) (CoreAudio-Fehler \(status))" }
}

extension AudioObjectID {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    private func address(_ selector: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func read<T>(_ selector: AudioObjectPropertySelector, default value: T,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var addr = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        let status = withUnsafeMutablePointer(to: &result) { ptr in
            AudioObjectGetPropertyData(self, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr else { throw CoreAudioError(what: "Eigenschaft lesen", status: status) }
        return result
    }

    func readString(_ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(self, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    /// Liest eine Eigenschaft, die ein Objekt liefert (z. B. die Beschreibung eines Process-Taps)
    func readObject(_ selector: AudioObjectPropertySelector) -> AnyObject? {
        var addr = address(selector)
        var ref: Unmanaged<AnyObject>?
        var size = UInt32(MemoryLayout<Unmanaged<AnyObject>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(self, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue()
    }

    func readIDs(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBufferPointer { buf in
            AudioObjectGetPropertyData(self, &addr, 0, nil, &size, buf.baseAddress!)
        }
        return status == noErr ? ids : []
    }

    static func defaultOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.systemObject.read(kAudioHardwarePropertyDefaultSystemOutputDevice, default: AudioDeviceID.unknown)
    }
}

extension AVAudioPCMBuffer {
    /// Effektivwert über alle Kanäle (0...1)
    var rms: Float {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        let channels = Int(format.isInterleaved ? 1 : format.channelCount)
        let samplesPerChannel = Int(frameLength) * (format.isInterleaved ? Int(format.channelCount) : 1)
        var sum: Float = 0
        for c in 0..<channels {
            let p = data[c]
            for i in 0..<samplesPerChannel { sum += p[i] * p[i] }
        }
        return (sum / Float(max(1, channels * samplesPerChannel))).squareRoot()
    }
}
