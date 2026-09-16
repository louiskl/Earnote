import Foundation

/// Bereinigt ein automatisch erstelltes Transkript, unabhängig von der Engine.
public enum TranscriptCleanup {
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
