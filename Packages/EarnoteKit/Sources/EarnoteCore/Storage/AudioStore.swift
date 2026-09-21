import Foundation

/// Wie es um den Speicherplatz steht – entscheidet, ob eine Aufnahme starten darf und wann sie
/// vorsichtshalber beendet wird. Eine Stunde Aufnahme (Mikrofon + Systemton) braucht rund 1 GB.
public enum DiskSpace: Sendable, Equatable {
    /// Genug Platz
    case fine
    /// Wird knapp – Aufnahme läuft, aber mit Hinweis
    case low(freeMB: Int, minutesLeft: Int)
    /// Zu wenig, um verlässlich aufzunehmen
    case critical(freeMB: Int)

    /// Rund 17 MB pro Minute (Mikrofon und Systemton getrennt, dazu die gemischte Datei)
    public static let megabytesPerMinute = 17

    public static func check(availableBytes: Int64?) -> DiskSpace {
        guard let availableBytes else { return .fine }
        let freeMB = Int(availableBytes / 1_048_576)
        if freeMB < 300 { return .critical(freeMB: freeMB) }
        if freeMB < 1_500 { return .low(freeMB: freeMB, minutesLeft: freeMB / megabytesPerMinute) }
        return .fine
    }

    /// Verständlicher Satz für die Oberfläche (nil, wenn alles in Ordnung ist)
    public var message: String? {
        switch self {
        case .fine:
            return nil
        case .low(let freeMB, let minutesLeft):
            return t("Nur noch \(freeMB) MB frei – das reicht für etwa \(minutesLeft) Minuten Aufnahme. Mach etwas Platz, sonst bricht die Aufnahme vorzeitig ab.")
        case .critical(let freeMB):
            return t("Zu wenig Speicherplatz: nur noch \(freeMB) MB frei. Lösche etwas (oder alte Aufnahmen in \(AppInfo.name)) und starte die Aufnahme neu.")
        }
    }
}

/// Audiodateien der Aufnahmen. Sie bleiben immer lokal auf dem Gerät und werden nie synchronisiert.
public protocol AudioStore: Sendable {
    /// Platz auf dem Laufwerk, auf dem die Aufnahmen landen
    var diskSpace: DiskSpace { get }
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
    /// Datei zum Anhören: die gemischte Aufnahme, sonst das Mikrofon, sonst die importierte Datei
    func playbackURL(for recording: Recording) -> URL?
    /// Löscht den ganzen Ordner der Aufnahme
    func deleteFolder(for id: UUID)
}

/// Audio als Dateien unter `<Datenordner>/Recordings/<id>/`
public struct FileAudioStore: AudioStore {
    public let storage: Storage

    public var diskSpace: DiskSpace { DiskSpace.check(availableBytes: storage.availableBytes) }

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

    public func playbackURL(for recording: Recording) -> URL? {
        if let fileName = recording.importedFileName {
            let imported = importedAudioURL(for: recording.id, fileName: fileName)
            if fm.fileExists(atPath: imported.path) { return imported }
        }
        for url in [mixURL(for: recording.id), micURL(for: recording.id)] where fm.fileExists(atPath: url.path) {
            return url
        }
        return nil
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
