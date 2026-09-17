import Foundation

public enum RecordingStatus: String, Codable, Sendable {
    case recording, queued, transcribing, summarizing, exporting, done, failed

    public var label: String {
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
    public var isBusy: Bool { [RecordingStatus.queued, .transcribing, .summarizing, .exporting].contains(self) }
}

public struct ExportResult: Codable, Hashable, Sendable {
    public var destinationID: String
    public var destinationName: String
    public var success: Bool
    public var message: String
    public var url: String?
    public var date: Date = Date()
    /// Ziel war nicht eingerichtet und wurde übersprungen (optional, damit ältere Dateien lesbar bleiben)
    public var skipped: Bool?

    public init(destinationID: String, destinationName: String, success: Bool, message: String,
                url: String? = nil, date: Date = Date(), skipped: Bool? = nil) {
        self.destinationID = destinationID
        self.destinationName = destinationName
        self.success = success
        self.message = message
        self.url = url
        self.date = date
        self.skipped = skipped
    }
}

/// Woher eine Aufnahme stammt
public enum RecordingOrigin: String, Codable, Sendable {
    case microphone, importedFile, companionDevice
}

/// Stand einer Aufnahme als Wert (Snapshot). Gespeichert wird sie in der Bibliothek (`LibraryRecording`);
/// ältere Versionen legten sie als meta.json im Ordner der Aufnahme ab.
public struct Recording: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var categoryID: UUID?
    public var sourceApp: String?          // z. B. "Zoom"
    public var startedAt: Date = Date()
    public var endedAt: Date?
    public var hasSystemAudio: Bool = false
    public var status: RecordingStatus = .recording
    public var progress: Double = 0
    public var errorMessage: String?
    public var exports: [ExportResult] = []
    public var language: String = "de"
    public var importedFileName: String?
    public var summaryTitle: String?
    /// Erster Satz der Notizen – für die Vorschau in der Liste
    public var summaryPreview: String?
    public var taskCount: Int = 0
    /// Summe der Pausen während der Aufnahme (optional, damit ältere meta.json-Dateien lesbar bleiben)
    public var pausedDuration: TimeInterval?
    /// Vom Nutzer benannt (nil bei älteren meta.json-Dateien: dann entscheidet das Namensmuster)
    public var isTitleCustom: Bool?

    public init(id: UUID = UUID(), title: String, categoryID: UUID? = nil, sourceApp: String? = nil,
                startedAt: Date = Date(), endedAt: Date? = nil, status: RecordingStatus = .recording) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.sourceApp = sourceApp
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }

    /// Automatisch vergebener Name wie „Meeting – 15. Sept., 19:58“ (nicht vom Nutzer umbenannt)
    public var hasAutoTitle: Bool {
        if let isTitleCustom { return !isTitleCustom }
        return Self.looksAutomatic(title)
    }

    /// Entspricht der Name dem Muster der automatisch vergebenen Namen?
    public static func looksAutomatic(_ title: String) -> Bool {
        title.range(of: #" – \d{1,2}\. \S+, \d{2}:\d{2}$"#, options: .regularExpression) != nil
    }

    public var origin: RecordingOrigin { importedFileName == nil ? .microphone : .importedFile }

    /// Was als Überschrift angezeigt wird: der Titel der Notizen, außer der Nutzer hat selbst benannt.
    public var displayTitle: String {
        if let summaryTitle, hasAutoTitle { return summaryTitle }
        return title
    }

    /// Aufgenommene Zeit ohne Pausen
    public var duration: TimeInterval { max(0, (endedAt ?? Date()).timeIntervalSince(startedAt) - (pausedDuration ?? 0)) }
}

public struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?   // "Ich" / "Andere" / nil

    public init(id: UUID = UUID(), start: Double, end: Double, text: String, speaker: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public struct Transcript: Codable, Sendable {
    public var segments: [TranscriptSegment]
    public var engine: String

    public init(segments: [TranscriptSegment], engine: String) {
        self.segments = segments
        self.engine = engine
    }

    /// Kompakter Text mit Zeitmarken und Sprechern, für die KI und die Ablage.
    public func formatted(includeSpeakers: Bool = true) -> String {
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

    public var plainText: String { segments.map(\.text).joined(separator: " ") }
}

public enum TimeFormat {
    public static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
