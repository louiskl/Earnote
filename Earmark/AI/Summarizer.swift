import Foundation

struct Summary: Codable {
    var title: String
    var markdown: String        // ohne Titelzeile
    var taskCount: Int
    var provider: String

    /// Der erste richtige Absatz (ohne Überschriften und Listen) – als Vorschau in der Aufnahmeliste.
    var preview: String? {
        let paragraph = markdown.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("- ") && !$0.hasPrefix("* ") }
        guard let paragraph else { return nil }
        let plain = paragraph.replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
        return String(plain.prefix(220))
    }

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

/// Notizen als feste Felder – für Modelle, die strukturiert antworten können (Apple Intelligence).
struct NotesDraft {
    struct Topic { var heading: String; var points: [String] }
    /// Art der Aufnahme, wie das Modell sie erkannt hat (z. B. "Video oder Vortrag")
    var kind: String = ""
    var title: String
    var summary: String
    var topics: [Topic]
    var decisions: [String]
    var tasks: [String]
    var openQuestions: [String]

    static let passiveKind = "Video oder Vortrag"

    func summary(provider: String, fallbackTitle: String, showTopics: Bool) -> Summary {
        var md = [summary.trimmingCharacters(in: .whitespacesAndNewlines)]
        // Kleine Modelle wiederholen Aussagen gern in mehreren Abschnitten – jede nur einmal zeigen.
        var seen = Set<String>()
        func unique(_ items: [String]) -> [String] {
            items.map(Self.clean).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        }
        func section(_ heading: String, _ lines: [String], prefix: String = "- ") {
            guard !lines.isEmpty else { return }
            md.append("## \(heading)\n" + lines.map { prefix + $0 }.joined(separator: "\n"))
        }
        // Wer ein Video oder einen Vortrag aufnimmt, bekommt dort keine Aufgaben zugeteilt
        let passive = kind == Self.passiveKind
        let taskLines = passive ? [] : unique(tasks)
        let decisionLines = passive ? [] : unique(decisions)
        if showTopics {
            // „Zusammenfassung“, „Fazit“ usw. wiederholen nur die Kurzfassung
            let recap = ["zusammenfassung", "kurzfassung", "fazit", "abschluss", "schluss", "ergebnis"]
            for t in topics where !recap.contains(Self.clean(t.heading).lowercased()) {
                section(Self.clean(t.heading), unique(t.points))
            }
        } else if taskLines.isEmpty {
            // Sehr kurz und ohne Aufgaben (z. B. ein kurzer Clip): Inhalt als schlichte Liste ohne Zwischenüberschriften.
            // Mit Aufgaben (typische Sprachnotiz) tragen die Aufgaben den Inhalt, sonst stünde alles doppelt da.
            let points = unique(topics.flatMap(\.points))
            if !points.isEmpty { md.append(points.map { "- " + $0 }.joined(separator: "\n")) }
        }
        section("Entscheidungen", decisionLines)
        section("Aufgaben", taskLines, prefix: "- [ ] ")
        section("Offene Fragen", unique(openQuestions))
        let cleanTitle = Self.clean(title).trimmingCharacters(in: CharacterSet(charactersIn: "#* "))
        return Summary(title: String((cleanTitle.isEmpty ? fallbackTitle : cleanTitle).prefix(120)),
                       markdown: md.filter { !$0.isEmpty }.joined(separator: "\n\n"),
                       taskCount: taskLines.count,
                       provider: provider)
    }

    /// Entfernt Aufzählungszeichen und Checkboxen, die das Modell selbst mitliefert.
    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?:[-*•]\s*)?(?:\[[ xX]?\]\s*)?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol StructuredNotesClient: LLMClient {
    func completeNotes(system: String, prompt: String) async throws -> NotesDraft
}

/// Fortschritt, der nur vorwärts läuft – auch über Verdichtungsrunden und Neuversuche hinweg.
final class MonotonicProgress: @unchecked Sendable {
    private let report: (Double) -> Void
    private let lock = NSLock()
    private var value = 0.0

