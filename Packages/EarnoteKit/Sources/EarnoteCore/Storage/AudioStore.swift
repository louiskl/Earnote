import Foundation

/// Audiodateien der Aufnahmen. Sie bleiben immer lokal auf dem Gerät und werden nie synchronisiert.
public protocol AudioStore: Sendable {
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
    /// Löscht Mikrofon-, Systemton-, Misch- und importierte Audiodatei
    func deleteAudio(for recording: Recording)
    func hasAudio(_ recording: Recording) -> Bool
    /// Löscht den ganzen Ordner der Aufnahme
    func deleteFolder(for id: UUID)
}

/// Audio als Dateien unter `<Datenordner>/Recordings/<id>/`
public struct FileAudioStore: AudioStore {
    public let storage: Storage

    public init(storage: Storage = .standard) {
        self.storage = storage
    }

    private var fm: FileManager { .default }

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

    public func deleteFolder(for id: UUID) {
        try? fm.removeItem(at: storage.folder(for: id))
    }
}
