import EarnoteCore
import Foundation
import WhisperKit

/// Lokale Transkription mit WhisperKit. Lange Aufnahmen werden in ~10-Minuten-Stücken
/// verarbeitet, geschnitten an leisen Stellen, damit der Speicherbedarf klein bleibt.
public struct WhisperTranscriber: Transcriber {
    public let modelFolder: URL
    public let modelName: String
    public var engineName: String { "Whisper \(modelName)" }
    private let sliceSeconds = 600
    private let searchSeconds = 15

    public init(modelFolder: URL, modelName: String) {
        self.modelFolder = modelFolder
        self.modelName = modelName
    }

    public func transcribe(audio url: URL, language: String,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
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
        return TranscriptCleanup.removeRepetitions(segments)
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
}
