import Foundation

/// Ablage als Dateien: ein Ordner pro Aufnahme mit meta.json, transcript.json, summary.md(.json) und Audio.
public struct FileRecordingRepository: RecordingRepository {
    public let storage: Storage

    public init(storage: Storage = .standard) {
        self.storage = storage
    }

    private var fm: FileManager { .default }
    private func summaryJSONURL(_ id: UUID) -> URL { storage.summaryURL(id).appendingPathExtension("json") }

    // MARK: Aufnahmen

    public func loadRecordings() -> [Recording] {
        let dirs = (try? fm.contentsOfDirectory(at: storage.recordingsDir, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            if let r = Storage.load(Recording.self, from: dir.appendingPathComponent("meta.json")) { return r }
            // Leere Überbleibsel gelöschter Aufnahmen entfernen
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            if contents.allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(at: dir) }
            return nil
        }
    }

    public func insert(_ recording: Recording) {
        Storage.save(recording, to: storage.metaURL(recording.id))
    }

    public func update(_ recording: Recording) {
        Storage.save(recording, to: storage.metaURL(recording.id))
    }

    public func delete(_ id: UUID) {
        try? fm.removeItem(at: storage.folder(for: id))
    }

    public func exists(_ id: UUID) -> Bool {
        fm.fileExists(atPath: storage.metaURL(id).path)
    }

    // MARK: Transkript

    public func transcript(for id: UUID) -> Transcript? {
        Storage.load(Transcript.self, from: storage.transcriptURL(id))
    }

    public func saveTranscript(_ transcript: Transcript, for id: UUID) {
        Storage.save(transcript, to: storage.transcriptURL(id))
    }

    public func deleteTranscript(for id: UUID) {
        try? fm.removeItem(at: storage.transcriptURL(id))
    }

    // MARK: Zusammenfassung

    public func summary(for id: UUID) -> Summary? {
        Storage.load(Summary.self, from: summaryJSONURL(id))
    }

    public func saveSummary(_ summary: Summary, for id: UUID) {
        Storage.save(summary, to: summaryJSONURL(id))
        try? ("# \(summary.title)\n\n" + summary.markdown).write(to: storage.summaryURL(id), atomically: true, encoding: .utf8)
    }

    public func deleteSummary(for id: UUID) {
        try? fm.removeItem(at: storage.summaryURL(id))
        try? fm.removeItem(at: summaryJSONURL(id))
    }

    // MARK: Audio

    public func folderURL(for id: UUID) -> URL { storage.folder(for: id) }
    public func createFolder(for id: UUID) { storage.createFolder(for: id) }
    public func micURL(for id: UUID) -> URL { storage.micURL(id) }
    public func systemURL(for id: UUID) -> URL { storage.systemURL(id) }
    public func mixURL(for id: UUID) -> URL { storage.mixURL(id) }

    public func importedAudioURL(for id: UUID, fileName: String) -> URL {
        storage.folder(for: id).appendingPathComponent(fileName)
    }

    public func importAudio(from source: URL, for id: UUID) throws -> String {
        let dest = importedAudioURL(for: id, fileName: "import.\(source.pathExtension)")
        storage.createFolder(for: id)
        try fm.copyItem(at: source, to: dest)
        return dest.lastPathComponent
    }

    public func deleteAudio(for recording: Recording) {
        let id = recording.id
        var urls = [storage.micURL(id), storage.systemURL(id), storage.mixURL(id)]
        if let imported = recording.importedFileName {
            urls.append(importedAudioURL(for: id, fileName: imported))
        }
        for url in urls where fm.fileExists(atPath: url.path) {
            do { try fm.removeItem(at: url) }
            catch { Log.error("Audiodatei nicht gelöscht (\(url.lastPathComponent)): \(error.localizedDescription)") }
        }
    }

    public func hasAudio(_ recording: Recording) -> Bool {
        let id = recording.id
        if let imported = recording.importedFileName {
            return fm.fileExists(atPath: importedAudioURL(for: id, fileName: imported).path)
        }
        return fm.fileExists(atPath: storage.micURL(id).path) || fm.fileExists(atPath: storage.mixURL(id).path)
    }
}
