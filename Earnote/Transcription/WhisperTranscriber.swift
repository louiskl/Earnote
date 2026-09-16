import AVFoundation
import Foundation
import WhisperKit

/// Verwaltet die Whisper-Modelle (Download, Auswahl).
@MainActor
final class WhisperModelManager: ObservableObject {
    static let shared = WhisperModelManager()

    struct ModelInfo: Identifiable, Hashable {
        let id: String
        var title: String
        var detail: String
    }

    /// Kuratierte Auswahl – die tatsächlich verfügbaren Namen werden online abgeglichen.
    static let curated: [ModelInfo] = [
        ModelInfo(id: "large-v3-v20240930_turbo", title: "Large v3 Turbo", detail: "Beste Qualität, schnell · ca. 1,6 GB · empfohlen"),
        ModelInfo(id: "large-v3-v20240930_626MB", title: "Large v3 Turbo (komprimiert)", detail: "Sehr gut, weniger Speicher · ca. 0,6 GB"),
        ModelInfo(id: "small", title: "Small", detail: "Schnell, gute Qualität · ca. 0,5 GB"),
        ModelInfo(id: "base", title: "Base", detail: "Sehr schnell, einfache Qualität · ca. 0,15 GB"),
    ]

    @Published var downloading: String?
    @Published var downloadProgress: Double = 0
    @Published var lastError: String?
    @Published private(set) var installed: [String: URL] = [:]
    @Published var available: [String] = []

    private let repo = "argmaxinc/whisperkit-coreml"
    private var installedKey = "whisper.installed"

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: installedKey) as? [String: String] {
            installed = saved.compactMapValues { path in
                FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
            }
        }
    }

    var recommendedModel: String {
        let rec = WhisperKit.recommendedModels().default
        return rec.isEmpty ? Self.curated[0].id : rec
    }

    func installedFolder(for model: String) -> (model: String, folder: URL)? {
        let available = installed.filter { FileManager.default.fileExists(atPath: $0.value.path) }
        if let url = available[model] { return (model, url) }
        guard let fallback = available.keys.sorted().first, let folder = available[fallback] else { return nil }
        Log.info("Whisper-Modell „\(model)“ fehlt; verwende installiertes Modell „\(fallback)“.")
        return (fallback, folder)
    }

    func refreshAvailable() async {
        do {
            available = try await WhisperKit.fetchAvailableModels(from: repo)
        } catch {
            Log.error("Modellliste: \(error.localizedDescription)")
        }
    }

    /// Zu einer Kurz-ID den vollen Modellnamen im Repository finden.
    func resolve(_ model: String) -> String {
        if available.contains(model) { return model }
        return available.first { $0.hasSuffix(model) } ?? model
    }

    func download(_ model: String) async -> Bool {
        downloading = model
        downloadProgress = 0
        lastError = nil
        defer { downloading = nil }
        if available.isEmpty { await refreshAvailable() }
        do {
            let variant = resolve(model)
            let folder = try await WhisperKit.download(
                variant: variant,
                downloadBase: Storage.modelsDir,
                from: repo,
                progressCallback: { progress in
                    Task { @MainActor in self.downloadProgress = progress.fractionCompleted }
                })
            installed[model] = folder
            UserDefaults.standard.set(installed.mapValues(\.path), forKey: installedKey)
            Log.info("Whisper-Modell geladen: \(variant) → \(folder.path)")
            return true
        } catch {
            lastError = "Download fehlgeschlagen: \(error.localizedDescription)"
            Log.error(lastError!)
            return false
        }
    }

    func delete(_ model: String) {
        guard let url = installed[model] else { return }
        Task { await WhisperKitCache.shared.release() }
        try? FileManager.default.removeItem(at: url)
        installed[model] = nil
        UserDefaults.standard.set(installed.mapValues(\.path), forKey: installedKey)
    }
}

/// Hält das geladene Whisper-Modell zwischen den Aufnahmen einer Warteschlange im Speicher.
/// Das Laden dauert – beim allerersten Mal mehrere Minuten, weil macOS das Modell für den Chip optimiert.
actor WhisperKitCache {
    static let shared = WhisperKitCache()
    private var folder: URL?
    private var kit: WhisperKit?

    func kit(for folder: URL) async throws -> WhisperKit {
        if let kit, self.folder == folder { return kit }
        kit = nil
        let config = WhisperKitConfig(modelFolder: folder.path, verbose: false, prewarm: false, load: true, download: false)
        let loaded = try await WhisperKit(config)
        kit = loaded
        self.folder = folder
        return loaded
    }

    /// Speicher freigeben, wenn nichts mehr zu tun ist.
    func release() {
        kit = nil
        folder = nil
    }
}

