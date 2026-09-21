import Foundation

/// Eine Karteikarte: vorne die Frage, hinten die Antwort.
public struct Flashcard: Hashable, Sendable {
    public let question: String
    public let answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// Karteikarten aus einer Aufnahme. Sie leben als Abschnitt in der Notiz („Frage :: Antwort“) –
/// so lassen sie sich wie der Rest der Notiz bearbeiten, ohne eigenes Datenmodell.
public enum Flashcards {
    /// Trennzeichen zwischen Frage und Antwort – auffällig genug, um nicht in normalem Text vorzukommen
    public static let separator = " :: "

    /// Karteikarten aus dem Text der Notiz lesen (egal, unter welcher Überschrift sie stehen)
    public static func parse(_ markdown: String) -> [Flashcard] {
        markdown.components(separatedBy: "\n").compactMap { line in
            var text = line.trimmingCharacters(in: .whitespaces)
            for marker in ["- ", "* ", "• "] where text.hasPrefix(marker) {
                text = String(text.dropFirst(marker.count))
            }
            guard let range = text.range(of: separator) else { return nil }
            let question = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let answer = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !question.isEmpty, !answer.isEmpty else { return nil }
            return Flashcard(question: question, answer: answer)
        }
    }

    /// Der Abschnitt, der unter die Notiz gehängt wird
    public static func markdownSection(_ cards: [Flashcard], heading: String) -> String {
        guard !cards.isEmpty else { return "" }
        return "## \(heading)\n\n"
            + cards.map { "- \($0.question)\(separator)\($0.answer)" }.joined(separator: "\n")
            + "\n"
    }

    /// Anki liest CSV mit Komma: erste Spalte Vorderseite, zweite Rückseite.
    public static func csv(_ cards: [Flashcard]) -> String {
        func field(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return cards.map { "\(field($0.question)),\(field($0.answer))" }.joined(separator: "\n") + "\n"
    }

    /// Fragt die KI nach Karteikarten. Antwortet sie mit Fließtext, bleibt die Liste leer –
    /// dann ist nichts passiert, statt Unsinn in der Notiz zu landen.
    public static func generate(client: any LLMClient, material: String, language: String,
                                count: Int = 12, limit: Int = 20_000) async throws -> [Flashcard] {
        let system = t("""
        Du machst Karteikarten zum Lernen aus einer Mitschrift.
        Antworte ausschließlich mit Zeilen der Form: Frage :: Antwort
        Keine Nummerierung, keine Überschriften, keine Einleitung.
        Jede Frage fragt genau eine Sache ab, die Antwort passt in ein bis zwei Sätze.
        Frage nach Begriffen, Zusammenhängen und Rechenwegen – nicht nach Nebensächlichkeiten
        wie Terminen oder Organisatorischem.
        """) + "\n" + t("Sprache der Karten: \(language)")
        let prompt = t("Mach höchstens \(count) Karteikarten aus diesem Material:") + "\n\n"
            + String(material.prefix(limit))
        return parse(try await client.complete(system: system, prompt: prompt))
    }
}