    init(_ report: @escaping (Double) -> Void) { self.report = report }

    var current: Double { lock.lock(); defer { lock.unlock() }; return value }

    func set(_ newValue: Double) {
        lock.lock()
        guard newValue > value else { lock.unlock(); return }
        value = min(1, newValue)
        let v = value
        lock.unlock()
        report(v)
    }

    /// Lässt den Balken während eines Schritts ohne Zwischenstand weiterlaufen: anfangs zügig, dann immer
    /// langsamer, ohne das Ziel zu erreichen. Läuft, bis der zurückgegebene Task abgebrochen wird.
    func creep(to target: Double, typicalSeconds: Double) -> Task<Void, Never> {
        let start = current
        return Task.detached { [self] in
            var elapsed = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                elapsed += 0.5
                set(start + (target - start) * (1 - exp(-elapsed / typicalSeconds)))
            }
        }
    }
}

/// Anfrage passte nicht ins Kontextfenster des Modells – mit kleineren Abschnitten erneut versuchen.
struct ContextWindowExceeded: LocalizedError {
    var errorDescription: String? { "Die Aufnahme ist für das gewählte KI-Modell zu lang." }
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
        let tracker = MonotonicProgress(progress)
        var material = transcript
        var isNotes = false
        var limit = chunkCharacters
        let words = Self.spokenWordCount(transcript)

