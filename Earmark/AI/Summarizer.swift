import Foundation

struct Summary: Codable {
    var title: String
    var markdown: String        // ohne Titelzeile
    var taskCount: Int
    var provider: String

    static func parse(_ raw: String, provider: String, fallbackTitle: String) -> Summary {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Manche Modelle packen alles in einen ```markdown-Block
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```[a-zA-Z]*\n"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\n```\s*$"#, with: "", options: .regularExpression)
        }
        var lines = text.components(separatedBy: "\n")
        var title = fallbackTitle
        if let idx = lines.firstIndex(where: { $0.hasPrefix("# ") }), idx < 3 {
            title = String(lines[idx].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.removeSubrange(0...idx)
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let tasks = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") }.count
        return Summary(title: String(title.prefix(120)), markdown: body, taskCount: tasks, provider: provider)
    }
}

struct SummaryContext {
    var category: RecordingCategory?
    var titleHint: String
    var sourceApp: String?
    var date: Date
    var duration: TimeInterval
    var hasSpeakers: Bool
    var language: String
}

/// Erstellt aus dem Transkript eine strukturierte Zusammenfassung.
/// Sehr lange Transkripte werden abschnittsweise verdichtet (Map-Reduce).
struct Summarizer {
    let client: LLMClient
    let chunkCharacters: Int
    let providerName: String

    func summarize(transcript: String, context: SummaryContext,
                   progress: @escaping (Double) -> Void) async throws -> Summary {
        var material = transcript
        var isNotes = false

        if material.count > chunkCharacters {
            var round = 0
            while material.count > chunkCharacters && round < 4 {
                let chunks = Self.split(material, max: chunkCharacters)
                var notes: [String] = []
                for (i, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    let part = try await client.complete(system: mapSystem(context),
                                                         prompt: "Teil \(i + 1) von \(chunks.count):\n\n\(chunk)")
                    notes.append(part)
                    progress(0.85 * Double(i + 1) / Double(chunks.count) / Double(round + 1))
                }
                material = notes.joined(separator: "\n\n")
                isNotes = true
                round += 1
            }
        }

        let raw = try await client.complete(system: finalSystem(context), prompt: finalPrompt(material, context, isNotes: isNotes))
        progress(1)
        return Summary.parse(raw, provider: providerName, fallbackTitle: context.titleHint.isEmpty ? "Aufnahme" : context.titleHint)
    }

    // MARK: Prompts

    private func mapSystem(_ c: SummaryContext) -> String {
        """
        Du verdichtest einen Abschnitt eines langen, automatisch erstellten Transkripts zu ausführlichen Stichpunkt-Notizen auf \(c.language).
        Behalte alle inhaltlich wichtigen Punkte: Themen (mit Zeitmarke [hh:mm:ss] am Anfang), Aussagen, Zahlen, Namen,
        Entscheidungen, Aufgaben (wer, bis wann), Begriffe, Hinweise auf Prüfungen oder Fristen.
        Erfinde nichts. Keine Einleitung, kein Schlusssatz.
        """
    }

    private func finalSystem(_ c: SummaryContext) -> String {
        var s = """
        Du bist ein präziser, sachlicher Protokollant. Du erstellst aus einem automatisch erstellten Transkript eine
        gut strukturierte Zusammenfassung auf \(c.language) im Markdown-Format.

        Formatregeln:
        - Erste Zeile: "# " gefolgt von einem prägnanten Titel (max. 80 Zeichen).
        - Danach Abschnitte mit "## Überschrift". Innerhalb der Abschnitte Stichpunkte mit "- ".
        - Aufgaben IMMER als Checkliste: "- [ ] Aufgabe (Person, Frist)" – Person/Frist nur, wenn genannt.
        - Bei Themen die Zeitmarke im Format [hh:mm:ss] angeben, an der das Thema beginnt.
        - Keine Einleitung, keine Schlussbemerkung, keine Tabellen, kein Codeblock.

        Inhaltsregeln:
        - Nutze ausschließlich Inhalte aus dem Material. Erfinde nichts; Unklares mit "(unklar)" markieren.
        - Das Transkript enthält Erkennungsfehler: Korrigiere offensichtlich falsch erkannte Fachbegriffe und Namen stillschweigend.
        - Leere Abschnitte weglassen.
        """
        if c.hasSpeakers {
            s += "\n- Sprecher: \"Ich\" ist die Person, die aufnimmt; \"Andere\" sind die Gesprächspartner."
        }
        return s
    }

    private func finalPrompt(_ material: String, _ c: SummaryContext, isNotes: Bool) -> String {
        let df = DateFormatter()
        df.dateStyle = .full; df.timeStyle = .short
        df.locale = Locale(identifier: "de_DE")
        var p = ""
        if let cat = c.category {
            p += "Kategorie: \(cat.name)\nAnweisungen für diese Kategorie:\n\(cat.instructions)\n\n"
        }
        p += "Datum: \(df.string(from: c.date))\n"
        p += "Dauer: ca. \(Int(c.duration / 60)) Minuten\n"
        if let app = c.sourceApp { p += "Aufgenommen in: \(app)\n" }
        if !c.titleHint.isEmpty { p += "Titel/Kontext vom Nutzer: \(c.titleHint)\n" }
        p += isNotes
            ? "\nDas folgende Material sind bereits verdichtete Notizen aus dem vollständigen Transkript, in zeitlicher Reihenfolge:\n\n"
            : "\nTranskript:\n\n"
        p += material
        return p
    }

    static func split(_ text: String, max: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            if current.count + line.count + 1 > max, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            if line.count > max {
                var rest = Substring(line)
                while rest.count > max {
                    chunks.append(String(rest.prefix(max)))
                    rest = rest.dropFirst(max)
                }
                current = String(rest)
            } else {
                current += (current.isEmpty ? "" : "\n") + line
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
