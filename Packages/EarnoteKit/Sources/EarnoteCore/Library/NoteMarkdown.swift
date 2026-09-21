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

    public var id: Int {
        switch self {
        case .paragraph(let id, _), .heading(let id, _, _, _), .bullet(let id, _, _), .numbered(let id, _, _, _),
             .task(let id, _, _, _), .quote(let id, _): return id
        }
    }
}

public enum NoteMarkdown {
    private static let taskRegex = try! Regex(#"^(\s*)[-*] \[([ xX])\] (.*)$"#)
    private static let timestampRegex = try! Regex(#"\s*\[(\d{1,2}:\d{2}(?::\d{2})?)\]\s*$"#)
    private static let numberedRegex = try! Regex(#"^(\d+)\.\s+(.*)$"#)

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

    /// Text zum Teilen: Titel als Überschrift, dann die Notiz
    public static func shareText(title: String, markdown: String) -> String {
        "# \(title)\n\n\(markdown)"
    }
}
