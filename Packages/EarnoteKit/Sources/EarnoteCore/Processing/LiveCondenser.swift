import Foundation

/// Was das Vorverdichten bis zum Stopp geschafft hat
public struct PreCondensed: Sendable {
    /// Schon verdichtete Notizen der früheren Abschnitte
    public let notes: String
    /// Der Rest des Transkripts, der noch roh ist
    public let tail: String

    public init(notes: String, tail: String) {
        self.notes = notes
        self.tail = tail
    }
}

/// Verdichtet das Transkript schon **während** der Aufnahme.
///
/// Warum: Nach einer 90-Minuten-Vorlesung ist das Transkript dank `LiveTranscription` zwar sofort da,
/// die KI muss es danach aber erst in mehreren Runden verdichten – das dauert die meiste Zeit.
/// Hier passiert das schon währenddessen: Sobald wieder ein Block Text zusammengekommen ist, wird er
/// zu Notizen verdichtet. Nach dem Stopp bleibt nur noch der letzte Rest plus die eigentliche Notiz.
///
/// Geht unterwegs etwas schief, ist das kein Fehler: Dann liegt eben nichts Vorverdichtetes vor
/// und es läuft wie bisher.
public actor LiveCondenser {
    private let summarizer: Summarizer
    private let context: SummaryContext
    /// So viel neuer Text muss da sein, damit sich ein Durchgang lohnt
    private let blockCharacters: Int

    private var notes: [String] = []
    /// Bis hierhin ist der Text verdichtet (Zeichen vom Anfang)
    private var consumed = 0
    private var running = false
    private var failed = false

    public init(summarizer: Summarizer, context: SummaryContext, blockCharacters: Int = 20_000) {
        self.summarizer = summarizer
        self.context = context
        self.blockCharacters = max(4_000, blockCharacters)
    }

    /// Verdichtet den nächsten Block, wenn genug neuer Text da ist. Sonst passiert nichts.
    /// `fullText` ist das Transkript, so weit es bisher fertig ist – es wächst nur hinten.
    public func advance(fullText: String) async {
        guard !failed, !running, fullText.count - consumed >= blockCharacters else { return }
        running = true
        defer { running = false }
        let block = nextBlock(from: fullText)
        guard !block.text.isEmpty else { return }
        do {
            let started = Date()
            let note = try await summarizer.condense(chunk: block.text, part: notes.count + 1, of: 0,
                                                     context: context)
            notes.append(note)
            consumed = block.end
            Log.info(String(format: "Vorverdichtet: Block %d (%d Zeichen) in %.0f s",
                            notes.count, block.text.count, Date().timeIntervalSince(started)))
        } catch is CancellationError {
            // Aufnahme beendet – der Rest wird nach dem Stopp normal verarbeitet
        } catch {
            failed = true
            Log.info("Vorverdichten abgebrochen: \(error.localizedDescription)")
        }
    }

    /// Nach dem Stopp: Was ist verdichtet, was ist noch roh?
    /// `nil` heißt: nichts Verwertbares – bitte ganz normal verarbeiten.
    public func finish(fullText: String) -> PreCondensed? {
        guard !failed, !notes.isEmpty, consumed > 0, consumed <= fullText.count else { return nil }
        let tail = String(fullText.dropFirst(consumed))
        return PreCondensed(notes: notes.joined(separator: "\n\n"), tail: tail)
    }

    /// Der nächste Block, abgeschnitten am letzten Zeilenumbruch – mitten im Satz zu trennen
    /// kostet Sinn, den die KI nicht zurückbekommt.
    private func nextBlock(from fullText: String) -> (text: String, end: Int) {
        let start = fullText.index(fullText.startIndex, offsetBy: consumed)
        let hardEnd = fullText.index(start, offsetBy: blockCharacters, limitedBy: fullText.endIndex) ?? fullText.endIndex
        let slice = fullText[start..<hardEnd]
        guard let lastBreak = slice.lastIndex(of: "\n") else {
            return (String(slice), consumed + slice.count)
        }
        let text = slice[slice.startIndex...lastBreak]
        return (String(text).trimmingCharacters(in: .whitespacesAndNewlines), consumed + text.count)
    }
}
