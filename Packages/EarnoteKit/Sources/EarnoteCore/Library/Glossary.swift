import Foundation

/// Wörterbuch: richtige Schreibweisen von Namen und Fachbegriffen, dazu die Hörfehler, die dabei entstehen.
/// Es hilft an drei Stellen: als Hinweis für die Spracherkennung, als Hinweis für die KI und beim
/// nachträglichen Korrigieren einer fertigen Notiz.
public enum Glossary {
    /// Einträge, die für eine Aufnahme gelten: die globalen und die des Bereichs.
    public static func forCategory(_ id: UUID?, in terms: [GlossaryTerm]) -> [GlossaryTerm] {
        terms.filter { $0.categoryID == nil || $0.categoryID == id }
            .filter { !$0.term.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Begriffe als Hinweis für die Spracherkennung (Whisper-Prompt).
    public static func speechHints(_ terms: [GlossaryTerm]) -> [String] {
        terms.map { $0.term.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Zeilen für die KI – leer, wenn es nichts zu sagen gibt.
    public static func promptText(_ terms: [GlossaryTerm]) -> String {
        let lines = terms.compactMap { term -> String? in
            let name = term.term.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let variants = term.variants.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return variants.isEmpty ? "- \(name)" : "- \(name) (oft falsch erkannt als: \(variants.joined(separator: ", ")))"
        }
        guard !lines.isEmpty else { return "" }
        return "Richtige Schreibweisen von Namen und Begriffen (im Transkript oft falsch erkannt):\n"
            + lines.joined(separator: "\n")
    }
}

/// Eine falsch erkannte Schreibweise durch die richtige ersetzen – in Notiz und Transkript.
public enum TermCorrection {
    /// Ersetzt `wrong` durch `right`, Groß- und Kleinschreibung egal, aber nur als ganzes Wort:
    /// aus „Maier“ wird „Meier“, aus „Maiers“ nicht „Meiers“ mittendrin.
    public static func replace(_ text: String, wrong: String, with right: String) -> String {
        let wrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wrong.isEmpty else { return text }
        // Beginnt oder endet der Begriff mit einem Sonderzeichen (z. B. „§ 5“), gibt es dort keine Wortgrenze.
        let head = wrong.first.map(isWordCharacter) == true ? "\\b" : ""
        let tail = wrong.last.map(isWordCharacter) == true ? "\\b" : ""
        let pattern = head + NSRegularExpression.escapedPattern(for: wrong) + tail
        return text.replacingOccurrences(of: pattern,
                                         with: NSRegularExpression.escapedTemplate(for: right),
                                         options: [.regularExpression, .caseInsensitive])
    }

    private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
}
