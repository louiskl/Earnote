import AppKit
import Foundation

struct ExportPayload {
    var recording: Recording
    var category: RecordingCategory?
    var summary: Summary?
    var transcript: String
    var settings: DestinationSettings

    var title: String { summary?.title ?? recording.title }
    var includeTranscript: Bool { settings.includeTranscript && !transcript.isEmpty }
}

/// Das Ziel ist noch nicht fertig eingerichtet. Das ist kein Fehler der Aufnahme –
/// die Notizen sind fertig, nur dieses eine Ziel wird übersprungen.
struct DestinationNotConfigured: LocalizedError {
    let hint: String
    var errorDescription: String? { hint }
}

protocol Destination {
    /// Gibt optional einen Link zum erstellten Eintrag zurück.
    func export(_ payload: ExportPayload) async throws -> String?
}

struct DestinationInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let detail: String
}

enum Destinations {
    static let all: [DestinationInfo] = [
        DestinationInfo(id: NotionDestination.id, name: "Notion", symbol: "square.stack.3d.up.fill",
                        detail: "Neue Seite in einer Notion-Datenbank mit Kategorie, Datum und Aufgaben."),
        DestinationInfo(id: ObsidianDestination.id, name: "Obsidian", symbol: "diamond.fill",
                        detail: "Markdown-Notiz mit Eigenschaften in deinem Vault."),
        DestinationInfo(id: AppleNotesDestination.id, name: "Apple Notizen", symbol: "note.text",
                        detail: "Notiz im Ordner deiner Wahl, synchron über iCloud."),
        DestinationInfo(id: MarkdownDestination.id, name: "Markdown-Ordner", symbol: "folder.fill",
                        detail: "Eine .md-Datei pro Aufnahme – ideal für Backups, iCloud Drive oder andere Apps."),
        DestinationInfo(id: BearDestination.id, name: "Bear", symbol: "pawprint.fill",
                        detail: "Neue Notiz in Bear mit Tags."),
        DestinationInfo(id: CraftDestination.id, name: "Craft", symbol: "doc.richtext.fill",
                        detail: "Neues Dokument in einem Craft-Space."),
    ]

    static func info(_ id: String) -> DestinationInfo? { all.first { $0.id == id } }

    static func make(_ id: String) -> Destination? {
        switch id {
        case NotionDestination.id: return NotionDestination()
        case ObsidianDestination.id: return ObsidianDestination()
        case AppleNotesDestination.id: return AppleNotesDestination()
        case MarkdownDestination.id: return MarkdownDestination()
        case BearDestination.id: return BearDestination()
        case CraftDestination.id: return CraftDestination()
        default: return nil
        }
    }

    /// Fehlt noch etwas an der Einrichtung? (nil = bereit)
    static func setupProblem(_ id: String, _ s: DestinationSettings) -> String? {
        switch id {
        case NotionDestination.id:
            if Keychain.notionToken?.isEmpty ?? true { return "Notion-Schlüssel fehlt" }
            if s.notionDatabaseID.isEmpty { return "Notion-Datenbank noch nicht angelegt" }
        case ObsidianDestination.id:
            if s.obsidianVaultPath.isEmpty { return "Obsidian-Vault nicht ausgewählt" }
        case CraftDestination.id:
            if s.craftSpaceID.isEmpty { return "Craft-Space-ID fehlt" }
        case BearDestination.id:
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.shinyfrog.bear") == nil { return "Bear ist nicht installiert" }
        default: break
        }
        return nil
    }
}

// MARK: - Markdown-Dokument

enum MarkdownDocument {
    static func build(_ p: ExportPayload, frontmatter: Bool) -> String {
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

    static func metaLine(_ p: ExportPayload) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateStyle = .medium; df.timeStyle = .short
        var parts = [df.string(from: p.recording.startedAt), "\(Int(p.recording.duration / 60)) Min."]
        if let c = p.category { parts.insert(c.name, at: 0) }
        if let app = p.recording.sourceApp { parts.append(app) }
        return parts.joined(separator: " · ")
    }

    static func tag(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
    }

    static func fileName(_ p: ExportPayload) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HHmm"
        let clean = p.title.replacingOccurrences(of: #"[/\\:*?"<>|#^\[\]]"#, with: "", options: .regularExpression)
        return "\(df.string(from: p.recording.startedAt)) \(clean.prefix(80)).md"
    }

