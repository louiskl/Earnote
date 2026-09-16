import Foundation

protocol Transcriber {
    var engineName: String { get }
    func transcribe(audio url: URL, language: String,
                    progress: @escaping (Double) -> Void) async throws -> [TranscriptSegment]
}

enum TranscriptionError: LocalizedError {
    case modelMissing, unsupportedLanguage(String), unavailable(String), noSpeech

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Kein Whisper-Modell geladen. Bitte in den Einstellungen unter „Transkription“ ein Modell herunterladen."
        case .unsupportedLanguage(let l): return "Die Sprache „\(l)“ wird von dieser Transkription nicht unterstützt."
        case .unavailable(let why): return why
        case .noSpeech: return "In der Aufnahme wurde keine Sprache erkannt. Ist das richtige Mikrofon ausgewählt?"
        }
    }
}

enum TranscriberFactory {
    @MainActor
    static func make(for settings: AppSettings) throws -> Transcriber {
        switch settings.transcriptionEngine {
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleSpeechTranscriber() }
            #endif
            throw TranscriptionError.unavailable("Die Apple-Spracherkennung benötigt macOS 26. Bitte Whisper auswählen.")
        case .whisperKit:
            guard let selected = WhisperModelManager.shared.installedFolder(for: settings.whisperModel) else {
                throw TranscriptionError.modelMissing
            }
            return WhisperTranscriber(modelFolder: selected.folder, modelName: selected.model)
        }
    }

    static var appleSpeechAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

extension String {
    /// Entfernt Whisper-Steuerzeichen wie <|de|> oder [Musik].
    var cleanedTranscriptText: String {
        var s = replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*[\[\(][^\]\)]*[\]\)]\s*$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
