import Foundation

/// „Wichtig!“-Markierungen und Klausur-Radar (Earnote Pro).
/// Markierungen liegen als `marks.json` im Ordner der Aufnahme – nur auf diesem Gerät, wie das Audio.
/// ponytail: gibt das iPhone die Aufnahme an den Mac ab (Weg B), kennt der Mac die Markierungen nicht.
public enum ImportantMarks {
    static let fileName = "marks.json"

    public static func load(in folder: URL) -> [Double] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return [] }
        return (try? JSONDecoder().decode([Double].self, from: data)) ?? []
    }

    public static func append(_ seconds: Double, in folder: URL) {
        let marks = load(in: folder) + [seconds]
        try? JSONEncoder().encode(marks).write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }

    /// Hinweis an die KI: die markierten Stellen mit dem, was kurz davor gesagt wurde (man tippt meist erst danach)
    public static func instruction(marks: [Double], transcript: Transcript?) -> String {
        guard !marks.isEmpty else { return "" }
        let quotes = marks.sorted().map { mark -> String in
            let said = transcript?.segments
                .filter { $0.end >= mark - 25 && $0.start <= mark + 5 }
                .map(\.text).joined(separator: " ") ?? ""
            let clock = "[\(TimeFormat.clock(mark))]"
            return said.isEmpty ? "- \(clock)" : "- \(clock) „\(said.prefix(400))“"
        }
        return """
        Während der Aufnahme wurden diese Stellen ausdrücklich als wichtig markiert. Nimm jede davon in den Abschnitt \
        mit den Prüfungshinweisen auf (Überschrift „Wichtig für die Klausur“, falls es keinen gibt), mit Zeitmarke:
        \(quotes.joined(separator: "\n"))
        """
    }
}

public enum ExamRadar {
    /// Überschriften, unter denen Prüfungsrelevantes steht – deutsch wie englisch, weil die Notizsprache frei ist
    static let headingWords = ["klausur", "prüfung", "wichtig", "merken", "exam", "important", "key takeaways"]

    /// Die Punkte aus den Prüfungs-Abschnitten einer Notiz (Aufzählungen, nummerierte Punkte, Absätze)
    public static func items(in markdown: String) -> [String] {
        var inSection = false
        var items: [String] = []
        for block in NoteMarkdown.blocks(markdown) {
            switch block {
            case .heading(_, _, let text, _):
                let lower = text.lowercased()
                inSection = headingWords.contains { lower.contains($0) }
            case .bullet(_, let text, _), .numbered(_, _, let text, _), .paragraph(_, let text):
                if inSection { items.append(text) }
            default:
                continue
            }
        }
        return items
    }

    /// Alles als Markdown zum Teilen oder Drucken: je Aufnahme eine Überschrift, darunter ihre Punkte
    public static func markdown(title: String, notes: [(title: String, items: [String])]) -> String {
        var out = "# \(title)\n"
        for note in notes where !note.items.isEmpty {
            out += "\n## \(note.title)\n" + note.items.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return out
    }
}
