import Foundation

/// Welche Pro-Funktion bei *dieser* Aufnahme hilft – für den Pro-Hinweis nach einer fertigen Notiz (`FeedbackMoment.proHint`).
/// Liefert Kandidaten in Reihenfolge; die App nimmt den ersten, der noch Probeversuche hat. Rohwerte wie `Pro.Feature`.
public enum ProSuggestion: String, Sendable, CaseIterable {
    case translate, speakers, examRadar, chat

    /// - Parameters:
    ///   - spokenLanguage: Sprache der Aufnahme (`Recording.language`)
    ///   - readerLanguage: Sprache der Oberfläche, z. B. „de“
    ///   - isConversation: Meeting oder Call (Arbeit) statt Vorlesung
    ///   - speakerCount: schon erkannte Sprecher im Transkript
    ///   - hasMarks: In der Aufnahme wurde „Wichtig“ getippt
    public static func candidates(spokenLanguage: String, readerLanguage: String, isConversation: Bool,
                                  speakerCount: Int, hasMarks: Bool) -> [ProSuggestion] {
        var result: [ProSuggestion] = []
        if base(spokenLanguage) != base(readerLanguage) { result.append(.translate) }
        if isConversation && speakerCount < 2 { result.append(.speakers) }
        if !isConversation && !hasMarks { result.append(.examRadar) }
        result.append(.chat)
        return result
    }

    private static func base(_ code: String) -> String {
        String(code.lowercased().prefix { $0.isLetter })
    }
}
