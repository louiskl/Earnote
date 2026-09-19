import Foundation

/// Bereinigt ein automatisch erstelltes Transkript, unabhängig von der Engine.
public enum TranscriptCleanup {
    /// Sätze, die Whisper aus Stille erfindet: Abspann- und Untertitel-Hinweise aus den Trainingsdaten.
    /// Sie sind nie echter Inhalt und fliegen immer raus.
    static let creditPhrases = [
        "untertitel im auftrag des", "untertitelung im auftrag des", "untertitelung des zdf",
        "untertitel von", "untertitel der amara", "amara org", "copyright wdr",
        "vielen dank fur ihre aufmerksamkeit und bis zum nachsten mal",
        "thanks for watching", "subtitles by the amara org community", "thank you for watching",
    ]

    /// Höflichkeitsfloskeln, die Whisper gern an stille Stellen setzt. Sie können auch echt sein –
    /// deshalb fliegen sie nur raus, wenn sie allein in einer Pause stehen.
    static let politePhrases = [
        "vielen dank", "danke", "dankeschon", "danke schon", "tschuss", "bis zum nachsten mal",
        "auf wiedersehen", "bis dann", "so", "okay", "hm", "mhm", "ja", "untertitel", "musik", "applaus",
    ]

    /// Alles zusammen: Schleifen entfernen, erfundene Sätze aus Stille entfernen.
    public static func clean(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        removeHallucinations(removeRepetitions(segments))
    }

    /// Entfernt Sätze, die Whisper aus Stille erfindet.
    /// Abspann-Floskeln immer, Höflichkeitsfloskeln nur, wenn sie einzeln in einer Pause stehen.
    public static func removeHallucinations(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.enumerated().filter { index, segment in
            let text = normalized(segment.text)
            guard !text.isEmpty else { return false }
            // Die Abspann-Floskeln stehen oft mit Jahreszahl oder Zusatz da – deshalb „enthält“ statt „gleich“.
            if creditPhrases.contains(where: text.contains) { return false }
            guard politePhrases.contains(text) else { return true }
            // Drei Wörter, die sich über Sekunden ziehen: Das hat Whisper über eine stille Stelle gelegt.
            let words = max(1, text.split(separator: " ").count)
            if segment.end - segment.start > Double(words) * 1.5 + 1.5 { return false }
            // Steht die Floskel mitten im Gespräch, ist sie echt; steht sie allein in einer Pause, nicht.
            let gapBefore = index == 0 ? Double.infinity : segment.start - segments[index - 1].end
            let gapAfter = index == segments.count - 1 ? Double.infinity : segments[index + 1].start - segment.end
            return min(gapBefore, gapAfter) < 2
        }.map(\.element)
    }

    /// Wie viele Wörter tatsächlich gesprochen wurden – zu wenige heißt: keine Sprache erkannt.
    public static func spokenWords(_ segments: [TranscriptSegment]) -> Int {
        segments.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +)
    }

    /// Kleinbuchstaben ohne Satzzeichen und Akzente – damit „Vielen Dank!“ und „vielen dank“ gleich sind.
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.punctuationCharacters).joined()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Whisper wiederholt bei Stille manchmal denselben Satz – solche Schleifen entfernen.
    public static func removeRepetitions(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var keys: [String] = []
        func key(_ text: String) -> String {
            text.lowercased().components(separatedBy: CharacterSet.punctuationCharacters
                .union(.whitespacesAndNewlines)).joined()
        }
        func follows(_ a: TranscriptSegment, _ b: TranscriptSegment) -> Bool {
            a.speaker == b.speaker && b.start >= a.start && b.start - a.end <= 3
        }
        for seg in segments {
            let normalized = key(seg.text)
            // Kurze Antworten, Sprecherwechsel und Wiederholungen nach Pausen können echter Inhalt sein.
            if normalized.count >= 12, keys.last == normalized, let last = out.last, follows(last, seg) {
                // Zeitspanne mitführen, damit auch eine längere Schleife am Stück erkannt wird.
                out[out.count - 1].end = max(last.end, seg.end)
                continue
            }
            out.append(seg)
            keys.append(normalized)
            let n = out.count
            if n >= 4, keys[n - 4].count >= 12, keys[n - 3].count >= 12,
               keys[n - 4] != keys[n - 3], keys[n - 4] == keys[n - 2], keys[n - 3] == keys[n - 1],
               follows(out[n - 4], out[n - 3]), follows(out[n - 3], out[n - 2]), follows(out[n - 2], out[n - 1]) {
                // A–B–A–B: das erste Paar behalten. Nicht über Lücken oder Sprecherwechsel hinweg kürzen.
                out[n - 3].end = max(out[n - 3].end, out[n - 1].end)
                out.removeLast(2)
                keys.removeLast(2)
            }
        }
        return out
    }
}