    /// Sehr einfache Markdown→HTML-Umwandlung (für Apple Notizen).
    static func html(_ markdown: String) -> String {
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

struct MarkdownDestination: Destination {
    static let id = "markdown"

    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(AppInfo.name)
    }

    func export(_ p: ExportPayload) async throws -> String? {
        let folder = p.settings.markdownFolderPath.isEmpty ? Self.defaultFolder : URL(fileURLWithPath: p.settings.markdownFolderPath)
        let sub = p.category.map { folder.appendingPathComponent($0.name) } ?? folder
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let url = sub.appendingPathComponent(MarkdownDocument.fileName(p))
        try MarkdownDocument.build(p, frontmatter: true).write(to: url, atomically: true, encoding: .utf8)
        return url.absoluteString
    }
}

struct ObsidianDestination: Destination {
    static let id = "obsidian"

    func export(_ p: ExportPayload) async throws -> String? {
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

// MARK: - App-basierte Ziele

struct AppleNotesDestination: Destination {
    static let id = "applenotes"

    func export(_ p: ExportPayload) async throws -> String? {
        var md = "# \(p.title)\n\n> \(MarkdownDocument.metaLine(p))\n\n"
        if let s = p.summary { md += s.markdown + "\n\n" }
        if p.includeTranscript { md += "## Transkript\n\n" + p.transcript }
        let html = MarkdownDocument.html(md)
        let folder = p.settings.appleNotesFolder.isEmpty ? AppInfo.name : p.settings.appleNotesFolder

        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let script = """
        tell application "Notes"
            set acc to default account
            if not (exists folder \(q(folder)) of acc) then
                make new folder at acc with properties {name:\(q(folder))}
            end if
            set n to make new note at folder \(q(folder)) of acc with properties {body:\(q(html))}
            return id of n
        end tell
        """
        return try await MainActor.run { () throws -> String? in
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
                throw LLMError(message: "Apple Notizen: \(msg). Bitte in Systemeinstellungen › Datenschutz › Automation erlauben.")
            }
            _ = result
            return nil
        }
    }
}

struct BearDestination: Destination {
    static let id = "bear"

    func export(_ p: ExportPayload) async throws -> String? {
        var payload = p
        if p.transcript.count > 150_000 { payload.settings.includeTranscript = false }
        let body = MarkdownDocument.build(payload, frontmatter: false)
            .components(separatedBy: "\n").dropFirst().joined(separator: "\n")   // Titel übergibt Bear separat
        var tags = p.settings.bearTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let c = p.category { tags.append("\(AppInfo.name.lowercased())/\(MarkdownDocument.tag(c.name))") }
        var comps = URLComponents(string: "bear://x-callback-url/create")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: p.title),
            URLQueryItem(name: "text", value: body),
            URLQueryItem(name: "tags", value: tags.joined(separator: ",")),
            URLQueryItem(name: "open_note", value: "no"),
            URLQueryItem(name: "show_window", value: "no"),
        ]
        guard let url = comps.url else { throw LLMError(message: "Bear-Link konnte nicht erstellt werden") }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        if !ok { throw LLMError(message: "Bear konnte nicht geöffnet werden") }
        return nil
    }
}

struct CraftDestination: Destination {
    static let id = "craft"

    func export(_ p: ExportPayload) async throws -> String? {
        guard !p.settings.craftSpaceID.isEmpty else { throw DestinationNotConfigured(hint: "Noch keine Craft-Space-ID eingetragen.") }
        var payload = p
        if p.transcript.count > 150_000 { payload.settings.includeTranscript = false }
        let body = MarkdownDocument.build(payload, frontmatter: false)
            .components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        var comps = URLComponents(string: "craftdocs://createdocument")!
        comps.queryItems = [
            URLQueryItem(name: "spaceId", value: p.settings.craftSpaceID),
            URLQueryItem(name: "title", value: p.title),
            URLQueryItem(name: "content", value: body),
            URLQueryItem(name: "folderId", value: ""),
        ]
        guard let url = comps.url else { throw LLMError(message: "Craft-Link konnte nicht erstellt werden") }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        if !ok { throw LLMError(message: "Craft konnte nicht geöffnet werden") }
        return nil
    }
}
