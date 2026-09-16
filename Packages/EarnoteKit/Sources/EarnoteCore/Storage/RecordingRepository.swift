import Foundation

/// Speicher für Aufnahmen und ihre Dateien. Pipeline und Bibliothek arbeiten nur über dieses Protokoll,
/// damit die Ablage (heute JSON-Dateien, später SwiftData) getauscht werden kann.
public protocol RecordingRepository: Sendable {
    // MARK: Aufnahmen
    /// Alle gespeicherten Aufnahmen (unsortiert)
    func loadRecordings() -> [Recording]
    func insert(_ recording: Recording)
    func update(_ recording: Recording)
    /// Löscht die Aufnahme mit allen Dateien
    func delete(_ id: UUID)
    func exists(_ id: UUID) -> Bool

    // MARK: Transkript
    func transcript(for id: UUID) -> Transcript?
    func saveTranscript(_ transcript: Transcript, for id: UUID)
    func deleteTranscript(for id: UUID)

    // MARK: Zusammenfassung
    func summary(for id: UUID) -> Summary?
    func saveSummary(_ summary: Summary, for id: UUID)
    func deleteSummary(for id: UUID)

    // MARK: Audio
    /// Ordner der Aufnahme (z. B. zum Zeigen im Finder)
    func folderURL(for id: UUID) -> URL
    /// Legt den Ordner an, bevor Audio hineingeschrieben wird
    func createFolder(for id: UUID)
    func micURL(for id: UUID) -> URL
    func systemURL(for id: UUID) -> URL
    func mixURL(for id: UUID) -> URL
    func importedAudioURL(for id: UUID, fileName: String) -> URL
    /// Kopiert eine Audiodatei in die Aufnahme und liefert den Dateinamen innerhalb der Aufnahme
    func importAudio(from source: URL, for id: UUID) throws -> String
    /// Löscht Mikrofon-, Systemton-, Misch- und importierte Audiodatei; Transkript und Notizen bleiben
    func deleteAudio(for recording: Recording)
    func hasAudio(_ recording: Recording) -> Bool
}
