import EarnoteCore
import AVFoundation

/// Mischt Mikrofon und Systemton während der Aufnahme in Echtzeit zusammen – für die Live-Mitschrift.
///
/// Beide Quellen laufen auf eigenen Uhren. Das Mikrofon gibt hier den Takt vor: Systemton wird
/// kurz zwischengespeichert und in gleicher Länge dazugemischt. Für die Anzeige reicht das;
/// das endgültige Transkript entsteht später sample-genau aus den Dateien.
final class LiveAudioMixer: @unchecked Sendable {
    /// Intern wird in Float32 gemischt und erst am Ende in das Format der Spracherkennung gewandelt
    /// (die erwartet je nach System z. B. Int16).
    private let workFormat: AVAudioFormat
    private let micConverter: FormatConverter
    private let systemConverter: FormatConverter
    private let outputConverter: FormatConverter
    private let lock = NSLock()
    private var pending: [Float] = []
    private let maxPending: Int

    /// Wird mit dem fertig gemischten Puffer im Zielformat aufgerufen.
    var onMixed: ((AVAudioPCMBuffer) -> Void)?

    init(format: AVAudioFormat) {
        workFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                                   channels: 1, interleaved: false) ?? format
        micConverter = FormatConverter(target: workFormat)
        systemConverter = FormatConverter(target: workFormat)
        outputConverter = FormatConverter(target: format)
        maxPending = Int(format.sampleRate * 2)   // höchstens 2 Sekunden Rückstand
    }

    func addSystem(_ buffer: AVAudioPCMBuffer) {
        guard let converted = systemConverter.convert(buffer), let p = converted.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: p, count: Int(converted.frameLength)))
        lock.lock()
        pending.append(contentsOf: samples)
        if pending.count > maxPending { pending.removeFirst(pending.count - maxPending) }
        lock.unlock()
    }

    func addMic(_ buffer: AVAudioPCMBuffer) {
        guard let mixed = micConverter.convert(buffer), let dst = mixed.floatChannelData?[0] else { return }
        let count = Int(mixed.frameLength)

        lock.lock()
        let take = min(count, pending.count)
        let system = take > 0 ? Array(pending.prefix(take)) : []
        if take > 0 { pending.removeFirst(take) }
        lock.unlock()

        // Der Eingangspuffer darf nicht überschrieben werden, falls nichts gewandelt wurde
        guard let out = AVAudioPCMBuffer(pcmFormat: workFormat, frameCapacity: mixed.frameCapacity),
              let outData = out.floatChannelData?[0] else { return }
        out.frameLength = mixed.frameLength
        for i in 0..<count {
            let s = i < system.count ? system[i] : 0
            outData[i] = max(-1, min(1, dst[i] + s * 0.9))
        }
        if let converted = outputConverter.convert(out) { onMixed?(converted) }
    }
}
