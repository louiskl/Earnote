import Foundation

/// Probeklausur je Fach (Earnote Pro, am Mac frei): Die KI stellt Fragen aus den Notizen eines Bereichs und korrigiert
/// die Antworten mit Verweis auf die Vorlesung. Grundlage sind die fertigen Notizen – wie bei der Übersicht.
/// Gesichert wird eine Probeklausur als Notiz einer Aufnahme ohne Ton; ein eigenes Datenmodell braucht es nicht.
public enum MockExam {
    /// Eine Vorlesung, aus der Fragen kommen dürfen
    public struct Source: Sendable, Hashable {
        public let recordingID: UUID
        public let title: String
        public let date: Date
        public let markdown: String

        public init(recordingID: UUID, title: String, date: Date, markdown: String) {
            self.recordingID = recordingID
            self.title = title
            self.date = date
            self.markdown = markdown
        }
    }

    public struct Question: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let text: String
        /// Wissen, Verständnis oder Rechnen – so, wie die KI es nennt
        public let kind: String
        /// Index in den Quellen (nil, wenn die KI keine passende genannt hat)
        public let source: Int?

        public init(text: String, kind: String, source: Int?) {
            self.text = text
            self.kind = kind
            self.source = source
        }
    }

    public struct Grade: Hashable, Sendable {
        /// 0 = falsch oder leer, 1 = teilweise, 2 = richtig
        public let points: Int
        public let feedback: String

        public init(points: Int, feedback: String) {
            self.points = min(maxPoints, max(0, points))
            self.feedback = feedback
        }
    }

    public static let maxPoints = 2
    public static let defaultCount = 10

    // MARK: Material

    /// Notizen mit Nummer („[V2]“), neueste zuerst, bis das Budget voll ist. Was im Klausur-Radar stünde,
    /// kommt je Vorlesung vorneweg – das soll die KI bevorzugt abfragen.
    /// Gibt den Text und die Quellen zurück, die tatsächlich hineingepasst haben (in dieser Reihenfolge nummeriert).
    public static func material(_ sources: [Source], limit: Int) -> (text: String, used: [Source]) {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        var used: [Source] = []
        var text = ""
        for source in sources.sorted(by: { $0.date > $1.date }) {
            let number = used.count + 1
            var block = "## [V\(number)] \(source.title) (\(df.string(from: source.date)))\n"
            let important = ExamRadar.items(in: source.markdown)
            if !important.isEmpty {
                block += t("Prüfungsrelevant:") + "\n" + important.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
            }
            block += source.markdown + "\n\n"
            if text.count + block.count > limit {
                // Die erste Vorlesung immer mitnehmen, notfalls gekürzt – sonst gäbe es gar keine Fragen
                if used.isEmpty { text = String(block.prefix(limit)); used.append(source) }
                break
            }
            text += block
            used.append(source)
        }
        return (text, used)
    }

    // MARK: Fragen

    public static func questionSystem(language: String, count: Int) -> String {
        t("""
        Du stellst eine Probeklausur aus den Mitschriften eines Fachs zusammen. Die Studentin oder der Student \
        beantwortet die Fragen schriftlich, danach werden sie korrigiert.
        Schreibe genau \(count) Fragen, je Frage genau eine Zeile in diesem Format:
        V<Nummer der Vorlesung> | <Art> | <Frage>
        Beispiel: V2 | Verständnis | Warum ist eine Matrix mit lauter verschiedenen Eigenwerten diagonalisierbar?
        Art ist genau eines von: Wissen, Verständnis, Rechnen. Mische die Arten; Rechnen nur, wenn das Material \
        Rechenwege enthält.
        Frage bevorzugt, was unter „Prüfungsrelevant“ steht, und verteile die Fragen auf möglichst viele Vorlesungen.
        Nur, was im Material steht – nichts erfinden. Keine Fragen zu Terminen oder Organisatorischem.
        Jede Frage ist in zwei bis fünf Sätzen beantwortbar. Keine Lösungen, keine Einleitung, keine Nummerierung.
        """) + "\n" + t("Sprache der Fragen: \(language)")
    }

    /// Zeilen „V2 | Verständnis | Frage“ lesen. Fehlt die Nummer oder die Art, bleibt die Frage trotzdem.
    public static func parseQuestions(_ text: String, sourceCount: Int) -> [Question] {
        var seen = Set<String>()
        return text.components(separatedBy: "\n").compactMap { raw -> Question? in
            let line = raw.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^(?:[-*•] |\d+[.)]\s+)"#, with: "", options: .regularExpression)
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            var source: Int?
            var kind = ""
            var question = line
            if parts.count >= 3 {
                source = Int(parts[0].drop { !$0.isNumber }.prefix { $0.isNumber }).map { $0 - 1 }
                kind = parts[1]
                question = parts[2...].joined(separator: " | ")
            } else if parts.count == 2 {
                source = Int(parts[0].drop { !$0.isNumber }.prefix { $0.isNumber }).map { $0 - 1 }
                question = parts[1]
            }
            if let index = source, !(0..<sourceCount).contains(index) { source = nil }
            // Nur echte Fragen: genug Text, kein Überschriften- oder Einleitungsrest
            guard question.count >= 12, !question.hasPrefix("#"), question.contains("?") || question.count >= 25,
                  seen.insert(question.lowercased()).inserted else { return nil }
            return Question(text: question, kind: kind, source: source)
        }
    }

    public static func questions(client: any LLMClient, sources: [Source], language: String,
                                 count: Int = defaultCount, limit: Int) async throws -> (questions: [Question], used: [Source]) {
        let (text, used) = material(sources, limit: limit)
        guard !used.isEmpty else { return ([], []) }
        var response = try await client.complete(system: questionSystem(language: language, count: count),
                                                 prompt: t("Material:") + "\n\n" + text)
        response = stripFence(response)
        return (Array(parseQuestions(response, sourceCount: used.count).prefix(count)), used)
    }

    // MARK: Korrektur

    public static func gradeSystem(language: String) -> String {
        t("""
        Du korrigierst eine Antwort in einer Probeklausur – freundlich, ehrlich und knapp.
        Grundlage ist die Mitschrift unten. Antworte in genau zwei Zeilen:
        Punkte: <0, 1 oder 2>
        Rückmeldung: <ein bis zwei Sätze: was richtig war und was gefehlt hat>
        2 = richtig und vollständig, 1 = teilweise richtig, 0 = falsch, leer oder am Thema vorbei.
        Andere Formulierungen als in der Mitschrift sind in Ordnung, wenn der Inhalt stimmt.
        Wiederholt die Antwort nur die Frage oder sagt nichts Inhaltliches, gibt es 0 Punkte.
        Steht die Lösung nicht in der Mitschrift, bewerte nach allgemeinem Fachwissen und sag das.
        """) + "\n" + t("Sprache der Rückmeldung: \(language)")
    }

    /// „Punkte: 1“ und „Rückmeldung: …“ lesen – auch, wenn die KI die Wörter anders schreibt oder alles in eine Zeile packt
    public static func parseGrade(_ text: String) -> Grade? {
        let cleaned = stripFence(text)
        guard let match = cleaned.firstMatch(of: try! Regex(#"(?i)(?:punkte|points|score)\s*[:=]\s*([0-2])"#)),
              let points = Int(match.output[1].substring ?? "") else { return nil }
        var feedback = cleaned
        if let label = cleaned.firstMatch(of: try! Regex(#"(?i)(?:rückmeldung|feedback)\s*[:=]\s*"#)) {
            feedback = String(cleaned[label.range.upperBound...])
        } else {
            feedback = String(cleaned[match.range.upperBound...])
        }
        return Grade(points: points, feedback: feedback.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Eine Antwort korrigieren – nur mit der Notiz, aus der die Frage stammt, damit es auch in kleine Modelle passt.
    /// Leere Antworten kosten keine Anfrage.
    public static func grade(client: any LLMClient, question: Question, answer: String, source: Source?,
                             language: String, limit: Int) async throws -> Grade {
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return Grade(points: 0, feedback: t("Keine Antwort.")) }
        // Kleine Modelle geben dafür trotzdem Punkte (gemessen mit Qwen3 4B) – das entscheiden wir selbst
        if repeatsQuestion(answer, question.text) {
            return Grade(points: 0, feedback: t("Die Antwort wiederholt nur die Frage."))
        }
        var prompt = ""
        if let source { prompt += t("Mitschrift:") + "\n" + String(source.markdown.prefix(limit)) + "\n\n" }
        prompt += t("Frage:") + " " + question.text + "\n" + t("Antwort:") + " " + String(answer.prefix(3_000))
        let response = try await client.complete(system: gradeSystem(language: language), prompt: prompt)
        return parseGrade(response) ?? Grade(points: 0, feedback: t("Die KI hat keine Bewertung geliefert."))
    }

    /// Die Antwort ist (fast) nur die Frage: gleiche Wörter, nichts dazu
    static func repeatsQuestion(_ answer: String, _ question: String) -> Bool {
        func words(_ s: String) -> [String] {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let a = words(answer), q = Set(words(question))
        guard !a.isEmpty else { return true }
        let new = a.filter { !q.contains($0) }
        return new.count <= max(1, a.count / 10)
    }

    // MARK: Sichern

    /// Die ganze Probeklausur als Notiz: Ergebnis oben, darunter je Frage Antwort, Punkte, Rückmeldung und Quelle
    public static func markdown(title: String, date: Date, questions: [Question], answers: [String],
                                grades: [Grade], sources: [Source]) -> String {
        let total = grades.reduce(0) { $0 + $1.points }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        var out = "# \(title)\n\n"
        out += "**" + t("Ergebnis: \(total) von \(questions.count * maxPoints) Punkten") + "** · \(df.string(from: date))\n"
        for (index, question) in questions.enumerated() {
            out += "\n## \(index + 1). \(question.text)\n"
            let answer = index < answers.count ? answers[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            out += "- **" + t("Deine Antwort:") + "** " + (answer.isEmpty ? "–" : answer.replacingOccurrences(of: "\n", with: " ")) + "\n"
            if index < grades.count {
                out += "- **" + t("Bewertung: \(grades[index].points) von \(maxPoints)") + "** – " + grades[index].feedback + "\n"
            }
            if let s = question.source, s < sources.count {
                out += "- " + t("Steht in: \(sources[s].title) (\(df.string(from: sources[s].date)))") + "\n"
            }
        }
        return out
    }

    private static func stripFence(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: #"^```[^\n]*\n"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\n```\s*$"#, with: "", options: .regularExpression)
        }
        return s
    }
}
