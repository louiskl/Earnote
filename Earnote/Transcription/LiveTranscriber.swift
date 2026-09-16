#if canImport(FoundationModels)
import EarnoteCore
import AVFoundation
import Foundation
import Speech

/// Schreibt während der Aufnahme live mit (Apple-Spracherkennung, macOS 26+).
/// Das ist nur die Vorschau – das endgültige Transkript entsteht danach wie bisher aus der Audiodatei.
@available(macOS 26.0, *)
final class LiveTranscriber: @unchecked Sendable {
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?

    /// Format, in dem die Puffer geliefert werden müssen (steht nach `start` fest).
    private(set) var audioFormat: AVAudioFormat?

    /// `onUpdate` liefert den bereits feststehenden Text und den vorläufigen Rest.
    func start(language: String, onUpdate: @escaping @MainActor (String, String) -> Void) async throws {
        let id = language == "auto" ? Locale.current.identifier : language
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
            throw TranscriptionError.unsupportedLanguage(id)
        }
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.info("Lade Sprachmodell für die Live-Mitschrift (\(locale.identifier)) …")
            try await request.downloadAndInstall()
        }
        audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultTask = Task {
            var settled = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        if !text.isEmpty { settled += (settled.isEmpty ? "" : " ") + text }
                        // Für die Anzeige reicht das Ende; alles Ältere steht später im Transkript.
                        if settled.count > 4_000 { settled = String(settled.suffix(3_000)) }
                        await onUpdate(settled, "")
                    } else {
                        await onUpdate(settled, text)
                    }
                }
            } catch is CancellationError {
                // normales Ende beim Stoppen der Aufnahme
            } catch {
                Log.error("Live-Mitschrift: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        Log.info("Live-Mitschrift gestartet (\(locale.identifier))")
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        continuation?.yield(AnalyzerInput(buffer: buffer))
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        resultTask?.cancel()
        resultTask = nil
    }
}
#endif
