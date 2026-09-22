import Foundation

/// Die Notiz als Folge einfacher Blöcke, so wie die KI sie schreibt: Absätze, Überschriften (ggf. mit Zeitmarke),
/// Aufzählungen und Aufgaben. Aufgaben merken sich ihre Zeile, damit Abhaken genau diese Zeile ändert.
public enum NoteBlock: Equatable, Sendable, Identifiable {
    case paragraph(id: Int, text: String)
    /// `level` 1–3; `timestamp` z. B. „00:14:05“ aus „## Budget [00:14:05]“
    case heading(id: Int, level: Int, text: String, timestamp: String?)
    case bullet(id: Int, text: String, indent: Int)
    case numbered(id: Int, number: String, text: String, indent: Int)
    case task(id: Int, text: String, isDone: Bool, line: Int)
    case quote(id: Int, text: String)

    /// Der reine Text des Blocks – für Suche und Zählung der Fundstellen
    public var plainText: String {
        switch self {
        case .paragraph(_, let text), .bullet(_, let text, _), .numbered(_, _, let text, _),
             .task(_, let text, _, _), .quote(_, let text):
            return text
        case .heading(_, _, let text, let timestamp):
            return timestamp.map { "\(text) \($0)" } ?? text
        }
    }

    public var id: Int {
        switch self {
        case .paragraph(let id, _), .heading(let id, _, _, _), .bullet(let id, _, _), .numbered(let id, _, _, _),
             .task(let id, _, _, _), .quote(let id, _): return id
        }
    }
}

