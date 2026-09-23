import Foundation

public struct Summary: Codable, Sendable {
    public var title: String
    public var markdown: String        // ohne Titelzeile
    public var taskCount: Int
    public var provider: String

    public init(title: String, markdown: String, taskCount: Int, provider: String) {
        self.title = title
        self.markdown = markdown
        self.taskCount = taskCount
        self.provider = provider
    }

    /// Der erste richtige Absatz (ohne Überschriften und Listen) – als Vorschau in der Aufnahmeliste.
    public var preview: String? {
        let paragraph = markdown.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("- ") && !$0.hasPrefix("* ") }
        guard let paragraph else { return nil }
        let plain = paragraph.replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
        return String(plain.prefix(220))
    }

    public static func parse(_ raw: String, provider: String, fallbackTitle: String) -> Summary {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Manche Modelle packen alles in einen ```markdown-Block
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```[a-zA-Z]*\n"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\n```\s*$"#, with: "", options: .regularExpression)
        }
        // Kleine Modelle setzen vor die Checkbox gern noch einen Spiegelstrich („- - [ ] …“) – dann fehlt das Kästchen
        var lines = text.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: #"^(\s*)[-*•]\s+(- \[[ xX]\])"#, with: "$1$2", options: .regularExpression)
        }
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
public struct NotesDraft: Sendable {
    public struct Topic: Sendable {
        public var heading: String
        public var points: [String]

        public init(heading: String, points: [String]) {
            self.heading = heading
            self.points = points
        }
    }
    /// Art der Aufnahme, wie das Modell sie erkannt hat (z. B. "Video oder Vortrag")
    public var kind: String = ""
    public var title: String
    public var summary: String
    public var topics: [Topic]
    public var decisions: [String]
    public var tasks: [String]
    public var openQuestions: [String]

