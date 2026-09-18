import Foundation

/// Eine Aufnahme mit allem, was bei der Übernahme alter Daten auf einmal gespeichert wird.
public struct LibraryImportItem: Sendable {
    public var recording: Recording
    public var transcript: Transcript?
    public var note: Summary?

    public init(recording: Recording, transcript: Transcript? = nil, note: Summary? = nil) {
        self.recording = recording
        self.transcript = transcript
        self.note = note
    }
}

/// Die Bibliothek: alles, was später über Geräte synchronisiert werden kann (Aufnahmen, Transkripte, Notizen,
/// Exportstatus, Bereiche, Wörterbuch). Audiodateien liegen getrennt im `AudioStore`.
/// Gibt nur Werttypen (Snapshots) und IDs heraus, nie gespeicherte Modellobjekte.
public protocol LibraryRepository: Sendable {
    // MARK: Aufnahmen
    /// Alle Aufnahmen, neueste zuerst – ohne die Transkripte zu laden
    func recordings() async throws -> [Recording]
    func recording(_ id: UUID) async throws -> Recording?
    func recordingIDs() async throws -> Set<UUID>
    func insertRecording(_ recording: Recording) async throws
    /// Ändert die Aufnahme über ihren Snapshot (eigene Felder, Bereich und Exporte). Fortschritt und
    /// Kennzahlen der Notiz werden dabei nicht gespeichert.
    func updateRecording(_ id: UUID, _ change: @escaping @Sendable (inout Recording) -> Void) async throws
    /// Löscht die Aufnahme samt Transkript, Notiz und Exporten
    func deleteRecording(_ id: UUID) async throws

    // MARK: Transkript
    func transcript(for id: UUID) async throws -> Transcript?
    func saveTranscript(_ transcript: Transcript, for id: UUID) async throws
    func deleteTranscript(for id: UUID) async throws

    // MARK: Notiz
    /// Aktuelle Fassung der Notiz
    func note(for id: UUID) async throws -> Summary?
    /// Neues Ergebnis der KI: setzt aktuelle Fassung und KI-Original
    func saveNote(_ note: Summary, for id: UUID) async throws
    /// Vom Nutzer geänderter Text: setzt `editedAt`, das KI-Original bleibt
    func updateNoteText(_ markdown: String, taskCount: Int, for id: UUID) async throws
    /// Verwirft die Änderungen des Nutzers und stellt die Fassung der KI wieder her
    @discardableResult
    func restoreGeneratedNote(for id: UUID) async throws -> Summary?
    func deleteNote(for id: UUID) async throws
    /// Ersetzt eine falsch erkannte Schreibweise in Titel, Notiz und Transkript einer Aufnahme
    func correctTerm(wrong: String, right: String, for id: UUID) async throws

    // MARK: Export
    func setExports(_ exports: [ExportResult], for id: UUID) async throws

    // MARK: Bereiche
    /// In der gespeicherten Reihenfolge
    func categories() async throws -> [RecordingCategory]
    /// Neuer Bereich am Ende (oder an `sortIndex`)
    func insertCategory(_ category: RecordingCategory, sortIndex: Int?) async throws
    func updateCategory(_ category: RecordingCategory) async throws
    /// Aufnahmen des Bereichs bleiben erhalten und verlieren nur die Zuordnung
    func deleteCategory(_ id: UUID) async throws
    func reorderCategories(_ ids: [UUID]) async throws

    // MARK: Wörterbuch
    func glossaryTerms() async throws -> [GlossaryTerm]
    func insertGlossaryTerm(_ term: GlossaryTerm) async throws
    func updateGlossaryTerm(_ term: GlossaryTerm) async throws
    func deleteGlossaryTerm(_ id: UUID) async throws

    // MARK: Suche
    /// Aufnahmen, deren Titel, Notiz oder Transkript den Suchbegriff enthält
    /// (Groß-/Kleinschreibung, Akzente und Umlaut-Umschreibungen egal; siehe `SearchText`)
    func searchRecordingIDs(matching query: String) async throws -> Set<UUID>

    // MARK: Übernahme
    /// Speichert mehrere Aufnahmen in einem Schritt; bereits vorhandene IDs werden übersprungen.
    /// Liefert die Anzahl der neu angelegten Aufnahmen.
    func importItems(_ items: [LibraryImportItem]) async throws -> Int
}
