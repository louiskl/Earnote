import Foundation
import SwiftData

// Umwandlungen zwischen den gespeicherten Modellen und den Werttypen (Snapshots), mit denen Pipeline,
// Stores und Oberfläche arbeiten. `@Model`-Objekte verlassen nie den Actor des Repositorys.

/// Wörterbuch-Eintrag als Wert
public struct GlossaryTerm: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var term: String
    public var variants: [String]
    public var note: String?
    /// nil = gilt in allen Bereichen
    public var categoryID: UUID?

    public init(id: UUID = UUID(), term: String, variants: [String] = [], note: String? = nil, categoryID: UUID? = nil) {
        self.id = id
        self.term = term
        self.variants = variants
        self.note = note
        self.categoryID = categoryID
    }
}

extension LibraryRecording {
    /// Snapshot mit Bereich, Exporten und Kennzahlen der Notiz – das Transkript wird dabei nicht geladen.
    public func snapshot() -> Recording {
        var r = Recording(id: id, title: title, categoryID: category?.id, sourceApp: sourceApp,
                          startedAt: startedAt, endedAt: endedAt, status: status)
        r.isTitleCustom = isTitleCustom
        r.pausedDuration = pausedDuration > 0 ? pausedDuration : nil
        r.language = languageCode
        r.hasSystemAudio = hasSystemAudio
        r.importedFileName = importedFileName
        r.errorMessage = errorMessage
        r.summaryTitle = note?.title
        r.summaryPreview = note?.preview
        r.taskCount = note?.taskCount ?? 0
        r.exports = (exports ?? []).map { $0.snapshot() }.sorted { ($0.date, $0.destinationID) < ($1.date, $1.destinationID) }
        return r
    }

    /// Übernimmt die eigenen Felder. Bereich, Exporte und Notiz setzt das Repository.
    public func apply(_ r: Recording) {
        title = r.title
        isTitleCustom = !r.hasAutoTitle
        startedAt = r.startedAt
        endedAt = r.endedAt
        pausedDuration = r.pausedDuration ?? 0
        sourceApp = r.sourceApp
        languageCode = r.language
        origin = r.origin
        hasSystemAudio = r.hasSystemAudio
        importedFileName = r.importedFileName
        status = r.status
        errorMessage = r.errorMessage
    }
}

extension LibraryTranscript {
    public func snapshot() -> Transcript? {
        guard let segmentsData, let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData) else {
            return nil
        }
        return Transcript(segments: segments, engine: engine)
    }

    public func apply(_ t: Transcript) throws {
        engine = t.engine
        segmentsData = try JSONEncoder().encode(t.segments)
        plainText = t.plainText
        wordCount = t.plainText.split(whereSeparator: \.isWhitespace).count
    }
}

extension LibraryNote {
    /// Die aktuelle Fassung
    public func snapshot() -> Summary {
        Summary(title: title, markdown: markdown, taskCount: taskCount, provider: provider)
    }

    /// Neues Ergebnis der KI: aktuelle Fassung und KI-Original.
    public func applyGenerated(_ s: Summary, preview: String? = nil) {
        title = s.title
        markdown = s.markdown
        generatedTitle = s.title
        generatedMarkdown = s.markdown
        provider = s.provider
        taskCount = s.taskCount
        self.preview = preview ?? s.preview
        editedAt = nil
    }
}

extension LibraryCategory {
    public func snapshot() -> RecordingCategory {
        RecordingCategory(id: id, name: name, emoji: emoji, symbol: symbol, colorHex: colorHex,
                          instructions: instructions, destinationIDs: Set(destinationIDs))
    }

    public func apply(_ c: RecordingCategory) {
        name = c.name
        emoji = c.emoji
        symbol = c.symbol
        colorHex = c.colorHex
        instructions = c.instructions
        destinationIDs = c.destinationIDs.sorted()
    }
}

extension LibraryGlossaryTerm {
    public func snapshot() -> GlossaryTerm {
        GlossaryTerm(id: id, term: term, variants: variants, note: note, categoryID: category?.id)
    }

    public func apply(_ g: GlossaryTerm) {
        term = g.term
        variants = g.variants
        note = g.note
    }
}

extension LibraryExport {
    public func snapshot() -> ExportResult {
        ExportResult(destinationID: destinationID, destinationName: destinationName, success: state == .success,
                     message: message, url: externalURL, date: date, skipped: state == .skipped ? true : nil)
    }

    public func apply(_ e: ExportResult) {
        destinationID = e.destinationID
        destinationName = e.destinationName
        state = e.success ? .success : (e.skipped == true ? .skipped : .failed)
        message = e.message
        externalURL = e.url
        date = e.date
    }
}
