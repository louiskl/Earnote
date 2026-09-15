import Foundation

enum RecordingStatus: String, Codable {
    case recording, queued, transcribing, summarizing, exporting, done, failed

    var label: String {
        switch self {
        case .recording: return "Aufnahme läuft"
        case .queued: return "Wartet"
        case .transcribing: return "Wird transkribiert"
        case .summarizing: return "Wird zusammengefasst"
        case .exporting: return "Wird exportiert"
        case .done: return "Fertig"
        case .failed: return "Fehler"
        }
    }
    var isBusy: Bool { [RecordingStatus.queued, .transcribing, .summarizing, .exporting].contains(self) }
}

struct ExportResult: Codable, Hashable {
    var destinationID: String
    var destinationName: String
    var success: Bool
    var message: String
    var url: String?
    var date: Date = Date()
}

/// Metadaten einer Aufnahme. Liegt als meta.json im Ordner der Aufnahme.
struct Recording: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var categoryID: UUID?
    var sourceApp: String?          // z. B. "Zoom"
    var startedAt: Date = Date()
    var endedAt: Date?
    var hasSystemAudio: Bool = false
    var status: RecordingStatus = .recording
    var progress: Double = 0
    var errorMessage: String?
    var exports: [ExportResult] = []
    var language: String = "de"
    var importedFileName: String?
    var summaryTitle: String?
    var taskCount: Int = 0

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
}

struct TranscriptSegment: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var speaker: String?   // "Ich" / "Andere" / nil
}

struct Transcript: Codable {
    var segments: [TranscriptSegment]
    var engine: String

    /// Kompakter Text mit Zeitmarken und Sprechern, für die KI und die Ablage.
    func formatted(includeSpeakers: Bool = true) -> String {
        var lines: [String] = []
        var currentSpeaker: String?
        var buffer: [String] = []
        var bufferStart: Double = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            let who = (includeSpeakers && currentSpeaker != nil) ? " \(currentSpeaker!):" : ""
            lines.append("[\(TimeFormat.clock(bufferStart))]\(who) " + buffer.joined(separator: " "))
            buffer.removeAll()
        }

        for seg in segments {
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            let speakerChanged = includeSpeakers && seg.speaker != currentSpeaker
            if buffer.isEmpty || speakerChanged || seg.start - bufferStart >= 60 {
                flush()
                bufferStart = seg.start
                currentSpeaker = seg.speaker
            }
            buffer.append(text)
        }
        flush()
        return lines.joined(separator: "\n")
    }

    var plainText: String { segments.map(\.text).joined(separator: " ") }
}

enum TimeFormat {
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
