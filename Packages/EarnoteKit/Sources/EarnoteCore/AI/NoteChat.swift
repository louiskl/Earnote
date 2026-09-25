import Foundation

/// Chat zur Notiz (Earnote Pro): Rückfragen an die KI. Sie bekommt die Notiz und nur die Stellen des Transkripts,
/// die zur Frage passen – das ganze Transkript sprengte bei langen Vorlesungen das lokale Modell.
public enum NoteChat {
    public struct Message: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let fromUser: Bool
        public var text: String

        public init(fromUser: Bool, text: String) {
            self.fromUser = fromUser
            self.text = text
        }
    }

    /// Obergrenzen, damit auch das lokale Modell (kleines Kontextfenster) mitkommt
    static let noteLimit = 12_000
    static let historyCount = 6
    static let messageLimit = 1_500

    /// Die Minuten des Transkripts (Zeilen aus `Transcript.formatted`), die die meisten Wörter der Frage enthalten –
    /// in zeitlicher Reihenfolge. Ohne Treffer: keine.
    /// ponytail: Wortanfänge statt Embeddings; reicht für „Was hat er zu X gesagt?“, Synonyme findet es nicht.
    public static func passages(for question: String, in transcript: Transcript?, count: Int = 3) -> [String] {
        guard let transcript else { return [] }
        let wanted = Set(keywords(question))
        guard !wanted.isEmpty else { return [] }
        let lines = transcript.formatted(includeSpeakers: true).components(separatedBy: "\n")
        let scored = lines.enumerated().compactMap { index, line -> (index: Int, score: Int)? in
            let score = wanted.intersection(keywords(line)).count
            return score > 0 ? (index, score) : nil
        }
        let best = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.prefix(count)
        return best.map(\.index).sorted().map { lines[$0] }
    }

    /// Wörter mit Gewicht: klein geschrieben, ohne Füllwörter, auf die ersten sechs Buchstaben gekürzt
    /// („Eigenwerte“ und „Eigenwert“ treffen sich so)
    static func keywords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { $0.count >= 4 && !stopwords.contains($0) }
            .map { String($0.prefix(6)) }
    }

    private static let stopwords: Set<String> = [
        "aber", "alle", "also", "auch", "dann", "dass", "denn", "diese", "dieser", "doch", "eine", "einem", "einen",
        "einer", "etwas", "gesagt", "genau", "habe", "haben", "hier", "immer", "jetzt", "kann", "können", "mehr",
        "nicht", "noch", "nochmal", "oder", "schon", "sein", "sich", "sind", "über", "und", "unter", "viel", "vorlesung",
        "warum", "welche", "welcher", "wenn", "werden", "wieder", "wird", "wurde", "zum", "zur", "erkläre", "erklär",
        "about", "what", "which", "that", "this", "with", "have", "does", "from", "they", "there", "explain",
    ]

    /// Systemtext und Anfrage. Der Verlauf steht mit in der Anfrage – die Clients kennen nur eine Runde.
    public static func request(title: String, note: String, passages: [String], history: [Message],
                               question: String) -> (system: String, prompt: String) {
        let system = """
        Du bist ein geduldiger Tutor. Du beantwortest Rückfragen zur Aufnahme „\(title)“. Grundlage sind die Notiz \
        und die Stellen aus dem Transkript unten. Steht etwas nicht darin, sag das ehrlich und erkläre es danach \
        allgemein – beginne diesen Teil mit „Allgemein:“. Antworte in der Sprache der Frage, kurz und verständlich, \
        gern mit Aufzählungen. Nutzt du eine Transkriptstelle, nenne ihre Zeitmarke in eckigen Klammern, z. B. [00:12:34].
        """
        var prompt = "## Notiz\n" + String(note.prefix(noteLimit))
        if !passages.isEmpty {
            prompt += "\n\n## Stellen aus dem Transkript\n" + passages.joined(separator: "\n")
        }
        let earlier = history.suffix(historyCount)
        if !earlier.isEmpty {
            prompt += "\n\n## Bisheriges Gespräch\n" + earlier.map {
                ($0.fromUser ? "Frage: " : "Antwort: ") + String($0.text.prefix(messageLimit))
            }.joined(separator: "\n")
        }
        prompt += "\n\n## Neue Frage\n" + question
        return (system, prompt)
    }

    /// Frage stellen; `partial` meldet die Antwort beim Entstehen
    public static func ask(client: any LLMClient, title: String, note: String, transcript: Transcript?,
                           history: [Message], question: String,
                           partial: @escaping @Sendable (String) -> Void) async throws -> String {
        let found = passages(for: question, in: transcript)
        let (system, prompt) = request(title: title, note: note, passages: found, history: history, question: question)
        let answer = try await client.complete(system: system, prompt: prompt, partial: partial)
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Frage und Antwort als Abschnitt für die Notiz („In Notiz übernehmen“)
    public static func markdown(question: String, answer: String) -> String {
        "\n**\(question)**\n\n\(answer)\n"
    }
}
