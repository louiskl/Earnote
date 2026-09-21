import Foundation

/// Eine Übersicht über mehrere Aufnahmen eines Bereichs – der rote Faden eines Semesters
/// statt zwölf einzelner Mitschriften. Arbeitsgrundlage sind die fertigen Notizen, nicht die Transkripte:
/// Sie sind schon verdichtet, passen dadurch zusammen in ein Modell und enthalten das Wesentliche.
public enum PeriodSummary {
    /// Eine Notiz, die in die Übersicht eingeht
    public struct Source: Sendable {
        public let title: String
        public let date: Date
        public let markdown: String

        public init(title: String, date: Date, markdown: String) {
            self.title = title
            self.date = date
            self.markdown = markdown
        }
    }

    /// Notizen in der Reihenfolge, in der sie entstanden sind – mit Datum, damit das Modell
    /// eine Entwicklung erkennen kann („zuerst …, später …“).
    public static func material(_ sources: [Source], limit: Int) -> String {
        let sorted = sources.sorted { $0.date < $1.date }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        var out = ""
        for source in sorted {
            let block = "## \(source.title) (\(df.string(from: source.date)))\n\n\(source.markdown)\n\n"
            // Lieber weniger Termine vollständig als alle halb: abschneiden, sobald es nicht mehr passt
            if out.count + block.count > limit { break }
            out += block
        }
        return out.isEmpty ? String(sorted.first?.markdown.prefix(limit) ?? "") : out
    }

    /// Wie viele Notizen tatsächlich hineingepasst haben (für den Hinweis in der Oberfläche)
    public static func fittingCount(_ sources: [Source], limit: Int) -> Int {
        let sorted = sources.sorted { $0.date < $1.date }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        var used = 0
        var count = 0
        for source in sorted {
            used += "## \(source.title) (\(df.string(from: source.date)))\n\n\(source.markdown)\n\n".count
            if used > limit { break }
            count += 1
        }
        return max(1, count)
    }

    public static func system(language: String, subject: String, simple: Bool, extra: String) -> String {
        var s = t("""
        Du fasst mehrere Mitschriften desselben Fachs zu einer Übersicht zusammen – zum Wiederholen vor einer Prüfung.
        Schreibe eine zusammenhängende Übersicht, keine Aneinanderreihung der einzelnen Termine.

        Aufbau (Überschriften mit ##, lass weg, was leer bliebe):
        - Überblick: worum es in diesem Abschnitt ging, in drei bis fünf Sätzen
        - Themen: die großen Themen, jeweils mit den wichtigsten Begriffen, Zusammenhängen und Beispielen
        - Roter Faden: was aufeinander aufbaut und wie die Themen zusammenhängen
        - Prüfungshinweise: alles, was mehrfach betont wurde oder ausdrücklich als prüfungsrelevant genannt wurde
        - Offene Aufgaben: was noch zu tun ist, als Aufgaben mit "- [ ] "

        Regeln:
        - Nur, was in den Mitschriften steht. Nichts erfinden, nichts ergänzen.
        - Wiederholungen zusammenfassen statt mehrfach aufzuschreiben.
        - Die erste Zeile ist ein Titel mit "# " – Fach und Zeitraum.
        """)
        s += "\n\n" + t("Fach: \(subject)") + "\n" + t("Sprache: \(language)")
        if simple {
            s += "\n" + t("Schreibe einfach: kurze Sätze, alltägliche Wörter, Fachbegriffe beim ersten Mal erklären.")
        }
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { s += "\n\n" + t("Zusätzliche Anweisung: \(extra)") }
        return s
    }

    /// Erzeugt die Übersicht. Kommt nichts Brauchbares zurück, ist das Ergebnis nil –
    /// besser keine Übersicht als eine erfundene.
    public static func generate(client: any LLMClient, sources: [Source], subject: String, language: String,
                                simple: Bool = false, extra: String = "", limit: Int = 40_000,
                                providerName: String) async throws -> Summary? {
        guard !sources.isEmpty else { return nil }
        let text = material(sources, limit: limit)
        let prompt = t("Hier sind die Mitschriften:") + "\n\n" + text
        let raw = try await client.complete(system: system(language: language, subject: subject,
                                                           simple: simple, extra: extra),
                                            prompt: prompt)
        guard raw.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 else { return nil }
        return Summary.parse(raw, provider: providerName, fallbackTitle: subject)
    }
}