/// Lokale Transkription mit WhisperKit. Lange Aufnahmen werden in ~10-Minuten-Stücken
/// verarbeitet, geschnitten an leisen Stellen, damit der Speicherbedarf klein bleibt.
struct WhisperTranscriber: Transcriber {
    let modelFolder: URL
    let modelName: String
    var engineName: String { "Whisper \(modelName)" }
    private let sliceSeconds = 600
    private let searchSeconds = 15

    func transcribe(audio url: URL, language: String,
                    progress: @escaping (Double) -> Void) async throws -> [TranscriptSegment] {
        let kit = try await WhisperKitCache.shared.kit(for: modelFolder)

        var options = DecodingOptions()
        options.task = .transcribe
        options.temperature = 0
        options.skipSpecialTokens = true
        options.withoutTimestamps = false
        options.chunkingStrategy = .vad
        if language == "auto" {
            options.language = nil
            options.detectLanguage = true
        } else {
            options.language = language
            options.detectLanguage = false
        }

        let reader = try ResamplingReader(url: url)
        let total = max(1, reader.duration)
        var segments: [TranscriptSegment] = []
        var carry: [Float] = []
        var offset: Double = 0
        var finished = false

        while !finished {
            try Task.checkCancellation()
            // Samples für ein Stück sammeln
            var samples = carry
            carry = []
            let target = (sliceSeconds + searchSeconds) * 16_000
            while samples.count < target {
                guard let buf = reader.read(frames: 16_000 * 30), let p = buf.floatChannelData?[0] else {
                    finished = true
                    break
                }
                samples.append(contentsOf: UnsafeBufferPointer(start: p, count: Int(buf.frameLength)))
            }
            if samples.isEmpty { break }

            // An der leisesten Stelle kurz nach der Zielgrenze schneiden
            if !finished {
                let cut = Self.quietestPoint(in: samples, from: sliceSeconds * 16_000, to: samples.count)
                carry = Array(samples[cut...])
                samples = Array(samples[..<cut])
            }

            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            for result in results {
                for seg in result.segments {
                    let text = seg.text.cleanedTranscriptText
                    guard !text.isEmpty else { continue }
                    segments.append(TranscriptSegment(start: offset + Double(seg.start),
                                                      end: offset + Double(seg.end), text: text))
                }
            }
            offset += Double(samples.count) / 16_000
            progress(min(1, offset / total))
        }
        return Self.removeRepetitions(segments)
    }

    static func quietestPoint(in samples: [Float], from start: Int, to end: Int) -> Int {
        let window = 4_000 // 0,25 s
        var best = start, bestEnergy = Float.greatestFiniteMagnitude
        var i = start
        while i + window <= end {
            var e: Float = 0
            for j in i..<(i + window) { e += samples[j] * samples[j] }
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window
        }
        return min(max(best, 1), samples.count)
    }

    /// Whisper wiederholt bei Stille manchmal denselben Satz – solche Schleifen entfernen.
    static func removeRepetitions(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var keys: [String] = []
        func key(_ text: String) -> String {
            text.lowercased().components(separatedBy: CharacterSet.punctuationCharacters
                .union(.whitespacesAndNewlines)).joined()
        }
        func follows(_ a: TranscriptSegment, _ b: TranscriptSegment) -> Bool {
            a.speaker == b.speaker && b.start >= a.start && b.start - a.end <= 3
        }
        for seg in segments {
            let normalized = key(seg.text)
            // Kurze Antworten, Sprecherwechsel und Wiederholungen nach Pausen können echter Inhalt sein.
            if normalized.count >= 12, keys.last == normalized, let last = out.last, follows(last, seg) {
                // Zeitspanne mitführen, damit auch eine längere Schleife am Stück erkannt wird.
                out[out.count - 1].end = max(last.end, seg.end)
                continue
            }
            out.append(seg)
            keys.append(normalized)
            let n = out.count
            if n >= 4, keys[n - 4].count >= 12, keys[n - 3].count >= 12,
               keys[n - 4] != keys[n - 3], keys[n - 4] == keys[n - 2], keys[n - 3] == keys[n - 1],
               follows(out[n - 4], out[n - 3]), follows(out[n - 3], out[n - 2]), follows(out[n - 2], out[n - 1]) {
                // A–B–A–B: das erste Paar behalten. Nicht über Lücken oder Sprecherwechsel hinweg kürzen.
                out[n - 3].end = max(out[n - 3].end, out[n - 1].end)
                out.removeLast(2)
                keys.removeLast(2)
            }
        }
        return out
    }
}