    public init(kind: String = "", title: String, summary: String, topics: [Topic], decisions: [String],
                tasks: [String], openQuestions: [String]) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.topics = topics
        self.decisions = decisions
        self.tasks = tasks
        self.openQuestions = openQuestions
    }

    public static let passiveKind = "Video oder Vortrag"

    public func summary(provider: String, fallbackTitle: String, showTopics: Bool) -> Summary {
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

/// Prüft Aufgaben gegen das Transkript. Kleine Modelle halten sich bei Aufgaben trotz klarer Regeln nicht immer
/// an das Gesagte: Sie verteilen Aufgaben an „Team“ oder an Namen, die nie fielen, hängen Uhrzeiten an, die niemand
/// genannt hat („– bis 17:00“ in einem englischen Meeting ohne jede Uhrzeit), und erfinden in Vorlesungen
/// Aufgaben aus dem Stoff („Vergleich der Leistung von SATA- und NVMe-SSDs“).
/// - Zuständige, die im Transkript nicht vorkommen oder nur eine Gruppe sind, fallen weg; ebenso Fristen mit
///   Zahlen, die nie gesagt wurden.
/// - Eine Aufgabe ohne bekannte zuständige Person bleibt nur, wenn im Transkript ein Satz mit denselben
///   Kernwörtern nach Auftrag klingt („bis Freitag“, „bitte“, „müsst ihr“). Ist die Notiz übersetzt, lässt
///   sich das nicht Wort für Wort prüfen – dann bleibt sie.
public enum TaskCheck {
    private static let groups: Set<String> = ["team", "alle", "gruppe", "studierende", "teilnehmer", "teilnehmende",
                                              "beteiligte", "wir", "everyone", "all", "everybody"]

    /// Wörter, an denen man einen Auftrag erkennt (klein, ohne Umlaute)
    /// Bewusst eindeutig: „bis 7000“ oder „der Prozess muss warten“ sind in einer Vorlesung kein Auftrag.
    private static let cues = ["bitte", "aufgabe", "ubung", "abgab", "erledig", "ubernehm", "ubernimm", "kummer",
                               "vorbereit", "musst", "solltet", "ich muss", "ich sollte", "ich will", "nicht vergessen",
                               "denk dran", "mach ich", "machst du", "bis zum", "bis nachst", "bis morgen", "bis ende",
                               "bis montag", "bis dienstag", "bis mittwoch", "bis donnerstag", "bis freitag",
                               "please", "deadline", "homework", "assignment", "submit", "todo", "need to", "have to",
                               "will do", "i'll", "i will", "can you", "could you", "next week", "prepare"]

    /// Woran man einen Beschluss erkennt – Sachaussagen einer Vorlesung sind keine Entscheidungen
    private static let decisionCues = ["entschied", "entscheid", "beschlo", "vereinbar", "festgeleg", "geeinigt", "einig ",
                                       "machen wir", "nehmen wir", "lassen wir", "verschieb", "streichen", "decided",
                                       "decide", "agreed", "let's", "we'll", "go with", "postpone", "move it", "drop"]

    public static func clean(_ markdown: String, transcript: String) -> String {
        // Zahlen, die gesagt wurden – ohne die Zeitmarken des Transkripts („[00:12:30]“), sonst gälte „00:00“ als genannt
        let spoken = transcript.replacing(/\[\d{1,2}:\d{2}(?::\d{2})?\]/, with: "")
        let numbers = Set(spoken.matches(of: /\d+/).compactMap { Int($0.output) })
        let requests = spoken.split { ".!?\n".contains($0) }
            .filter { sentence in cues.contains { NoteStems.folded(String(sentence)).contains($0) } }
            .map { NoteStems.of(String($0)) }
        let decisions = spoken.split { ".!?\n".contains($0) }
            .filter { sentence in decisionCues.contains { NoteStems.folded(String(sentence)).contains($0) } }
            .map { NoteStems.of(String($0)) }
        let lines = markdown.components(separatedBy: "\n")
        let prose = lines.filter { !$0.contains("[ ]") && !$0.hasPrefix("#") }
        let sameLanguage = NoteStems.sameLanguage(prose.joined(separator: "\n"), spoken)

        var section = ""
        let checked = lines.compactMap { line -> String? in
            if line.hasPrefix("## ") { section = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() }
            // Entscheidungen: nur, wenn im Transkript ein Satz mit denselben Kernwörtern nach Beschluss klingt
            if section == "entscheidungen", sameLanguage, line.hasPrefix("- "), !line.contains("[ ]") {
                let mine = NoteStems.of(line)
                let needed = mine.count <= 2 ? 1 : 2
                return decisions.contains { $0.intersection(mine).count >= needed } ? line : nil
            }
            guard let task = line.firstMatch(of: /^(\s*- \[[ xX]\] )(.*)$/) else { return line }
            var text = String(task.output.2)
            var assigned = false
            // „Heiko: …“ bzw. „**Heiko**: …“ – nur kurze Angaben vor dem Doppelpunkt sind eine Zuständigkeit
            if let who = text.firstMatch(of: /^\*{0,2}([^:*]{1,40}?)\*{0,2}:\s+(.+)$/) {
                let name = String(who.output.1).trimmingCharacters(in: .whitespaces)
                let known = !Glossary.relevant([GlossaryTerm(term: name)], in: transcript).isEmpty
                if name.split(separator: " ").count <= 3 {
                    if groups.contains(name.lowercased()) || !known {
                        text = String(who.output.2)
                    } else {
                        assigned = true
                    }
                }
            }
            // „– bis 17:00“, „(bis 30.09.2026)“, „Frist: …“: Zahlen, die nie gesagt wurden, sind erfunden
            if let due = text.firstMatch(of: /\s*[–—-]?\s*\(?\b(?:bis|Frist:?|until|by)\s+[^()]*\d[^()]*\)?\s*$/),
               !due.output.matches(of: /\d+/).allSatisfy({ Int($0.output).map(numbers.contains) ?? false }) {
                text = String(text[..<due.range.lowerBound])
            }
            if !assigned, sameLanguage {
                let mine = NoteStems.of(text)
                let needed = mine.count <= 2 ? 1 : 2
                guard requests.contains(where: { $0.intersection(mine).count >= needed }) else { return nil }
            }
            return task.output.1 + text
        }
        return NoteStems.tidy(checked.joined(separator: "\n"))
    }
}

/// Grobe Wortstämme zum Vergleichen von Notiz und Transkript, und das Aufräumen danach.
enum NoteStems {
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Die ersten fünf Buchstaben aller Wörter ab fünf Buchstaben, ohne Füllwörter
    static func of(_ text: String) -> Set<String> {
        Set(folded(text).split { !$0.isLetter }.filter { $0.count >= 5 }.map { String($0.prefix(5)) }
            .filter { !stop.contains($0) })
    }

    /// Ist die Notiz in der Sprache des Transkripts? Bei einer Übersetzung teilen beide kaum Wortstämme.
    static func sameLanguage(_ note: String, _ transcript: String) -> Bool {
        let mine = of(note)
        return !mine.isEmpty && Double(mine.intersection(of(transcript)).count) / Double(mine.count) >= 0.3
    }

    private static let stop: Set<String> = [
        "werde", "wurde", "welch", "diese", "nicht", "keine", "einer", "einem", "einen", "eines", "haben", "hatte",
        "sollt", "konne", "konnt", "musse", "warum", "wieso", "wesha", "immer", "schon", "etwas", "damit",
        "there", "which", "would", "could", "about", "these", "those", "their", "where", "shoul", "being", "other",
    ]

    /// Abschnitte für Entscheidungen, Aufgaben und offene Fragen, die leer geworden sind, fallen weg;
    /// kommt einer doppelt vor, wird er zusammengelegt.
    static func tidy(_ markdown: String) -> String {
        let closing = ["entscheidungen", "aufgaben", "offene fragen"]
        var parts: [(heading: String?, lines: [String])] = [(nil, [])]
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { parts.append((line.trimmingCharacters(in: .whitespaces), [])) }
            else { parts[parts.count - 1].lines.append(line) }
        }
        var merged: [(heading: String?, lines: [String])] = []
        for part in parts {
            if let heading = part.heading, closing.contains(String(heading.dropFirst(3)).lowercased()),
               let i = merged.firstIndex(where: { $0.heading == heading }) {
                merged[i].lines += part.lines
            } else {
                merged.append(part)
            }
        }
        return merged.compactMap { part -> String? in
            let body = part.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let heading = part.heading else { return part.lines.joined(separator: "\n") }
            if closing.contains(String(heading.dropFirst(3)).lowercased()) {
                return body.isEmpty ? nil : ([heading] + body).joined(separator: "\n") + "\n"
            }
            return ([heading] + part.lines).joined(separator: "\n")
        }.joined(separator: "\n").replacing(/\n{3,}/, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Prüft „Offene Fragen“ gegen das Transkript. Kleine Modelle denken sich hier gern Fragen aus, die passen
/// könnten („Wie kann die IT-Sicherheit weiter verbessert werden?“), obwohl niemand sie gestellt hat.
/// Eine Frage bleibt, wenn im Transkript eine Frage mit denselben Kernwörtern steht. Gab es dort gar keine Frage,
/// fällt der Abschnitt weg. Ist die Notiz in eine andere Sprache übersetzt, lässt sich das Wort für Wort nicht
/// prüfen – dann bleibt es bei der Regel „keine Frage im Transkript, keine offenen Fragen“.
public enum QuestionCheck {
    public static func clean(_ markdown: String, transcript: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## offene fragen")
        }) else { return markdown }
        let end = lines[(head + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.count
        let asked = transcript.matches(of: /[^.!?\n]*\?/).map { NoteStems.of(String($0.output)) }.filter { !$0.isEmpty }
        let sameLanguage = NoteStems.sameLanguage((lines[..<head] + lines[end...]).joined(separator: "\n"), transcript)
        let kept = lines[(head + 1)..<end].filter { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return false }
            guard !asked.isEmpty else { return false }
            guard sameLanguage else { return true }
            let mine = NoteStems.of(text)
            let needed = mine.count <= 2 ? 1 : 2
            return asked.contains { $0.intersection(mine).count >= needed }
        }
        lines.replaceSubrange(head..<end, with: kept.isEmpty ? [] : [lines[head]] + kept + [""])
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol StructuredNotesClient: LLMClient {
    func completeNotes(system: String, prompt: String) async throws -> NotesDraft
}

/// Fortschritt, der nur vorwärts läuft – auch über Verdichtungsrunden und Neuversuche hinweg.
public final class MonotonicProgress: @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var value = 0.0

    public init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    public var current: Double { lock.lock(); defer { lock.unlock() }; return value }

    public func set(_ newValue: Double) {
        lock.lock()
        guard newValue > value else { lock.unlock(); return }
        value = min(1, newValue)
        let v = value
        lock.unlock()
        report(v)
    }

    /// Lässt den Balken während eines Schritts ohne Zwischenstand weiterlaufen: anfangs zügig, dann immer
    /// langsamer, ohne das Ziel zu erreichen. Läuft, bis der zurückgegebene Task abgebrochen wird.
    public func creep(to target: Double, typicalSeconds: Double) -> Task<Void, Never> {
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
public struct ContextWindowExceeded: LocalizedError, Sendable {
    public var errorDescription: String? { "Die Aufnahme ist für das gewählte KI-Modell zu lang." }

    public init() {}
}

public struct SummaryContext: Sendable {
    public var category: RecordingCategory?
    public var titleHint: String
    public var sourceApp: String?
    public var date: Date
    public var duration: TimeInterval
    public var hasSpeakers: Bool
    public var language: String
    /// Wörterbuch: richtige Schreibweisen für diese Aufnahme
    public var glossary: [GlossaryTerm]
    /// Einmalige Anweisung des Nutzers für genau diesen Durchgang („Neu zusammenfassen“)
    public var extraInstructions: String
    /// Einfache Sprache statt Fachsprache
    public var simpleLanguage = false

    public init(category: RecordingCategory?, titleHint: String, sourceApp: String?, date: Date,
                duration: TimeInterval, hasSpeakers: Bool, language: String,
                glossary: [GlossaryTerm] = [], extraInstructions: String = "", simpleLanguage: Bool = false) {
        self.category = category
        self.titleHint = titleHint
        self.sourceApp = sourceApp
        self.date = date
        self.duration = duration
        self.hasSpeakers = hasSpeakers
        self.language = language
        self.glossary = glossary
        self.extraInstructions = extraInstructions
        self.simpleLanguage = simpleLanguage
    }
}

/// Erstellt aus dem Transkript eine strukturierte Zusammenfassung.
/// Sehr lange Transkripte werden abschnittsweise verdichtet (Map-Reduce).
public struct Summarizer: Sendable {
    public let client: any LLMClient
    public let chunkCharacters: Int
    public let providerName: String

    public init(client: any LLMClient, chunkCharacters: Int, providerName: String) {
        self.client = client
        self.chunkCharacters = chunkCharacters
        self.providerName = providerName
    }

    /// `draft` bekommt die Notiz des letzten Schritts, während die KI sie schreibt (roh, mit Titelzeile).
    public func summarize(transcript: String, context: SummaryContext, precondensed: PreCondensed? = nil,
                          draft: @escaping @Sendable (String) -> Void = { _ in },
                          progress: @escaping @Sendable (Double) -> Void) async throws -> Summary {
        var context = context
        context.glossary = Glossary.relevant(context.glossary, in: transcript)
        let tracker = MonotonicProgress(progress)
        var material = transcript
        var isNotes = false
        var limit = chunkCharacters
        let words = Self.spokenWordCount(transcript)

        // Während der Aufnahme schon verdichtet: Dann fehlt nur noch der Rest seit dem letzten Block.
        if let precondensed, !precondensed.notes.isEmpty {
            let tail = precondensed.tail.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts = [precondensed.notes]
            if tail.count > 500 {
                parts.append(try await condense(chunk: tail, part: 0, of: 0, context: context))
            } else if !tail.isEmpty {
                parts.append(tail)
            }
            material = parts.joined(separator: "\n\n")
            isNotes = true
            tracker.set(0.6)
            Log.info("Zusammenfassung baut auf vorverdichtetem Material auf (\(material.count) Zeichen)")
        }

        // Verdichtungsrunden laufen bis 80 %. Wie viele Runden nötig sind, steht vorher nicht fest –
        // deshalb bekommt jede Runde drei Viertel des noch freien Bereichs.
        var roundStart = isNotes ? 0.6 : 0.0
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
                var summary = try await finalNotes(material, context: context, isNotes: isNotes, words: words,
                                                   progress: tracker, draft: draft)
                summary.markdown = QuestionCheck.clean(TaskCheck.clean(summary.markdown, transcript: transcript),
                                                       transcript: transcript)
                return summary
            } catch is ContextWindowExceeded where limit > 1_500 {
                // Nur den letzten Schritt wiederholen: kleinere Abschnitte, aber nicht alles von vorn.
                limit /= 2
                round = min(round, 3)
            }
        }
    }

    /// Schreibt eine vorhandene Notiz neu – für „Vereinfachen“ und wenn es kein Transkript gibt (Übersicht eines
    /// Bereichs). Ohne Verdichten und ohne Prüfung gegen ein Transkript: Die Notiz wurde beim Entstehen schon geprüft.
    /// Der Umfang bleibt etwa wie bisher (die Längenvorgabe zielt auf ein Sechstel des Gesprochenen).
    public func rewrite(_ markdown: String, context: SummaryContext,
                        draft: @escaping @Sendable (String) -> Void = { _ in },
                        progress: @escaping @Sendable (Double) -> Void) async throws -> Summary {
        var context = context
        context.glossary = Glossary.relevant(context.glossary, in: markdown)
        return try await finalNotes(markdown, context: context, isNotes: true, words: Self.spokenWordCount(markdown) * 6,
                                    progress: MonotonicProgress(progress), draft: draft)
    }

    /// Eine Verdichtungsrunde: Das Material wird in Abschnitte geteilt und jeder zu Notizen zusammengefasst.
    private func condense(_ material: String, limit: Int, context: SummaryContext,
                          progress: (Int, Int) -> Void) async throws -> String {
        let chunks = Self.split(material, max: limit)
        var notes: [String] = []
        for (i, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            notes.append(try await condense(chunk: chunk, part: i + 1, of: chunks.count, context: context))
            progress(i + 1, chunks.count)
        }
        return notes.joined(separator: "\n\n")
    }

    /// Eine einzelne Verdichtungsstufe – auch das Vorverdichten während der Aufnahme benutzt sie,
    /// damit beide Wege dieselben Notizen erzeugen. `total` 0 heißt: Anzahl noch unbekannt.
    /// Passt ein Abschnitt nicht ins Kontextfenster, wird nur dieser Abschnitt halbiert.
    public func condense(chunk: String, part: Int, of total: Int,
                         context: SummaryContext) async throws -> String {
        do {
            let position = total > 0 ? t("Teil \(part) von \(total):") : t("Teil \(part):")
            return try await client.complete(system: mapSystem(context),
                                             prompt: "\(position)\n\n\(chunk)")
        } catch is ContextWindowExceeded where chunk.count > 1_500 {
            let halves = Self.split(chunk, max: chunk.count / 2 + 1)
            var notes: [String] = []
            for half in halves {
                notes.append(try await condense(chunk: half, part: part, of: total, context: context))
            }
            return notes.joined(separator: "\n\n")
        }
    }

    private func finalNotes(_ material: String, context: SummaryContext, isNotes: Bool, words: Int,
                            progress: MonotonicProgress, draft: @escaping @Sendable (String) -> Void) async throws -> Summary {
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
        let raw = try await client.complete(system: markdownSystem(context), prompt: prompt, partial: draft)
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
        - Hat jemand ausdrücklich etwas entschieden, vereinbart oder eine Aufgabe übernommen, halte auch das fest \
        (wer und bis wann nur, wenn es gesagt wurde).
        - Namen nur, wenn sie im Abschnitt fallen. Wer nicht genannt wird, bleibt ohne Namen.
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
        Wer sie liest, soll verstehen, worum es ging und was gesagt oder vereinbart wurde, ohne die Aufnahme zu hören. \
        Sprache der Notizen: \(c.language).
        """
    }

    /// Genauigkeit, Inhalt und Stil – gilt für beide Ausgabeformate. Genauigkeit steht vorn: Kleine lokale Modelle
    /// halten sich an das, was zuerst und konkret dasteht. Die Regeln zu Namen, Aufgaben und offenen Fragen
    /// antworten auf echte Fehler (erfundene „Team:“-Aufgaben in Vorlesungen, Namen aus dem Wörterbuch für
    /// unbenannte Sprecher, selbst ausgedachte Fragen).
    private func contentRules(_ c: SummaryContext) -> String {
        var s = """
        Genauigkeit (am wichtigsten)
        - Schreib nur, was in der Aufnahme gesagt wurde. Nichts ergänzen, nichts aus Allgemeinwissen auffüllen. \
        Lieber eine kurze Notiz als eine erfundene.
        - Namen nur, wenn sie in der Aufnahme fallen. Wer nicht genannt wird, bleibt ohne Namen ("eine Teilnehmerin", "der Dozent").
        - Aufgaben nur, wenn jemand in der Aufnahme ausdrücklich etwas übernimmt, zusagt oder verlangt, \
        oder sich die aufnehmende Person in einer Sprachnotiz etwas vornimmt. Leite keine Aufgaben aus dem Thema ab. \
        Keine Aufgaben für "Team", "alle" oder "Studierende" erfinden. Zuständige Person und Frist nur, wenn genau das gesagt wurde.
        - Vorlesungen, Vorträge und Videos haben meist keine Aufgaben – außer die vortragende Person verlangt ausdrücklich etwas \
        (etwa ein Übungsblatt bis Freitag).
        - Entscheidungen nur, wenn ausdrücklich etwas festgelegt wurde. Fakten aus einem Vortrag sind keine Entscheidungen.
        - Offene Fragen nur, wenn sie in der Aufnahme gestellt und nicht beantwortet wurden. Keine eigenen Fragen.
        - Gibt es keine Entscheidungen, Aufgaben oder offenen Fragen, lass diese Abschnitte ganz weg.
        - Das Transkript wurde automatisch erstellt und enthält Hörfehler. Offensichtlich falsch erkannte Wörter korrigierst du \
        stillschweigend; was unverständlich bleibt, lässt du weg. Ist das Transkript in einer anderen Sprache, übersetze sinngemäß.
        - Kategorie und Dateiname sind nur Hinweise. Richte dich nach dem, was tatsächlich zu hören ist, \
        und nenne es auch so (eine Vorlesung ist kein Meeting).

        Inhalt
        - Gib die wichtigen Aussagen sinngemäß wieder, mit Begründungen, Beispielen, Zahlen und Namen. \
        Zusammenhänge gehören dazu, nicht nur Schlagworte.
        - Wichtiges ausführlich, Nebensächliches knapp, Smalltalk und Wiederholungen gar nicht. \
        Der Umfang richtet sich nach dem Material (siehe "Umfang" in der Nachricht). Nichts doppelt aufschreiben.

        Stil
        - Neutral und sachlich, in der dritten Person ("Vereinbart wurde …", "Anna schlägt vor …"). Keine Wertungen, keine Ratschläge.
        - Ganze Sätze für Zusammenhänge, knappe Stichpunkte für Aufzählungen.
        - Formeln, Variablen und Rechenwege in Code-Zeichen setzen: `A·v = λ·v`. So bleiben sie unverändert.
        """
        if c.simpleLanguage {
            s += """

            Einfach erklärt
            - Schreibe so, dass es eine Schülerin in der 8. Klasse versteht: kurze Sätze, alltägliche Wörter.
            - Fachbegriffe dürfen vorkommen, aber jeder wird beim ersten Mal in einem Halbsatz erklärt.
            - Erkläre den Zusammenhang, statt ihn vorauszusetzen. Lieber ein Satz mehr als ein Fremdwort.
            """
        }
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
        - Namen nur, wenn sie im Transkript fallen. Wer nicht genannt wird, bleibt ohne Namen.
        - Aufgaben nur, wenn jemand sie ausdrücklich übernommen hat oder sich vornimmt – keine für "Team" oder "alle", \
        keine aus dem Thema abgeleiteten. Vorlesungen und Videos haben meist keine Aufgaben.
        - Offene Fragen nur, wenn sie gestellt und nicht beantwortet wurden.
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
        let glossary = Glossary.promptText(c.glossary)
        if !glossary.isEmpty { p += "\n\(glossary)\n" }
        let extra = c.extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { p += "\nAnweisung des Nutzers für diese Notiz (geht allen anderen Regeln vor):\n\(extra)\n" }
        p += isNotes
            ? "\nDas folgende Material sind bereits verdichtete Notizen aus dem vollständigen Transkript, in zeitlicher Reihenfolge:\n\n"
            : "\nTranskript:\n\n"
        p += material
        return p
    }

    /// Wie ausführlich die Notizen werden sollen – gemessen am gesprochenen Text, nicht an der Aufnahmedauer
    /// (eine lange Aufnahme mit viel Stille ergibt trotzdem nur eine kurze Notiz).
    public static func lengthGuidance(words: Int) -> String {
        switch words {
        case ..<150:
            return "Sehr kurz (ca. \(words) gesprochene Wörter). Nur Titel, eine Kurzfassung in ein bis drei Sätzen und, "
                + "falls vorhanden, Aufgaben. Keine weitere Gliederung."
        case ..<700:
            return "Kurz (ca. \(words) Wörter). Eine kompakte Notiz: Kurzfassung und das Wesentliche in wenigen Punkten, "
                + "höchstens etwa 150 Wörter; nach Themen gliedern nur, wenn es mehrere klar getrennte Themen gibt."
        case ..<3_000:
            return "Mittel (ca. \(words) Wörter). Gliedere nach den Hauptthemen, insgesamt etwa \(target(words)) Wörter."
        case ..<12_000:
            return "Lang (ca. \(words) Wörter). Gliedere mit einer Überschrift \"## Thema\" je Thema, insgesamt etwa "
                + "\(target(words)) Wörter. Unter jeder Überschrift knappe Stichpunkte statt langer Absätze."
        default:
            return "Sehr lang (ca. \(words) Wörter). Gliedere mit einer Überschrift \"## Thema [Zeitmarke]\" je Thema, "
                + "insgesamt etwa \(target(words)) Wörter. Unter jeder Überschrift knappe Stichpunkte statt langer Absätze."
        }
    }

    /// Zielumfang der Notiz: etwa ein Sechstel des Gesprochenen, höchstens 1.200 Wörter. Die Rechenzeit der lokalen KI
    /// hängt fast nur daran, wie viel sie schreibt. Gemessen an einer Stunde Vorlesung (Qwen3 4B, 23.09.2026):
    /// ohne Ziel 1.168 Wörter in 524 s, mit Ziel 592 Wörter in 386 s.
    static func target(_ words: Int) -> Int {
        min(1_200, max(150, words / 6 / 50 * 50))
    }

    /// Wörter im Transkript ohne Zeitmarken und Sprecherangaben.
    public static func spokenWordCount(_ transcript: String) -> Int {
        transcript.split(whereSeparator: \.isWhitespace).filter { word in
            !(word.hasPrefix("[") && word.hasSuffix("]")) && word != "Ich:" && word != "Andere:"
        }.count
    }

    public static func split(_ text: String, max: Int) -> [String] {
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