        // Verdichtungsrunden laufen bis 80 %. Wie viele Runden nötig sind, steht vorher nicht fest –
        // deshalb bekommt jede Runde drei Viertel des noch freien Bereichs.
        var roundStart = 0.0
        var round = 0
        while true {
            if material.count > limit, round < 4 {
                let roundEnd = roundStart + (0.8 - roundStart) * 0.75
                let condensed = try await condense(material, limit: limit, context: context) { done, total in
                    tracker.set(roundStart + (roundEnd - roundStart) * Double(done) / Double(total))
                }
                roundStart = roundEnd
                round += 1
                isNotes = true
                // Wird das Material nicht kürzer, bringen weitere Runden nichts außer Wartezeit.
                let shrank = condensed.count < Int(Double(material.count) * 0.8)
                material = condensed
                if !shrank { round = 4 }
                continue
            }

            do {
                return try await finalNotes(material, context: context, isNotes: isNotes, words: words, progress: tracker)
            } catch is ContextWindowExceeded where limit > 1_500 {
                // Nur den letzten Schritt wiederholen: kleinere Abschnitte, aber nicht alles von vorn.
                limit /= 2
                round = min(round, 3)
            }
        }
    }

    /// Eine Verdichtungsrunde: Das Material wird in Abschnitte geteilt und jeder zu Notizen zusammengefasst.
    private func condense(_ material: String, limit: Int, context: SummaryContext,
                          progress: (Int, Int) -> Void) async throws -> String {
        let chunks = Self.split(material, max: limit)
        var notes: [String] = []
        for (i, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            notes.append(try await condenseChunk(chunk, part: i + 1, of: chunks.count, context: context))
            progress(i + 1, chunks.count)
        }
        return notes.joined(separator: "\n\n")
    }

    /// Passt ein Abschnitt trotzdem nicht ins Kontextfenster, wird nur dieser Abschnitt halbiert.
    private func condenseChunk(_ chunk: String, part: Int, of total: Int,
                               context: SummaryContext) async throws -> String {
        do {
            return try await client.complete(system: mapSystem(context),
                                             prompt: "Teil \(part) von \(total):\n\n\(chunk)")
        } catch is ContextWindowExceeded where chunk.count > 1_500 {
            let halves = Self.split(chunk, max: chunk.count / 2 + 1)
            var notes: [String] = []
            for half in halves {
                notes.append(try await condenseChunk(half, part: part, of: total, context: context))
            }
            return notes.joined(separator: "\n\n")
        }
    }

    private func finalNotes(_ material: String, context: SummaryContext, isNotes: Bool, words: Int,
                            progress: MonotonicProgress) async throws -> Summary {
        let prompt = finalPrompt(material, context, isNotes: isNotes, words: words)
        let fallbackTitle = context.titleHint.isEmpty ? "Aufnahme" : context.titleHint
        // Der letzte Schritt meldet keinen Zwischenstand. Damit der Balken nicht minutenlang steht,
        // läuft er geschätzt weiter, bis die Notiz fertig ist.
        let estimate = progress.creep(to: 0.97, typicalSeconds: 20 + Double(material.count) / 250)
        defer { estimate.cancel() }

        // Kleine lokale Modelle halten Formatvorgaben schlecht ein. Sie füllen stattdessen feste Felder aus,
        // aus denen hier sauberes Markdown entsteht (keine leeren Abschnitte, Aufgaben immer als Checkliste).
        if let structured = client as? StructuredNotesClient {
            let draft = try await structured.completeNotes(system: structuredSystem(context), prompt: prompt)
            progress.set(1)
            return draft.summary(provider: providerName, fallbackTitle: fallbackTitle, showTopics: words >= 150)
        }
        let raw = try await client.complete(system: markdownSystem(context), prompt: prompt)
        progress.set(1)
        return Summary.parse(raw, provider: providerName, fallbackTitle: fallbackTitle)
    }

    // MARK: Prompts

    private func mapSystem(_ c: SummaryContext) -> String {
        """
        Du bekommst einen Abschnitt aus dem automatisch erstellten Transkript einer längeren Aufnahme. \
        Fasse ihn auf \(c.language) zu ausführlichen Arbeitsnotizen zusammen, aus denen später die endgültigen Notizen entstehen.

        - Gib den Inhalt sinngemäß in ganzen Sätzen wieder, mit Begründungen, Beispielen, Zahlen und Namen.
        - Fasse dich dabei kurz: Die Notizen dürfen höchstens ein Drittel so lang sein wie der Abschnitt.
        - Hat jemand ausdrücklich etwas entschieden, vereinbart oder eine Aufgabe übernommen, halte auch das fest (wer, bis wann).
        - Setze vor jedes neue Thema die Zeitmarke aus dem Transkript, z. B. "[00:12:30] Thema".
        - Schreibe neutral in der dritten Person. Lass Smalltalk, Füllwörter und Wiederholungen weg.
        - Nur, was im Abschnitt steht. Nichts erfinden, nichts bewerten. Keine Einleitung, kein Schlusssatz.
        """
    }

    /// Worum es geht – gilt für beide Ausgabeformate.
    private func intro(_ c: SummaryContext) -> String {
        """
        Du schreibst Notizen zu einer Aufnahme – einem Meeting, Gespräch, Telefonat, einer Vorlesung, einem Video oder einer Sprachnotiz. \
        Schreib sie so, wie ein aufmerksamer, erfahrener Mensch, der dabei war, sie für sich und andere festhalten würde: \
        Wer sie liest, soll verstehen, worum es ging, was gesagt wurde und was daraus folgt, ohne die Aufnahme zu hören. \
        Sprache der Notizen: \(c.language).
        """
    }

    /// Inhalt, Stil und Genauigkeit – gilt für beide Ausgabeformate.
    private func contentRules(_ c: SummaryContext) -> String {
        var s = """
        Inhalt
        - Erfasse zuerst das Ganze: Anlass, Thema, Beteiligte, Ergebnis.
        - Gib die Inhalte sinngemäß wieder: die wichtigen Aussagen mit ihren Begründungen, Beispiele, Zahlen, Namen und Termine. \
        Zusammenhänge gehören dazu, nicht nur Schlagworte.
        - Gewichte wie ein Mensch: Wichtiges ausführlich, Nebensächliches knapp, Smalltalk, Füllwörter und Wiederholungen gar nicht.
        - Der Umfang richtet sich nach dem Material (siehe "Umfang" in der Nachricht). Eine kurze Aufnahme ergibt eine kurze Notiz. \
        Nichts doppelt aufschreiben.
        - Eine Aufgabe ist nur, was jemand in der Aufnahme ausdrücklich übernommen, zugesagt oder verlangt hat, oder was sich \
        die aufnehmende Person in einer Sprachnotiz vornimmt. Leite keine Aufgaben aus dem Thema ab. \
        Gibt es keine Entscheidungen, Aufgaben oder offenen Fragen, lass diese Teile ganz weg.

        Stil
        - Neutral und sachlich, unpersönlich oder in der dritten Person ("Vereinbart wurde …", "Anna schlägt vor …"). \
        Keine Wertungen, keine eigene Meinung, keine Ratschläge.
        - Klare, vollständige Sätze, wo es um Zusammenhänge geht; knappe Stichpunkte für Aufzählungen.
        - Wörtliche Zitate nur, wenn die genaue Formulierung wichtig ist.

        Genauigkeit
        - Nur, was im Material steht. Nichts ergänzen oder erfinden; Unsicheres mit "(unklar)" kennzeichnen oder weglassen.
        - Kategorie und Dateiname sind nur Hinweise. Passt der Inhalt nicht dazu (etwa ein Video, Podcast oder Vortrag \
        statt eines Meetings), richte dich nach dem, was tatsächlich zu hören ist, und nenne es auch so.
        - Das Transkript wurde automatisch erstellt und enthält Hörfehler. Offensichtlich falsch erkannte Wörter, Namen und \
        Fachbegriffe korrigierst du stillschweigend. Ist das Transkript in einer anderen Sprache, übersetze sinngemäß.
        """
        if c.hasSpeakers {
            s += """

            - Sprecherangaben: "Ich" ist die Person, die aufgenommen hat, "Andere" sind die übrigen Beteiligten. \
            Die Zuordnung ist automatisch und nicht immer richtig. Übernimm "Ich"/"Andere" nicht in die Notizen; \
            nenne Personen beim Namen, wenn Namen fallen, sonst formuliere neutral.
            """
        }
        return s
    }

    private func markdownSystem(_ c: SummaryContext) -> String {
        """
        \(intro(c)) Format: Markdown.

        Aufbau
        - Erste Zeile: "# " und ein konkreter Titel, der den Inhalt benennt (höchstens 70 Zeichen; kein Datum, nicht nur "Meeting" oder "Notiz").
        - Danach ohne Überschrift eine Kurzfassung in 1–3 Sätzen: Worum ging es, was ist herausgekommen?
        - Dann der Inhalt, gegliedert nach den Themen, die tatsächlich vorkamen ("## Thema"). Keine vorgefertigten Rubriken. \
        Unter jedem Thema kurze Absätze oder Stichpunkte, je nachdem, was besser lesbar ist. \
        Bei sehr kurzen Aufnahmen keine Zwischenüberschriften.
        - Am Ende, nur wenn vorhanden: "## Entscheidungen", "## Aufgaben", "## Offene Fragen".
        - Jede Aufgabe steht in einer eigenen Zeile, die mit "- [ ] " beginnt. Zuständige Person und Frist nur, wenn sie genannt wurden.
        - Bei längeren Aufnahmen darf hinter einer Themenüberschrift die Zeitmarke stehen, an der das Thema beginnt, z. B. "## Budget [00:14:05]".
        - Keine Einleitung ("Hier ist …"), kein Schlusswort oder Fazit, keine Tabellen, keine Codeblöcke, keine Emojis.

        \(contentRules(c))
        """
    }

    /// Bewusst kurz: Kleine lokale Modelle befolgen wenige klare Regeln besser als viele.
    private func structuredSystem(_ c: SummaryContext) -> String {
        var s = """
        Du schreibst Notizen zu einer Aufnahme (Meeting, Gespräch, Vorlesung, Video oder Sprachnotiz), \
        so wie ein aufmerksamer Mensch, der dabei war. Sprache der Notizen: \(c.language).

        Regeln:
        - Gib wieder, was gesagt wurde: die Aussagen mit ihren Begründungen, Zahlen, Namen und Terminen, in ganzen, neutralen Sätzen.
        - Nur, was im Transkript steht. Nichts erfinden, nichts bewerten, keine Ratschläge.
        - Richte dich nach dem tatsächlichen Inhalt, nicht nach der Kategorie: Ein Video oder Vortrag ist kein Meeting.
        - Aufgaben nur, wenn jemand sie ausdrücklich übernommen hat oder sich vornimmt.
        - Das Transkript wurde automatisch erstellt und enthält Hörfehler. Korrigiere offensichtliche Fehler stillschweigend.
        """
        if c.hasSpeakers {
            s += "\n- \"Ich\" ist die Person, die aufgenommen hat; \"Andere\" sind die übrigen Beteiligten. "
                + "Bei Aufgaben der aufnehmenden Person schreibst du \"ich\"."
        }
        return s
    }

    private func finalPrompt(_ material: String, _ c: SummaryContext, isNotes: Bool, words: Int) -> String {
        let df = DateFormatter()
        df.dateStyle = .full; df.timeStyle = .short
        df.locale = Locale(identifier: "de_DE")
        var p = ""
        if let cat = c.category {
            p += "Vom Nutzer gewählte Kategorie (kann unpassend sein): \(cat.name)\n"
            let hints = cat.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hints.isEmpty { p += "Hinweise für diese Kategorie (ergänzen die allgemeinen Regeln):\n\(hints)\n" }
            p += "\n"
        }
        p += "Datum: \(df.string(from: c.date))\n"
        p += "Dauer: ca. \(max(1, Int((c.duration / 60).rounded()))) Minuten\n"
        if let app = c.sourceApp { p += "Aufgenommen in: \(app)\n" }
        if !c.titleHint.isEmpty { p += "Name der Aufnahme bzw. Datei: \(c.titleHint)\n" }
        p += "Umfang: \(Self.lengthGuidance(words: words))\n"
        p += isNotes
            ? "\nDas folgende Material sind bereits verdichtete Notizen aus dem vollständigen Transkript, in zeitlicher Reihenfolge:\n\n"
            : "\nTranskript:\n\n"
        p += material
        return p
    }

    /// Wie ausführlich die Notizen werden sollen – gemessen am gesprochenen Text, nicht an der Aufnahmedauer
    /// (eine lange Aufnahme mit viel Stille ergibt trotzdem nur eine kurze Notiz).
    static func lengthGuidance(words: Int) -> String {
        switch words {
        case ..<150:
            return "Sehr kurz (ca. \(words) gesprochene Wörter). Nur Titel, eine Kurzfassung in ein bis drei Sätzen und, "
                + "falls vorhanden, Aufgaben. Keine weitere Gliederung."
        case ..<700:
            return "Kurz (ca. \(words) Wörter). Eine kompakte Notiz: Kurzfassung und das Wesentliche in wenigen Punkten; "
                + "nach Themen gliedern nur, wenn es mehrere klar getrennte Themen gibt."
        case ..<3_000:
            return "Mittel (ca. \(words) Wörter). Gliedere nach den Hauptthemen."
        case ..<12_000:
            return "Lang (ca. \(words) Wörter). Gliedere ausführlich nach Themen und gib die Inhalte detailliert wieder."
        default:
            return "Sehr lang (ca. \(words) Wörter). Gliedere ausführlich nach Themen, gib die Inhalte detailliert wieder "
                + "und setze Zeitmarken hinter die Themenüberschriften."
        }
    }

    /// Wörter im Transkript ohne Zeitmarken und Sprecherangaben.
    static func spokenWordCount(_ transcript: String) -> Int {
        transcript.split(whereSeparator: \.isWhitespace).filter { word in
            !(word.hasPrefix("[") && word.hasSuffix("]")) && word != "Ich:" && word != "Andere:"
        }.count
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
