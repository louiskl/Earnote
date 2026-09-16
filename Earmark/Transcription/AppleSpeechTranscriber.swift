#if canImport(FoundationModels)
import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Apples eingebaute Spracherkennung (SpeechAnalyzer, macOS 26+). Kein Modell-Download nötig.
@available(macOS 26.0, *)
struct AppleSpeechTranscriber: Transcriber {
    static func supports(language: String) async -> Bool {
        let id = language == "auto" ? Locale.current.identifier : language
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) != nil
    }

    func transcribe(audio url: URL, language: String,
                    progress: @escaping (Double) -> Void) async throws -> [TranscriptSegment] {
        let id = language == "auto" ? Locale.current.identifier : language
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
            throw TranscriptionError.unsupportedLanguage(id)
        }
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.info("Lade Apple-Sprachmodell für \(locale.identifier) …")
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let duration = max(1, Double(file.length) / file.processingFormat.sampleRate)

        let collector = Task { () throws -> [TranscriptSegment] in
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = result.range.start.seconds
                let end = CMTimeRangeGetEnd(result.range).seconds
                segments.append(TranscriptSegment(start: start.isFinite ? start : 0,
                                                  end: end.isFinite ? end : start, text: text))
                if end.isFinite { progress(min(1, end / duration)) }
            }
            return segments
        }

        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value
    }
}
#endif
