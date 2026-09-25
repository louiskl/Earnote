import Foundation

/// Ein Stück Aufnahme, in dem eine Stimme spricht (Ergebnis der Sprechererkennung)
public struct SpeakerTurn: Equatable, Sendable {
    public var start: Double
    public var end: Double
    /// Kennung der Erkennung („S1“, „speaker_0“ …) – wird beim Zuordnen zu „Sprecher 1, 2 …“
    public var speaker: String

    public init(start: Double, end: Double, speaker: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

/// Sprechererkennung (Earnote Pro). Die Plattform hängt sie ein (EarnoteML: FluidAudio); `nil` = hier nicht
/// (z. B. ohne Pro) – dann bleibt das Transkript ohne Sprecher.
public protocol SpeakerDiarizer: Sendable {
    func diarize(_ audio: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerTurn]?
}

public enum Speakers {
    /// Anzeigename des n-ten Sprechers (ab 1)
    public static func label(_ number: Int) -> String { t("Sprecher \(number)") }

    /// Trägt in jedes Segment den Sprecher mit der größten Überschneidung ein, nummeriert nach erstem Auftreten.
    /// Erkennt die Erkennung nur eine Stimme, bleibt das Transkript ohne Sprecher – „Sprecher 1“ überall hilft niemandem.
    public static func assign(_ turns: [SpeakerTurn], to transcript: Transcript) -> Transcript {
        // Stimmen mit weniger als 2 % der Redezeit sind meist Fehlgriffe (Husten, Echo) – sonst stünde in der
        // Notiz ein „Sprecher 3“, den es nicht gibt. Im Test (30 min, 2 Stimmen) tauchte so einer für Sekunden auf.
        var share: [String: Double] = [:]
        for turn in turns { share[turn.speaker, default: 0] += turn.end - turn.start }
        let total = share.values.reduce(0, +)
        let turns = turns.filter { (share[$0.speaker] ?? 0) >= total * 0.02 }
        guard Set(turns.map(\.speaker)).count >= 2 else { return transcript }
        var numbers: [String: Int] = [:]
        var result = transcript
        for index in result.segments.indices {
            let segment = result.segments[index]
            var overlap: [String: Double] = [:]
            for turn in turns where turn.end > segment.start && turn.start < segment.end {
                overlap[turn.speaker, default: 0] += min(turn.end, segment.end) - max(turn.start, segment.start)
            }
            // Ohne Überschneidung (Pause zwischen den Stimmen) weiter mit dem vorigen Sprecher
            guard let id = overlap.max(by: { $0.value < $1.value })?.key else {
                result.segments[index].speaker = index > 0 ? result.segments[index - 1].speaker : nil
                continue
            }
            if numbers[id] == nil { numbers[id] = numbers.count + 1 }
            result.segments[index].speaker = label(numbers[id]!)
        }
        return result
    }

    /// Die Sprecher eines Transkripts in der Reihenfolge ihres ersten Auftretens
    public static func names(in transcript: Transcript) -> [String] {
        var seen: [String] = []
        for case let speaker? in transcript.segments.map(\.speaker) where !seen.contains(speaker) { seen.append(speaker) }
        return seen
    }

    /// Einen Sprecher umbenennen – im Transkript und überall in der Notiz.
    /// ponytail: einfaches Ersetzen im Text; „Sprecher 1“ träfe auch „Sprecher 10“ – bei so vielen Stimmen selten.
    public static func rename(_ old: String, to new: String, transcript: Transcript, note: String) -> (Transcript, String) {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != old else { return (transcript, note) }
        var result = transcript
        for index in result.segments.indices where result.segments[index].speaker == old {
            result.segments[index].speaker = name
        }
        return (result, note.replacingOccurrences(of: old, with: name))
    }
}
