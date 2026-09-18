import Foundation

public protocol Transcriber: Sendable {
    var engineName: String { get }
    /// `hints` sind Namen und Fachbegriffe aus dem Wörterbuch; Engines, die so etwas nicht können, ignorieren sie.
    func transcribe(audio url: URL, language: String, hints: [String],
                    progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment]
}

/// Erzeugt den Transcriber für die aktuellen Einstellungen. Die App implementiert das Protokoll,
/// weil die Engines (Whisper, Apple-Spracherkennung) Plattform- bzw. ML-Code brauchen.
public protocol TranscriberProvider: Sendable {
    func makeTranscriber(for settings: AppSettings) async throws -> any Transcriber
}

public enum TranscriptionError: LocalizedError, Sendable {
    case modelMissing, unsupportedLanguage(String), unavailable(String), noSpeech

    public var errorDescription: String? {
        switch self {
        case .modelMissing: return "Kein Whisper-Modell geladen. Bitte in den Einstellungen unter „Transkription“ ein Modell herunterladen."
        case .unsupportedLanguage(let l): return "Die Sprache „\(l)“ wird von dieser Transkription nicht unterstützt."
        case .unavailable(let why): return why
        case .noSpeech: return "In der Aufnahme wurde keine Sprache erkannt. Ist das richtige Mikrofon ausgewählt?"
        }
    }
}

extension String {
    /// Entfernt Whisper-Steuerzeichen wie <|de|> oder [Musik].
    public var cleanedTranscriptText: String {
        var s = replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*[\[\(][^\]\)]*[\]\)]\s*$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
