import AVFoundation

/// Liest eine Audiodatei stückweise und liefert 16 kHz Mono (Float32).
final class ResamplingReader {
    static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private var endOfFile = false
    let duration: Double

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: Self.outputFormat) else {
            throw NSError(domain: "Earmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audioformat wird nicht unterstützt"])
        }
        converter.downmix = true
        self.converter = converter
        duration = Double(file.length) / file.processingFormat.sampleRate
    }

    /// Liefert bis zu `frames` Samples, oder nil am Dateiende.
    func read(frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: frames) else { return nil }
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { [weak self] packetCount, inputStatus in
            guard let self, !self.endOfFile,
                  let input = AVAudioPCMBuffer(pcmFormat: self.file.processingFormat, frameCapacity: packetCount)
            else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            do { try self.file.read(into: input, frameCount: packetCount) } catch { input.frameLength = 0 }
            if input.frameLength == 0 {
                self.endOfFile = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error || out.frameLength == 0 { return nil }
        return out
    }
}

/// Lautstärkeverlauf (RMS) in festen Zeitfenstern – für die Sprecher-Zuordnung.
struct EnergyEnvelope: Codable {
    static let window: Double = 0.25
    var mic: [Float]
    var system: [Float]

    /// "Ich", wenn im Zeitraum das Mikrofon dominiert, sonst "Andere".
    func speaker(from start: Double, to end: Double) -> String? {
        guard !system.isEmpty else { return nil }
        let a = max(0, Int(start / Self.window))
        let b = max(a + 1, Int((end / Self.window).rounded(.up)))
        func energy(_ arr: [Float]) -> Float {
            guard a < arr.count else { return 0 }
            let slice = arr[a..<min(b, arr.count)]
            return slice.reduce(0, +) / Float(max(1, slice.count))
        }
        let m = energy(mic), s = energy(system)
        if m < 0.002 && s < 0.002 { return nil }
        return m > s * 1.2 ? "Ich" : "Andere"
    }
}

enum AudioMixer {
    /// Mischt Mikrofon und Systemton zu einer 16-kHz-Mono-WAV und berechnet den Lautstärkeverlauf.
    static func mix(mic: URL, system: URL?, output: URL,
                    progress: @escaping (Double) -> Void) throws -> EnergyEnvelope {
        let micReader = try ResamplingReader(url: mic)
        let sysReader: ResamplingReader? = try system.flatMap { url in
            FileManager.default.fileExists(atPath: url.path) ? try ResamplingReader(url: url) : nil
        }
        let total = max(micReader.duration, sysReader?.duration ?? 0)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        try? FileManager.default.removeItem(at: output)
        let out = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let chunk: AVAudioFrameCount = 16_000   // 1 Sekunde
        let windowFrames = Int(EnergyEnvelope.window * 16_000)
        var envelope = EnergyEnvelope(mic: [], system: [])
        var processed: Double = 0
        var micDone = false, sysDone = sysReader == nil

        while !(micDone && sysDone) {
            let m = micDone ? nil : micReader.read(frames: chunk)
            let s = sysDone ? nil : sysReader?.read(frames: chunk)
            if m == nil { micDone = true }
            if s == nil { sysDone = true }
            let length = Int(max(m?.frameLength ?? 0, s?.frameLength ?? 0))
            if length == 0 { continue }

            guard let mixed = AVAudioPCMBuffer(pcmFormat: ResamplingReader.outputFormat, frameCapacity: AVAudioFrameCount(length)) else { break }
            mixed.frameLength = AVAudioFrameCount(length)
            let dst = mixed.floatChannelData![0]
            let mp = m?.floatChannelData?[0], mLen = Int(m?.frameLength ?? 0)
            let sp = s?.floatChannelData?[0], sLen = Int(s?.frameLength ?? 0)

            var i = 0
            while i < length {
                let end = min(i + windowFrames, length)
                var me: Float = 0, se: Float = 0
                for j in i..<end {
                    let mv: Float = (mp != nil && j < mLen) ? mp![j] : 0
                    let sv: Float = (sp != nil && j < sLen) ? sp![j] : 0
                    me += mv * mv; se += sv * sv
                    dst[j] = max(-1, min(1, mv + sv * 0.9))
                }
                let n = Float(max(1, end - i))
                envelope.mic.append((me / n).squareRoot())
                if sysReader != nil { envelope.system.append((se / n).squareRoot()) }
                i = end
            }
            try out.write(from: mixed)
            processed += Double(length) / 16_000
            if total > 0 { progress(min(1, processed / total)) }
        }
        return envelope
    }

    /// Maximaler Pegel in dBFS (zur Erkennung stummer Aufnahmen).
    static func peakDecibels(of url: URL) -> Float {
        guard let reader = try? ResamplingReader(url: url) else { return -.infinity }
        var peak: Float = 0
        while let buf = reader.read(frames: 64_000), let p = buf.floatChannelData?[0] {
            for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(p[i])) }
        }
        return peak > 0 ? 20 * log10(peak) : -.infinity
    }
}
