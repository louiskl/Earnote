import Foundation

public struct ExportPayload: Sendable {
    public var recording: Recording
    public var category: RecordingCategory?
    public var summary: Summary?
    public var transcript: String
    public var settings: DestinationSettings

    public init(recording: Recording, category: RecordingCategory?, summary: Summary?, transcript: String,
                settings: DestinationSettings) {
        self.recording = recording
        self.category = category
        self.summary = summary
        self.transcript = transcript
        self.settings = settings
    }

    public var title: String { summary?.title ?? recording.title }
    public var includeTranscript: Bool { settings.includeTranscript && !transcript.isEmpty }
}

/// Das Ziel ist noch nicht fertig eingerichtet. Das ist kein Fehler der Aufnahme –
/// die Notizen sind fertig, nur dieses eine Ziel wird übersprungen.
public struct DestinationNotConfigured: LocalizedError, Sendable {
    public let hint: String
    public var errorDescription: String? { hint }

    public init(hint: String) { self.hint = hint }
}

public protocol Destination: Sendable {
    /// Gibt optional einen Link zum erstellten Eintrag zurück.
    func export(_ payload: ExportPayload) async throws -> String?
}

public struct DestinationInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    public let detail: String

    public init(id: String, name: String, symbol: String, detail: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.detail = detail
    }
}

/// Welche Ziele es gibt und wie sie erzeugt werden. Die App ergänzt ihre plattformspezifischen Ziele.
public protocol DestinationProvider: Sendable {
    /// In der Reihenfolge, in der die Ziele angezeigt werden
    var all: [DestinationInfo] { get }
    func make(_ id: String) -> (any Destination)?
    /// Fehlt noch etwas an der Einrichtung? (nil = bereit)
    func setupProblem(_ id: String, _ settings: DestinationSettings) -> String?
}

extension DestinationProvider {
    public func info(_ id: String) -> DestinationInfo? { all.first { $0.id == id } }
}

/// Ziele, die auf jeder Plattform funktionieren: Notion, Obsidian, Markdown-Ordner.
public struct CoreDestinations: DestinationProvider {
    public init() {}

    public var all: [DestinationInfo] {
        [
            DestinationInfo(id: NotionDestination.id, name: t("Notion"), symbol: "square.stack.3d.up.fill",
                            detail: t("Neue Seite in einer Notion-Datenbank mit Kategorie, Datum und Aufgaben.")),
            DestinationInfo(id: ObsidianDestination.id, name: t("Obsidian"), symbol: "diamond.fill",
                            detail: t("Markdown-Notiz mit Eigenschaften in deinem Vault.")),
            DestinationInfo(id: MarkdownDestination.id, name: t("Markdown-Ordner"), symbol: "folder.fill",
                            detail: t("Eine .md-Datei pro Aufnahme – ideal für Backups, iCloud Drive oder andere Apps.")),
            DestinationInfo(id: LogseqDestination.id, name: t("Logseq"), symbol: "list.bullet.indent",
                            detail: t("Seite in deinem Graphen, als Aufzählung mit Eigenschaften und TODOs.")),
            DestinationInfo(id: TodoistDestination.id, name: t("Todoist"), symbol: "checkmark.circle.fill",
                            detail: t("Offene Aufgaben aus der Notiz, je Bereich ein eigenes Projekt.")),
        ]
    }

    public func make(_ id: String) -> (any Destination)? {
        switch id {
        case NotionDestination.id: return NotionDestination()
        case ObsidianDestination.id: return ObsidianDestination()
        case MarkdownDestination.id: return MarkdownDestination()
        case LogseqDestination.id: return LogseqDestination()
        case TodoistDestination.id: return TodoistDestination()
        default: return nil
        }
    }

    public func setupProblem(_ id: String, _ s: DestinationSettings) -> String? {
        switch id {
        case NotionDestination.id:
            if !Keychain.hasValue(for: "notion.token") { return t("Notion-Schlüssel fehlt") }
            if s.notionDatabaseID.isEmpty { return t("Notion-Datenbank noch nicht angelegt") }
        case ObsidianDestination.id:
            if s.obsidianVaultPath.isEmpty { return t("Obsidian-Vault nicht ausgewählt") }
        case LogseqDestination.id:
            if s.logseqGraphPath.isEmpty { return t("Logseq-Graph nicht ausgewählt") }
        case TodoistDestination.id:
            if !Keychain.hasValue(for: "todoist.token") { return t("Todoist-Schlüssel fehlt") }
        default: break
        }
        return nil
    }
}

// MARK: - Markdown-Dokument

