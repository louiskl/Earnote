import Foundation

/// Notion über die offizielle API (interne Integration).
struct NotionDestination: Destination {
    static let id = "notion"
    private static let api = "https://api.notion.com/v1"
    private static let version = "2022-06-28"

    private static func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let token = Keychain.notionToken, !token.isEmpty else { throw DestinationNotConfigured(hint: "Notion ist noch nicht verbunden. In den Einstellungen unter „Ziele“ verbinden.") }
        do {
            return try await HTTP.json(api + path, method: method,
                                       headers: ["Authorization": "Bearer \(token)", "Notion-Version": version], body: body)
        } catch let e as LLMError where e.message.contains("object_not_found") || e.message.contains("HTTP 404") {
            throw LLMError(message: "Notion findet die Seite/Datenbank nicht. Bitte die Seite in Notion über „•••“ › „Verbindungen“ mit deiner Integration teilen.")
        } catch let e as LLMError where e.message.contains("HTTP 401") {
            throw LLMError(message: "Der Notion-Schlüssel ist ungültig.")
        }
    }

    // MARK: Einrichtung

    static func extractID(from link: String) -> String? {
        let hex = link.replacingOccurrences(of: "-", with: "")
        guard let regex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{32}") else { return nil }
        let matches = regex.matches(in: hex, range: NSRange(hex.startIndex..., in: hex))
        guard let last = matches.last, let r = Range(last.range, in: hex) else { return nil }
        return String(hex[r]).lowercased()
    }

    static func testToken() async throws -> String {
        let me = try await call("GET", "/users/me")
        return (me["bot"] as? [String: Any]).flatMap { ($0["workspace_name"] as? String) } ?? (me["name"] as? String ?? "Notion")
    }

    /// Legt unter der angegebenen Seite eine Datenbank mit dem App-Namen an.
    static func createDatabase(parentLink: String, categories: [RecordingCategory]) async throws -> (id: String, url: String) {
        guard let parent = extractID(from: parentLink) else {
            throw LLMError(message: "Im Link wurde keine Notion-Seiten-ID gefunden.")
        }
        let colors = ["blue", "purple", "green", "orange", "red", "pink", "yellow", "gray"]
        let options = categories.enumerated().map { ["name": $0.element.name, "color": colors[$0.offset % colors.count]] }
        let db = try await call("POST", "/databases", [
            "parent": ["type": "page_id", "page_id": parent],
            "icon": ["type": "emoji", "emoji": "🎙️"],
            "title": [["type": "text", "text": ["content": AppInfo.name]]],
            "properties": [
                "Name": ["title": [:] as [String: Any]],
                "Datum": ["date": [:] as [String: Any]],
                "Kategorie": ["select": ["options": options]],
                "Quelle": ["rich_text": [:] as [String: Any]],
                "Dauer (Min)": ["number": [:] as [String: Any]],
                "Aufgaben": ["number": [:] as [String: Any]],
                "Status": ["select": ["options": [["name": "Neu", "color": "yellow"], ["name": "Erledigt", "color": "green"]]]],
            ],
        ])
        guard let id = db["id"] as? String else { throw LLMError(message: "Notion hat keine Datenbank-ID zurückgegeben") }
        return (id, db["url"] as? String ?? "")
    }

    // MARK: Export

    func export(_ p: ExportPayload) async throws -> String? {
        guard !p.settings.notionDatabaseID.isEmpty else { throw LLMError(message: "Notion-Datenbank ist nicht eingerichtet") }

        var blocks: [[String: Any]] = [[
            "object": "block", "type": "callout",
            "callout": ["rich_text": Self.richText(MarkdownDocument.metaLine(p)),
                        "icon": ["type": "emoji", "emoji": "🗓️"], "color": "gray_background"],
        ]]
        if let s = p.summary { blocks += Self.blocks(fromMarkdown: s.markdown) }

        var props: [String: Any] = [
            "Name": ["title": Self.richText(String(p.title.prefix(200)))],
            "Datum": ["date": ["start": ISO8601DateFormatter.string(from: p.recording.startedAt, timeZone: .current,
                                                                      formatOptions: [.withInternetDateTime])]],
            "Dauer (Min)": ["number": Int(p.recording.duration / 60)],
            "Aufgaben": ["number": p.summary?.taskCount ?? 0],
            "Status": ["select": ["name": "Neu"]],
        ]
        if let c = p.category { props["Kategorie"] = ["select": ["name": c.name]] }
        if let app = p.recording.sourceApp { props["Quelle"] = ["rich_text": Self.richText(app)] }

        let page = try await Self.call("POST", "/pages", [
            "parent": ["database_id": p.settings.notionDatabaseID],
            "icon": ["type": "emoji", "emoji": "🎙️"],
            "properties": props,
            "children": Array(blocks.prefix(100)),
        ])
        guard let pageID = page["id"] as? String else { throw LLMError(message: "Notion hat keine Seiten-ID zurückgegeben") }
        _ = try await Self.append(pageID, Array(blocks.dropFirst(100)))

        if p.includeTranscript {
            let toggle: [String: Any] = [
                "object": "block", "type": "toggle",
                "toggle": ["rich_text": Self.richText("Vollständiges Transkript", bold: true)],
            ]
            let created = try await Self.append(pageID, [toggle])
            if let toggleID = created.first?["id"] as? String {
                let paragraphs = p.transcript.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { Self.block("paragraph", Self.richText($0)) }
                _ = try await Self.append(toggleID, paragraphs)
            }
        }
        return page["url"] as? String
    }

    private static func append(_ parent: String, _ blocks: [[String: Any]]) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        var index = 0
        while index < blocks.count {
            let batch = Array(blocks[index..<min(index + 100, blocks.count)])
            let res = try await call("PATCH", "/blocks/\(parent)/children", ["children": batch])
            results += res["results"] as? [[String: Any]] ?? []
            index += 100
            try await Task.sleep(nanoseconds: 350_000_000)
        }
        return results
    }

    // MARK: Markdown → Notion-Blöcke

    static func block(_ type: String, _ richText: [[String: Any]], extra: [String: Any] = [:]) -> [String: Any] {
        var content: [String: Any] = ["rich_text": richText]
        extra.forEach { content[$0.key] = $0.value }
        return ["object": "block", "type": type, type: content]
    }

    /// Text mit **fett** in Notion-Rich-Text umwandeln (max. 2000 Zeichen je Element).
    static func richText(_ text: String, bold: Bool = false) -> [[String: Any]] {
        var out: [[String: Any]] = []
        let parts = text.components(separatedBy: "**")
        for (i, part) in parts.enumerated() where !part.isEmpty {
            let isBold = bold || i % 2 == 1
            var rest = Substring(part)
            while !rest.isEmpty {
                let piece = rest.prefix(1900)
                rest = rest.dropFirst(piece.count)
                out.append(["type": "text", "text": ["content": String(piece)], "annotations": ["bold": isBold]])
            }
        }
        return Array(out.prefix(100))
    }

    static func blocks(fromMarkdown md: String) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        for raw in md.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var b: [String: Any]
            if line.hasPrefix("### ") {
                b = block("heading_3", richText(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                b = block("heading_2", richText(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                b = block("heading_1", richText(String(line.dropFirst(2))))
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                b = block("to_do", richText(String(line.dropFirst(6))), extra: ["checked": !line.hasPrefix("- [ ]")])
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                b = block("bulleted_list_item", richText(String(line.dropFirst(2))))
            } else if let r = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                b = block("numbered_list_item", richText(String(line[r.upperBound...])))
            } else if line.hasPrefix("> ") {
                b = block("quote", richText(String(line.dropFirst(2))))
            } else if line == "---" {
                b = ["object": "block", "type": "divider", "divider": [String: Any]()]
            } else {
                b = block("paragraph", richText(line))
            }
            // Eingerückte Listenpunkte an den vorherigen Punkt hängen (eine Ebene)
            let listTypes = ["bulleted_list_item", "numbered_list_item", "to_do"]
            if indent >= 2, let type = b["type"] as? String, listTypes.contains(type),
               let last = blocks.last, let lastType = last["type"] as? String, listTypes.contains(lastType),
               var content = last[lastType] as? [String: Any] {
                var children = content["children"] as? [[String: Any]] ?? []
                children.append(b)
                content["children"] = children
                blocks[blocks.count - 1][lastType] = content
                continue
            }
            blocks.append(b)
        }
        return blocks
    }
}
