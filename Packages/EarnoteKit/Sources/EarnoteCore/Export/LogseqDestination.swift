import Foundation

/// Logseq liest einen Ordner voller Markdown-Dateien, schreibt aber alles als Aufzählung:
/// Eigenschaften stehen als `schlüssel:: wert` im ersten Block, jede Zeile beginnt mit „- “.
public struct LogseqDestination: Destination {
    public static let id = "logseq"

    public init() {}

    public func export(_ p: ExportPayload) async throws -> String? {
        guard !p.settings.logseqGraphPath.isEmpty else {
            throw DestinationNotConfigured(hint: t("Logseq-Graph noch nicht ausgewählt"))
        }
        let pages = URL(fileURLWithPath: p.settings.logseqGraphPath).appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        let url = pages.appendingPathComponent(MarkdownDocument.fileName(p))
        try Self.document(p).write(to: url, atomically: true, encoding: .utf8)
        return url.absoluteString
    }

    /// Die Notiz in Logseq-Schreibweise. Überschriften bleiben Überschriften, alles andere wird zum Block.
    static func document(_ p: ExportPayload) -> String {
        var out = "title:: \(p.title)\n"
        let iso = ISO8601DateFormatter()
        out += "date:: \(iso.string(from: p.recording.startedAt))\n"
        if let c = p.category { out += "tags:: \(AppInfo.name.lowercased()), \(MarkdownDocument.tag(c.name))\n" }
        out += "duration:: \(Int(p.recording.duration / 60)) min\n\n"
        out += "- " + MarkdownDocument.metaLine(p) + "\n"
        if let summary = p.summary { out += blocks(summary.markdown) }
        if p.includeTranscript {
            out += "- ## \(t("Transkript"))\n"
            for line in p.transcript.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                out += "\t- \(line)\n"
            }
        }
        return out
    }

    /// Jede nicht leere Zeile wird ein Block; Unterpunkte bleiben eingerückt.
    private static func blocks(_ markdown: String) -> String {
        var out = ""
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let indent = String(repeating: "\t", count: min(3, (raw.prefix(while: { $0 == " " }).count) / 2))
            // Aufzählungen und Aufgaben behalten ihre Bedeutung, nur das Zeichen wechselt
            if line.hasPrefix("- [ ] ") || line.hasPrefix("* [ ] ") {
                out += "\(indent)- TODO \(line.dropFirst(6))\n"
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("* [x] ") || line.hasPrefix("- [X] ") {
                out += "\(indent)- DONE \(line.dropFirst(6))\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                out += "\(indent)- \(line.dropFirst(2))\n"
            } else {
                out += "\(indent)- \(line)\n"
            }
        }
        return out
    }
}

/// Aufgaben aus der Notiz als Todoist-Aufgaben – je Bereich ein Projekt.
public struct TodoistDestination: Destination {
    public static let id = "todoist"
    private static let api = "https://api.todoist.com/rest/v2"

    public init() {}

    public func export(_ p: ExportPayload) async throws -> String? {
        let tasks = NoteMarkdown.openTasks(p.summary?.markdown ?? "")
        guard !tasks.isEmpty else { return nil }
        guard let token = Keychain.todoistToken, !token.isEmpty else {
            throw DestinationNotConfigured(hint: t("Todoist-Schlüssel fehlt"))
        }
        let headers = ["Authorization": "Bearer \(token)"]
        let projectID = try await project(named: p.settings.todoistProject.isEmpty
                                          ? (p.category?.name ?? AppInfo.name)
                                          : p.settings.todoistProject, headers: headers)
        let note = t("Aus „\(p.title)“")
        for task in tasks {
            var body: [String: Any] = ["content": task, "description": note]
            if let projectID { body["project_id"] = projectID }
            _ = try await HTTP.json("\(Self.api)/tasks", headers: headers, body: body)
        }
        return nil
    }

    /// Vorhandenes Projekt suchen, sonst anlegen (nil = Eingang)
    private func project(named name: String, headers: [String: String]) async throws -> String? {
        var request = URLRequest(url: URL(string: "\(Self.api)/projects")!)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await HTTP.session.data(for: request)
        guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw DestinationNotConfigured(hint: t("Todoist-Schlüssel wird nicht akzeptiert"))
        }
        let projects = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        if let found = projects.first(where: { ($0["name"] as? String) == name }) {
            return found["id"] as? String
        }
        let created = try await HTTP.json("\(Self.api)/projects", headers: headers, body: ["name": name])
        return created["id"] as? String
    }
}
