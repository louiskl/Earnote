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
        entries(markdown).map(\.card)
    }

    /// Zeilenpositionen bleiben erhalten, damit Checkboxen und Suche weiterhin stimmen.
    public static func entries(_ markdown: String) -> [(line: Int, endLine: Int, card: Flashcard)] {
        var result: [(line: Int, endLine: Int, card: Flashcard)] = []
        var pending: (line: Int, question: String)?
        var inCode = false
        let labels = ["frage", "antwort", "question", "answer", "q", "a"]
        for (index, raw) in markdown.components(separatedBy: "\n").enumerated() {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^(?:[-*•] |\d+[.)]\s+)"#, with: "", options: .regularExpression)
            if text.hasPrefix("```") { inCode.toggle(); pending = nil; continue }
            guard !inCode else { continue }
            if text.isEmpty { continue }
            // Aufgaben, Überschriften und Zitate bleiben, was sie sind – auch wenn „::“ darin steht
            if ["#", ">", "[ ]", "[x]", "[X]"].contains(where: text.hasPrefix) { pending = nil; continue }
            guard var range = text.range(of: "::") else { pending = nil; continue }
            var label = text[..<range.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: "* ")).lowercased()
            // Ohne Beschriftung („Frage ::“) zählt nur „::“ mit Leerraum daneben – sonst würde aus
            // „std::vector“ oder „Klasse::methode“ in einer Informatik-Notiz eine Karte.
            if !labels.contains(label) {
                guard let spaced = text.range(of: #"\s::|::\s"#, options: .regularExpression) else { pending = nil; continue }
                range = spaced
                label = ""
            }
            let front = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let back = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !front.isEmpty, !back.isEmpty, !labels.contains(back.lowercased()) else { pending = nil; continue }
            if ["frage", "question", "q"].contains(label) {
                pending = (index, back)
            } else if ["antwort", "answer", "a"].contains(label) {
                if let pending {
                    result.append((pending.line, index, Flashcard(question: pending.question, answer: back)))
                }
                pending = nil
            } else {
                pending = nil
                result.append((index, index, Flashcard(question: front, answer: back)))
            }
        }
        return result
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
        Schreibe pro Karte genau eine Zeile: tatsächlicher Fragetext :: tatsächlicher Antworttext.
        Beispiel: Welche Aufgabe hat die CPU? :: Die CPU führt Programmbefehle aus.
        Die Wörter „Frage“ und „Antwort“ sind keine Inhalte und dürfen nicht als Platzhalter erscheinen.
        Schreibe Frage und Antwort niemals auf getrennte Zeilen.
        Nutze nur belegte Inhalte aus dem Material; erfinde keine Fakten.
        Keine Nummerierung, keine Überschriften, keine Einleitung.
        Jede Frage fragt genau eine Sache ab, die Antwort passt in ein bis zwei Sätze.
        Frage nach Begriffen, Zusammenhängen und Rechenwegen – nicht nach Nebensächlichkeiten
        wie Terminen oder Organisatorischem.
        """) + "\n" + t("Sprache der Karten: \(language)")
        let prompt = t("Mach höchstens \(count) Karteikarten aus diesem Material:") + "\n\n"
            + String(material.prefix(limit))
        var response = try await client.complete(system: system, prompt: prompt)
        response = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if response.hasPrefix("```") {
            response = response.replacingOccurrences(of: #"^```[^\n]*\n"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\n```\s*$"#, with: "", options: .regularExpression)
        }
        let cards = parse(response)
        var seen = Set<String>()
        return Array(cards.filter { seen.insert($0.question.lowercased()).inserted }.prefix(max(0, count)))
    }
}
