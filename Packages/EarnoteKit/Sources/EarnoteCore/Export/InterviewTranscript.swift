import Foundation

/// Interview-Transkript für Abschlussarbeiten nach Dresing & Pehl (vereinfacht): ein Absatz je Sprecherwechsel,
/// Kürzel „I:“ für die Person, die fragt, „B:“ bzw. „B1:“, „B2:“ für die Befragten, Zeitmarke `#00:01:23-4#` am
/// Ende jedes Absatzes. Als Text (MAXQDA, f4) oder RTF mit Zeilennummern (Word).
public enum InterviewTranscript {
    public struct Paragraph: Equatable, Sendable {
        public var code: String
        public var text: String
        public var end: Double
    }

    /// Absätze mit Kürzeln – nil, wenn das Transkript keine zwei Sprecher hat (dann erst „Sprecher erkennen“)
    public static func paragraphs(_ transcript: Transcript) -> [Paragraph]? { build(transcript)?.paragraphs }

    static func build(_ transcript: Transcript) -> (paragraphs: [Paragraph], codes: [(speaker: String, code: String)])? {
        let speakers = Speakers.names(in: transcript)
        guard speakers.count >= 2 else { return nil }
        var turns: [(speaker: String, text: String, end: Double)] = []
        for segment in transcript.segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let speaker = segment.speaker, !text.isEmpty else { continue }
            if turns.last?.speaker == speaker {
                turns[turns.count - 1].text += " " + text
                turns[turns.count - 1].end = segment.end
            } else {
                turns.append((speaker, text, segment.end))
            }
        }
        // Wer fragt: die Stimme mit den meisten Fragezeichen; bei Gleichstand die zuerst sprechende
        let questions = speakers.map { speaker in
            turns.filter { $0.speaker == speaker }.reduce(0) { $0 + $1.text.filter { $0 == "?" }.count }
        }
        let interviewer = speakers[questions.firstIndex(of: questions.max() ?? 0) ?? 0]
        let others = speakers.filter { $0 != interviewer }
        let codes = [(interviewer, "I")] + others.enumerated().map { ($1, others.count == 1 ? "B" : "B\($0 + 1)") }
        let lookup = Dictionary(uniqueKeysWithValues: codes)
        return (turns.map { Paragraph(code: lookup[$0.speaker] ?? "?", text: $0.text, end: $0.end) }, codes)
    }

    /// `#00:01:23-4#` – Stunden, Minuten, Sekunden, Zehntel (wie f4 und MAXQDA sie erkennen)
    static func stamp(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded(.down))
        return "#\(TimeFormat.clock(Double(tenths / 10)))-\(tenths % 10)#"
    }

    /// Kopf: Titel, Datum, Dauer und welche Stimme welches Kürzel hat
    static func header(title: String, date: Date, duration: TimeInterval, codes: [(speaker: String, code: String)]) -> [String] {
        let legend = codes.map { "\($0.code) = \($0.speaker)" }.joined(separator: ", ")
        return [
            title,
            t("Datum: \(date.formatted(date: .numeric, time: .omitted)) · Dauer: \(TimeFormat.clock(duration))"),
            t("Transkription nach Dresing & Pehl (vereinfacht) · \(legend)"),
        ]
    }

    public static func text(_ transcript: Transcript, title: String, date: Date, duration: TimeInterval) -> String? {
        guard let (paragraphs, codes) = build(transcript) else { return nil }
        let body = paragraphs.map { "\($0.code): \($0.text) \(stamp($0.end))" }
        return (header(title: title, date: date, duration: duration, codes: codes) + body).joined(separator: "\n\n") + "\n"
    }

    /// RTF mit Zeilennummern am Rand – Word und MAXQDA öffnen es direkt
    public static func rtf(_ transcript: Transcript, title: String, date: Date, duration: TimeInterval) -> String? {
        guard let (paragraphs, codes) = build(transcript) else { return nil }
        let head = header(title: title, date: date, duration: duration, codes: codes)
        var rtf = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0\\fswiss Helvetica;}}\\f0\\fs24\\sl360\\slmult1\n"
        rtf += "{\\b " + escape(head[0]) + "}\\par\n" + escape(head[1]) + "\\par\n" + escape(head[2]) + "\\par\\par\n"
        // Zeilennummern nur für das Transkript, nicht für den Kopf
        rtf += "\\sect\\sectd\\linemod1\\linex360\\linerestart\n"
        for paragraph in paragraphs {
            rtf += "{\\b " + escape(paragraph.code) + ":} " + escape(paragraph.text) + " " + escape(stamp(paragraph.end)) + "\\par\\par\n"
        }
        return rtf + "}\n"
    }

    /// RTF kennt nur ASCII: Steuerzeichen maskieren, alles andere als `\uN?` (UTF-16, vorzeichenbehaftet)
    static func escape(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            switch unit {
            case 0x5C: out += "\\\\"
            case 0x7B: out += "\\{"
            case 0x7D: out += "\\}"
            case 0x0A: out += "\\line "
            case 0..<0x80: out.unicodeScalars.append(Unicode.Scalar(unit)!)
            default: out += "\\u\(Int16(bitPattern: unit))?"
            }
        }
        return out
    }
}