public enum MarkdownDocument {
    public static func build(_ p: ExportPayload, frontmatter: Bool) -> String {
        var out = ""
        let iso = ISO8601DateFormatter()
        if frontmatter {
            out += "---\n"
            out += "title: \"\(p.title.replacingOccurrences(of: "\"", with: "'"))\"\n"
            out += "date: \(iso.string(from: p.recording.startedAt))\n"
            if let c = p.category { out += "category: \"\(c.name)\"\n" }
            if let app = p.recording.sourceApp { out += "source: \"\(app)\"\n" }
            out += "duration_minutes: \(Int(p.recording.duration / 60))\n"
            out += "tags: [\(AppInfo.name.lowercased())\(p.category.map { ", \(tag($0.name))" } ?? "")]\n"
            out += "---\n\n"
        }
        out += "# \(p.title)\n\n"
        out += "> \(metaLine(p))\n\n"
        if let s = p.summary { out += s.markdown + "\n\n" }
        if p.includeTranscript {
            out += "## Transkript\n\n"
            out += p.transcript.components(separatedBy: "\n").joined(separator: "\n\n") + "\n"
        }
        return out
    }

    public static func metaLine(_ p: ExportPayload) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateStyle = .medium; df.timeStyle = .short
        var parts = [df.string(from: p.recording.startedAt), "\(Int(p.recording.duration / 60)) Min."]
        if let c = p.category { parts.insert(c.name, at: 0) }
        if let app = p.recording.sourceApp { parts.append(app) }
        return parts.joined(separator: " · ")
    }

    public static func tag(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
    }

    public static func fileName(_ p: ExportPayload) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HHmm"
        let clean = p.title.replacingOccurrences(of: #"[/\\:*?"<>|#^\[\]]"#, with: "", options: .regularExpression)
        return "\(df.string(from: p.recording.startedAt)) \(clean.prefix(80)).md"
    }

    /// Sehr einfache Markdown→HTML-Umwandlung (für Apple Notizen).
    public static func html(_ markdown: String) -> String {
        func esc(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<b>$1</b>", options: .regularExpression)
            return t
        }
        var html = ""
        var inList = false
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let isItem = line.hasPrefix("- ") || line.hasPrefix("* ") || line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
            if !isItem && inList { html += "</ul>"; inList = false }
            if line.hasPrefix("### ") { html += "<h3>\(esc(String(line.dropFirst(4))))</h3>" }
            else if line.hasPrefix("## ") { html += "<h2>\(esc(String(line.dropFirst(3))))</h2>" }
            else if line.hasPrefix("# ") { html += "<h1>\(esc(String(line.dropFirst(2))))</h1>" }
            else if line.hasPrefix("> ") { html += "<div><i>\(esc(String(line.dropFirst(2))))</i></div>" }
            else if isItem {
                if !inList { html += "<ul>"; inList = true }
                var item = line.replacingOccurrences(of: #"^(- |\* |\d+\. )"#, with: "", options: .regularExpression)
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                if item.hasPrefix("[x] ") { item = "☑ " + item.dropFirst(4) }
                html += "<li>\(esc(item))</li>"
            }
            else if line.isEmpty { html += "" }
            else if line.hasPrefix("---") { html += "<hr>" }
            else { html += "<div>\(esc(line))</div>" }
        }
        if inList { html += "</ul>" }
        return html
    }
}

// MARK: - Datei-basierte Ziele

public struct MarkdownDestination: Destination {
    public static let id = "markdown"

    public init() {}

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(AppInfo.name)
    }

    public func export(_ p: ExportPayload) async throws -> String? {
        let folder = p.settings.markdownFolderPath.isEmpty ? Self.defaultFolder : URL(fileURLWithPath: p.settings.markdownFolderPath)
        let sub = p.category.map { folder.appendingPathComponent($0.name) } ?? folder
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let url = sub.appendingPathComponent(MarkdownDocument.fileName(p))
        try MarkdownDocument.build(p, frontmatter: true).write(to: url, atomically: true, encoding: .utf8)
        return url.absoluteString
    }
}

public struct ObsidianDestination: Destination {
    public static let id = "obsidian"

    public init() {}

    public func export(_ p: ExportPayload) async throws -> String? {
        guard !p.settings.obsidianVaultPath.isEmpty else { throw DestinationNotConfigured(hint: "Noch kein Obsidian-Vault ausgewählt.") }
        var folder = URL(fileURLWithPath: p.settings.obsidianVaultPath)
        if !p.settings.obsidianFolder.isEmpty { folder.appendPathComponent(p.settings.obsidianFolder) }
        if let c = p.category { folder.appendPathComponent(c.name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(MarkdownDocument.fileName(p))
        try MarkdownDocument.build(p, frontmatter: true).write(to: url, atomically: true, encoding: .utf8)
        var comps = URLComponents(string: "obsidian://open")!
        comps.queryItems = [URLQueryItem(name: "path", value: url.path)]
        return comps.url?.absoluteString
    }
}
