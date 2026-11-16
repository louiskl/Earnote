import Foundation

/// Folien oder Skript zur Aufnahme (Earnote Pro, am Mac frei). Das PDF und sein Text liegen im Ordner der Aufnahme
/// (`slides.pdf`, `slides.json` – eine Zeichenkette je Seite). Den Text liest die App beim Anhängen (PDFKit gehört
/// nicht in den Kern); die Verarbeitung gibt ihn der KI mit, damit sie Fachbegriffe und Formeln richtig schreibt und
/// auf „Folie 12“ verweist. Grenze wie bei „Wichtig“: Die Folien bleiben auf dem Gerät, iCloud kennt sie nicht.
public enum Slides {
    public static let pdfName = "slides.pdf"
    static let textName = "slides.json"
    /// Link-Schema für „Folie 12“ in der Notiz – nur in der Anzeige, gespeichert und exportiert wird reiner Text
    public static let linkScheme = "earnote-slide"

    public static func pdfURL(in folder: URL) -> URL { folder.appendingPathComponent(pdfName) }

    /// Text je Seite; leer, wenn keine Folien angehängt sind
    public static func pages(in folder: URL) -> [String] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(textName)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    public static func save(pages: [String], in folder: URL) throws {
        try JSONEncoder().encode(pages).write(to: folder.appendingPathComponent(textName), options: .atomic)
    }

    public static func remove(in folder: URL) {
        for name in [pdfName, textName] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
    }

    /// Hinweis an die KI mit dem Text der Folien. Passt nicht alles ins Budget, bekommt jede Folie gleich viel Platz –
    /// so bleiben die Nummern aller Folien erhalten, auf die die Notiz verweisen kann.
    public static func instruction(pages: [String], budget: Int) -> String {
        let numbered = pages.enumerated().compactMap { index, text -> (Int, String)? in
            let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return cleaned.isEmpty ? nil : (index + 1, cleaned)
        }
        guard !numbered.isEmpty, budget > 0 else { return "" }
        let total = numbered.reduce(0) { $0 + $1.1.count }
        let perPage = total <= budget ? Int.max : max(80, budget / numbered.count)
        var used = 0
        var lines: [String] = []
        for (number, text) in numbered {
            let line = "Folie \(number): \(text.prefix(perPage))"
            if used + line.count > budget + 200 { break }   // ponytail: ab ~100 Folien fallen die letzten weg
            used += line.count
            lines.append(line)
        }
        return """
        Zu dieser Aufnahme gehören Folien (Text unten, je Folie mit Nummer). Nutze sie, um Fachbegriffe, Namen und \
        Formeln richtig zu schreiben und Themen zuzuordnen. Schreib nichts von den Folien in die Notiz, was in der \
        Aufnahme nicht vorkam. Gehört ein Thema der Aufnahme zu einer Folie, schreib dahinter „(Folie N)“ – \
        auf Englisch „(Slide N)“ –, höchstens einmal je Thema.
        \(lines.joined(separator: "\n"))
        """
    }

    /// „Folie 12“ / „Slide 12“ als Link, damit ein Tipp die Folie öffnet. Nur Nummern, die es gibt.
    public static func linked(_ text: String, pageCount: Int) -> String {
        guard pageCount > 0 else { return text }
        return text.replacing(referenceRegex) { match in
            guard let page = Int(match.output.2), (1...pageCount).contains(page) else { return String(match.output.0) }
            return "[\(match.output.0)](\(linkScheme):\(page))"
        }
    }

    // Fester Ausdruck, kann nicht scheitern
    private static var referenceRegex: Regex<(Substring, Substring, Substring)> {
        try! Regex(#"(Folien?|Slides?)\s+(\d{1,4})\b"#)
    }

    /// Seitennummer aus einem Link von `linked`
    public static func page(from url: URL) -> Int? {
        guard url.scheme == linkScheme else { return nil }
        return Int(url.absoluteString.dropFirst(linkScheme.count + 1))
    }
}
