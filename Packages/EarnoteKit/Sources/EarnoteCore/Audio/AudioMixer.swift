import AVFoundation

/// Liest eine Audiodatei stückweise und liefert 16 kHz Mono (Float32).
public final class ResamplingReader {
    public static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private var endOfFile = false
    public let duration: Double

    public init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: Self.outputFormat) else {
            throw NSError(domain: AppInfo.name, code: 2, userInfo: [NSLocalizedDescriptionKey: t("Audioformat wird nicht unterstützt")])
        }
        converter.downmix = true
        self.converter = converter
        duration = Double(file.length) / file.processingFormat.sampleRate
    }

    /// Springt an eine Stelle der Datei (in Sekunden). Danach liest `read` von dort weiter.
    public func seek(toSeconds seconds: Double) {
        let position = AVAudioFramePosition(max(0, seconds) * file.processingFormat.sampleRate)
        guard position < file.length else { endOfFile = true; return }
        file.framePosition = position
        endOfFile = false
        converter.reset()
    }

    /// Liefert bis zu `frames` Samples, oder nil am Dateiende.
    public func read(frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: frames) else { return nil }
        var error: NSError?
        // Der Block läuft synchron innerhalb von `convert` und wird danach nicht aufbewahrt
        nonisolated(unsafe) let reader = self
        let status = converter.convert(to: out, error: &error) { packetCount, inputStatus in
            guard !reader.endOfFile,
                  let input = AVAudioPCMBuffer(pcmFormat: reader.file.processingFormat, frameCapacity: packetCount)
            else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            do { try reader.file.read(into: input, frameCount: packetCount) } catch { input.frameLength = 0 }
            if input.frameLength == 0 {
                reader.endOfFile = true
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
public struct EnergyEnvelope: Codable, Sendable {
    public static let window: Double = 0.25
    /// Ab wie viel Übersprechen von Lautsprechern statt Kopfhörern ausgegangen wird
    public static let speakerThreshold: Float = 0.15
    /// Wie viel lauter als das erwartete Übersprechen das Mikrofon sein muss, damit es als eigene Stimme zählt
    public static let ownVoiceFactor: Float = 2.5
    public static let silence: Float = 0.002

    public var mic: [Float]
    public var system: [Float]
    /// Wie stark das Mikrofon den Systemton mithört: 0 mit Kopfhörern, deutlich über 1 bei lauten Lautsprechern.
    public var bleed: Float = 0

    public init(mic: [Float], system: [Float]) {
        self.mic = mic
        self.system = system
        self.bleed = Self.estimateBleed(mic: mic, system: system)
    }

    /// Typisches Verhältnis Mikrofon zu Systemton in Momenten, in denen der Systemton spielt.
    /// Der Median ist robust: Redet die aufnehmende Person zwischendurch mit, verzerrt das das Ergebnis nicht.
    private static func estimateBleed(mic: [Float], system: [Float]) -> Float {
        var ratios = zip(mic, system).filter { $0.1 > 0.01 }.map { $0.0 / $0.1 }
        guard ratios.count >= 8 else { return 0 }
        ratios.sort()
        return ratios[ratios.count / 2]
    }

    /// Anteil der Zeit, in der überhaupt etwas zu hören ist (0…1) – grobe Sprach-Erkennung vor der Transkription.
    /// Ist er praktisch null, war die Aufnahme stumm und Whisper würde nur Sätze erfinden.
    public var loudShare: Double {
        let windows = max(mic.count, system.count)
        guard windows > 0 else { return 1 }
        let loud = (0..<windows).filter { i in
            let m = i < mic.count ? mic[i] : 0
            let s = i < system.count ? system[i] : 0
            return max(m, s) > Self.silence * 3
        }.count
        return Double(loud) / Double(windows)
    }

    /// Anteil der Zeit, in dem die jeweilige Spur etwas aufgenommen hat
    public var micLoudShare: Double { share(of: mic) }
    public var systemLoudShare: Double { share(of: system) }

    private func share(of track: [Float]) -> Double {
        guard !track.isEmpty else { return 0 }
        return Double(track.filter { $0 > Self.silence * 3 }.count) / Double(track.count)
    }

    /// Lohnt sich „Ich“ und „Andere“ überhaupt? Nur, wenn auf beiden Spuren nennenswert etwas passiert.
    /// In einer Vorlesung ohne Call kommt alles aus dem Mikrofon – dann wäre jede Zuordnung geraten.
    public var hasTwoSources: Bool { micLoudShare > 0.05 && systemLoudShare > 0.05 }

    /// Lauter Systemton lässt das Mikrofon mithören. Nur was deutlich darüber liegt, ist die eigene Stimme.
    public func isOwnVoice(mic m: Float, system s: Float) -> Bool {
        m > max(Self.silence * 2, bleed * s * Self.ownVoiceFactor)
    }

    /// "Ich", wenn im Zeitraum die eigene Stimme zu hören ist, sonst "Andere".
    public func speaker(from start: Double, to end: Double) -> String? {
        guard !system.isEmpty else { return nil }
        let a = max(0, Int(start / Self.window))
        let b = max(a + 1, Int((end / Self.window).rounded(.up)))
        func energy(_ arr: [Float]) -> Float {
            guard a < arr.count else { return 0 }
            let slice = arr[a..<min(b, arr.count)]
            return slice.reduce(0, +) / Float(max(1, slice.count))
        }
        let m = energy(mic), s = energy(system)
        if m < Self.silence && s < Self.silence { return nil }
        return isOwnVoice(mic: m, system: s) ? "Ich" : "Andere"
    }
}

public enum AudioMixer {
    private static let sampleRate = 16_000
    private static var windowFrames: AVAudioFrameCount { AVAudioFrameCount(EnergyEnvelope.window * Double(sampleRate)) }

    /// Mischt Mikrofon und Systemton zu einer 16-kHz-Mono-WAV und liefert den Lautstärkeverlauf.
    /// Erst wird gemessen, dann gemischt: Nur so ist vorher bekannt, wie stark das Mikrofon
    /// die Lautsprecher mithört – und dieser Anteil kann beim Mischen leise gedreht werden.
    public static func mix(mic: URL, system: URL?, output: URL,
                           progress: @escaping (Double) -> Void) throws -> EnergyEnvelope {
        try mix(mic: mic, system: system, output: output, from: 0, to: nil, progress: progress)
    }

    /// Mischt nur den Ausschnitt `from ..< to` (Sekunden; `to` nil = bis zum Ende).
    /// Wird beim Transkribieren während der Aufnahme gebraucht: Der Ton wächst noch, jeder Abschnitt
    /// wird einzeln gemischt und transkribiert.
    public static func mix(mic: URL, system: URL?, output: URL, from: Double, to: Double?,
                           progress: @escaping (Double) -> Void) throws -> EnergyEnvelope {
        let envelope = try measure(mic: mic, system: system, from: from, to: to) { progress($0 * 0.4) }
        try write(mic: mic, system: system, output: output, envelope: envelope, from: from, to: to) { progress(0.4 + $0 * 0.6) }
        return envelope
    }

    /// Wie viele Sekunden Ton bereits auf der Platte stehen (beide Spuren, das Kürzere zählt).
    public static func availableSeconds(mic: URL, system: URL?) -> Double {
        guard let micFile = try? AVAudioFile(forReading: mic) else { return 0 }
        let micSeconds = Double(micFile.length) / micFile.processingFormat.sampleRate
        guard let system, FileManager.default.fileExists(atPath: system.path),
              let systemFile = try? AVAudioFile(forReading: system) else { return micSeconds }
        let systemSeconds = Double(systemFile.length) / systemFile.processingFormat.sampleRate
        // Beide Spuren liegen normal höchstens Sekundenbruchteile auseinander. Hinkt der Systemton weit hinterher,
        // liefert er gerade nichts – dann darf er die Live-Mitschrift nicht aufhalten. Vorher blieb sie in jeder
        // Vorlesung bei 0 stehen (Systemspur nach 97 Minuten: 0 Sekunden), und nach dem Stopp wurde alles
        // noch einmal komplett transkribiert. Gemischt wird ohnehin bis zum Ende der längeren Spur.
        return micSeconds - systemSeconds > 5 ? micSeconds : min(micSeconds, systemSeconds)
    }

    private static func readers(mic: URL, system: URL?, from: Double = 0,
                                to: Double? = nil) throws -> (ResamplingReader, ResamplingReader?, Double) {
        let micReader = try ResamplingReader(url: mic)
        let sysReader: ResamplingReader? = try system.flatMap { url in
            FileManager.default.fileExists(atPath: url.path) ? try ResamplingReader(url: url) : nil
        }
        if from > 0 {
            micReader.seek(toSeconds: from)
            sysReader?.seek(toSeconds: from)
        }
        let end = to ?? max(micReader.duration, sysReader?.duration ?? 0)
        return (micReader, sysReader, max(0, end - from))
    }

    private static func rms(_ buffer: AVAudioPCMBuffer?) -> Float {
        guard let buffer, let p = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var energy: Float = 0
        for i in 0..<Int(buffer.frameLength) { energy += p[i] * p[i] }
        return (energy / Float(buffer.frameLength)).squareRoot()
    }

    /// 1. Durchgang: Lautstärke beider Spuren je Zeitfenster.
    private static func measure(mic: URL, system: URL?, from: Double = 0, to: Double? = nil,
                                progress: (Double) -> Void) throws -> EnergyEnvelope {
        let (micReader, sysReader, total) = try readers(mic: mic, system: system, from: from, to: to)
        var micEnv: [Float] = [], sysEnv: [Float] = []
        var micDone = false, sysDone = sysReader == nil
        var processed: Double = 0

        while !(micDone && sysDone), processed < total {
            let m = micDone ? nil : micReader.read(frames: windowFrames)
            let s = sysDone ? nil : sysReader?.read(frames: windowFrames)
            if m == nil { micDone = true }
            if s == nil { sysDone = true }
            if m == nil && s == nil { break }
            micEnv.append(rms(m))
            if sysReader != nil { sysEnv.append(rms(s)) }
            processed += EnergyEnvelope.window
            if total > 0 { progress(min(1, processed / total)) }
        }
        return EnergyEnvelope(mic: micEnv, system: sysEnv)
    }

    /// 2. Durchgang: mischen. Bei Lautsprecherbetrieb wird das Mikrofon dort leise gedreht,
    /// wo es nur den Systemton mithört – sonst steht alles doppelt in der Aufnahme (Echo).
    private static func write(mic: URL, system: URL?, output: URL, envelope: EnergyEnvelope,
                              from: Double = 0, to: Double? = nil,
                              progress: (Double) -> Void) throws {
        let (micReader, sysReader, total) = try readers(mic: mic, system: system, from: from, to: to)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        try? FileManager.default.removeItem(at: output)
        let out = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let overSpeakers = envelope.bleed > EnergyEnvelope.speakerThreshold && !envelope.system.isEmpty
        var micDone = false, sysDone = sysReader == nil
        var processed: Double = 0
        var index = 0
        var previousGain: Float = 1

        while !(micDone && sysDone), processed < total {
            let m = micDone ? nil : micReader.read(frames: windowFrames)
            let s = sysDone ? nil : sysReader?.read(frames: windowFrames)
            if m == nil { micDone = true }
            if s == nil { sysDone = true }
            let length = Int(max(m?.frameLength ?? 0, s?.frameLength ?? 0))
            if length == 0 { break }

            var gain: Float = 1
            if overSpeakers, index < envelope.mic.count, index < envelope.system.count,
               !envelope.isOwnVoice(mic: envelope.mic[index], system: envelope.system[index]) {
                gain = 0.15
            }

            guard let mixed = AVAudioPCMBuffer(pcmFormat: ResamplingReader.outputFormat,
                                               frameCapacity: AVAudioFrameCount(length)) else { break }
            mixed.frameLength = AVAudioFrameCount(length)
            let dst = mixed.floatChannelData![0]
            let mp = m?.floatChannelData?[0], mLen = Int(m?.frameLength ?? 0)
            let sp = s?.floatChannelData?[0], sLen = Int(s?.frameLength ?? 0)

            for j in 0..<length {
                let mv: Float = (mp != nil && j < mLen) ? mp![j] : 0
                let sv: Float = (sp != nil && j < sLen) ? sp![j] : 0
                // Übergang zwischen zwei Fenstern weich, damit kein Knacken entsteht
                let g = previousGain + (gain - previousGain) * Float(j) / Float(length)
                dst[j] = max(-1, min(1, mv * g + sv * 0.9))
            }
            try out.write(from: mixed)

            previousGain = gain
            index += 1
            processed += EnergyEnvelope.window
            if total > 0 { progress(min(1, processed / total)) }
        }
    }

    /// Maximaler Pegel in dBFS (zur Erkennung stummer Aufnahmen).
    public static func peakDecibels(of url: URL) -> Float {
        guard let reader = try? ResamplingReader(url: url) else { return -.infinity }
        var peak: Float = 0
        while let buf = reader.read(frames: 64_000), let p = buf.floatChannelData?[0] {
            for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(p[i])) }
        }
        return peak > 0 ? 20 * log10(peak) : -.infinity
    }
}
