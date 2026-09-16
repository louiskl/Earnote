import AVFoundation

/// Wandelt Audiopuffer fortlaufend in ein Zielformat um (andere Abtastrate oder Kanalzahl).
/// Der Wandler behält seinen Zustand, damit bei Abtastratenwechseln nichts knackst.
public final class FormatConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var source: AVAudioFormat?

    public init(target: AVAudioFormat) { self.target = target }

    /// Gibt den Puffer im Zielformat zurück – oder den unveränderten Puffer, wenn er schon passt.
    public func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        if buffer.format == target { return buffer }
        if source != buffer.format {
            source = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var used = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if used { status.pointee = .noDataNow; return nil }
            used = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            Log.error("Audio umwandeln: \(error.localizedDescription)")
            return nil
        }
        return out.frameLength > 0 ? out : nil
    }
}
