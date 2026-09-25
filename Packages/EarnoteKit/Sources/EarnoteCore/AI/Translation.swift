import Foundation

/// Übersetzen (Earnote Pro): eine fertige Notiz oder das ganze Transkript nachträglich in eine andere Sprache.
/// Die Sprache neuer Notizen stellt man kostenlos in den Einstellungen ein – das hier ist für das, was schon da ist.
public enum Translation {
    /// Sprachen zur Auswahl (Namen so, wie die KI sie im Auftrag liest)
    public static let languages = ["Deutsch", "Englisch", "Französisch", "Spanisch", "Italienisch", "Portugiesisch",
                                   "Niederländisch", "Polnisch", "Türkisch", "Ukrainisch", "Arabisch", "Chinesisch"]

    /// Größe eines Stücks – klein genug für das lokale Modell
    static let chunkCharacters = 5_000

    /// Notiz übersetzen; Markdown, Aufgaben, Zeitmarken und Karteikarten („::“) bleiben erhalten
    public static func note(_ markdown: String, to language: String, client: any LLMClient,
                            progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> String {
        let parts = chunks(markdown.components(separatedBy: "\n"))
        var out: [String] = []
        for (index, part) in parts.enumerated() {
            let system = """
            Übersetze den Markdown-Text vollständig auf \(language). Behalte Überschriften, Aufzählungen, Aufgaben \
            („- [ ]“), Zeitmarken in eckigen Klammern, Formeln und „::“ genau bei. Gib nur die Übersetzung aus.
            """
            out.append(try await client.complete(system: system, prompt: part).trimmingCharacters(in: .whitespacesAndNewlines))
            progress(Double(index + 1) / Double(parts.count))
        }
        return out.joined(separator: "\n\n")
    }

    /// Transkript übersetzen, Minute für Minute (Zeilen aus `Transcript.formatted`) – jede Zeile behält ihre Zeitmarke
    public static func transcript(_ transcript: Transcript, to language: String, client: any LLMClient,
                                  progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [String] {
        let lines = transcript.formatted(includeSpeakers: true).components(separatedBy: "\n").filter { !$0.isEmpty }
        let parts = chunks(lines)
        var out: [String] = []
        for (index, part) in parts.enumerated() {
            let system = """
            Übersetze jede Zeile auf \(language). Jede Zeile beginnt mit einer Zeitmarke in eckigen Klammern – \
            behalte sie unverändert am Zeilenanfang, ebenso Sprechernamen davor. Gleiche Anzahl Zeilen, \
            nichts zusammenfassen, nichts weglassen. Gib nur die übersetzten Zeilen aus.
            """
            let answer = try await client.complete(system: system, prompt: part)
            out += answer.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("[") }
            progress(Double(index + 1) / Double(parts.count))
        }
        return out
    }

    /// Zeilen zu Stücken bis `chunkCharacters` zusammenfassen, ohne eine Zeile zu teilen
    static func chunks(_ lines: [String], limit: Int = chunkCharacters) -> [String] {
        var parts: [String] = []
        var current = ""
        for line in lines {
            if !current.isEmpty, current.count + line.count + 1 > limit {
                parts.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(current) }
        return parts
    }
}