public enum NoteMarkdown {
    // `Regex` ist nicht Sendable; als berechnete Eigenschaft gehört jede Auswertung dem Aufrufer.
    private static var taskRegex: Regex<AnyRegexOutput> { try! Regex(#"^(\s*)[-*] \[([ xX])\] (.*)$"#) }
    private static var timestampRegex: Regex<AnyRegexOutput> { try! Regex(#"\s*\[(\d{1,2}:\d{2}(?::\d{2})?)\]\s*$"#) }
    private static var numberedRegex: Regex<AnyRegexOutput> { try! Regex(#"^(\d+)\.\s+(.*)$"#) }

    public static func blocks(_ markdown: String) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        var paragraph: [String] = []
        let lines = markdown.components(separatedBy: "\n")

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(id: blocks.count, text: paragraph.joined(separator: " ")))
            paragraph = []
        }

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = (raw.prefix { $0 == " " }.count) / 2
            if line.isEmpty || line == "---" {
                flushParagraph()
            } else if let match = raw.firstMatch(of: taskRegex) {
                flushParagraph()
                let mark = String(match.output[2].substring ?? " ")
                blocks.append(.task(id: blocks.count, text: String(match.output[3].substring ?? ""),
                                    isDone: mark.lowercased() == "x", line: index))
            } else if let level = headingLevel(line) {
                flushParagraph()
                var text = String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)
                var timestamp: String?
                if let m = text.firstMatch(of: timestampRegex), let stamp = m.output[1].substring {
                    timestamp = String(stamp)
                    text = String(text[..<m.range.lowerBound])
                }
                blocks.append(.heading(id: blocks.count, level: level, text: text, timestamp: timestamp))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushParagraph()
                blocks.append(.bullet(id: blocks.count, text: String(line.dropFirst(2)), indent: indent))
            } else if let m = line.firstMatch(of: numberedRegex), let number = m.output[1].substring, let rest = m.output[2].substring {
                flushParagraph()
                blocks.append(.numbered(id: blocks.count, number: String(number), text: String(rest), indent: indent))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(id: blocks.count, text: String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        for level in 1...3 where line.hasPrefix(String(repeating: "#", count: level) + " ") { return level }
        return nil
    }

    /// Schaltet die Aufgabe in dieser Zeile um. Andere Zeilen bleiben Zeichen für Zeichen gleich.
    /// - Returns: nil, wenn die Zeile keine Aufgabe ist
    public static func togglingTask(in markdown: String, line: Int) -> String? {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.indices.contains(line),
              let match = lines[line].firstMatch(of: taskRegex),
              let markRange = match.output[2].range else { return nil }
        let done = lines[line][markRange].lowercased() == "x"
        lines[line].replaceSubrange(markRange, with: done ? " " : "x")
        return lines.joined(separator: "\n")
    }

    /// Offene Aufgaben (so zählt auch der Rest der App)
    public static func openTaskCount(_ markdown: String) -> Int {
        openTasks(markdown).count
    }

    /// Der Text jeder offenen Aufgabe, ohne Kästchen und Aufzählungszeichen
    public static func openTasks(_ markdown: String) -> [String] {
        markdown.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]") else { return nil }
            let text = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
    }

    /// Schützt Formeln vor der Markdown-Deutung. „A*v = λ*v“ wäre sonst „Av = λv“:
    /// Ein einzelnes Sternchen gilt in Markdown als Kursiv-Zeichen, auch mitten im Wort.
    /// Doppelte Sternchen (fett) und Code-Abschnitte bleiben, wie sie sind.
    public static func protectingMath(_ text: String) -> String {
        guard text.contains("*") else { return text }
        var out = ""
        var index = text.startIndex
        var insideCode = false
        while index < text.endIndex {
            let character = text[index]
            if character == "`" {
                insideCode.toggle()
                out.append(character)
                index = text.index(after: index)
                continue
            }
            if character == "*", !insideCode {
                var end = index
                while end < text.endIndex, text[end] == "*" { end = text.index(after: end) }
                let run = text.distance(from: index, to: end)
                // Genau ein Sternchen = Rechenzeichen, zwei = fett (das soll wirken)
                out += run == 1 ? "\\*" : String(repeating: "*", count: run)
                index = end
                continue
            }
            out.append(character)
            index = text.index(after: index)
        }
        return out
    }

    /// Einen Abschnitt („## Karteikarten“) samt Inhalt herausnehmen – bis zur nächsten Überschrift
    public static func removingSection(named heading: String, from markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var out: [String] = []
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                skipping = title.caseInsensitiveCompare(heading) == .orderedSame
            }
            if !skipping { out.append(line) }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Wörter, an denen ein Ergebnis-Abschnitt zu erkennen ist – deutsch wie englisch,
    /// weil die Sprache der Notizen frei wählbar ist.
    private static let resultHeadings = ["entscheidungen", "ergebnisse", "beschlüsse",
                                         "decisions", "results", "outcomes", "key decisions"]

    /// Kurzprotokoll zum Weiterschicken: Titel, die Kurzfassung, Ergebnisse und alle Aufgaben –
    /// ohne Themenblöcke und Transkript. Findet sich kein Ergebnis-Abschnitt, bleibt es bei
    /// Kurzfassung und Aufgaben.
    public static func shortMinutes(title: String, markdown: String) -> String {
        var intro: [String] = []
        var results: [String] = []
        var tasks: [String] = []
        var inResults = false
        var beforeFirstHeading = true

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                beforeFirstHeading = false
                let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
                inResults = resultHeadings.contains { heading.contains($0) }
                continue
            }
            if isTask(trimmed) {
                tasks.append(trimmed)
            } else if inResults, !trimmed.isEmpty {
                results.append(trimmed)
            } else if beforeFirstHeading, !trimmed.isEmpty {
                intro.append(trimmed)
            }
        }

        var out = "# \(title)\n"
        if !intro.isEmpty { out += "\n" + intro.joined(separator: "\n") + "\n" }
        if !results.isEmpty { out += "\n## " + t("Ergebnisse") + "\n" + results.joined(separator: "\n") + "\n" }
        if !tasks.isEmpty { out += "\n## " + t("Aufgaben") + "\n" + tasks.joined(separator: "\n") + "\n" }
        return out
    }

    private static func isTask(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [")
    }

    /// Text zum Teilen: Titel als Überschrift, dann die Notiz
    public static func shareText(title: String, markdown: String) -> String {
        "# \(title)\n\n\(markdown)"
    }
}
