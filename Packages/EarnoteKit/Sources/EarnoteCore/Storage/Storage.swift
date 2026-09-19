import Foundation

/// Dateiablage unter einem Wurzelordner. Standard: ~/Library/Application Support/<AppInfo.supportFolderName>.
/// Tests übergeben einen temporären Ordner.
public struct Storage: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Der Datenordner der App
    public static let standard: Storage = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = supportRoot(in: base, defaults: .standard)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Storage(root: url)
    }()

    /// Nach einem fehlgeschlagenen Umzug weiter die alten Daten verwenden. Sonst würde der
    /// App-Start einen leeren Zielordner anlegen und den erneuten Umzug beim nächsten Start blockieren.
    public static func supportRoot(in base: URL, defaults: UserDefaults) -> URL {
        let new = base.appendingPathComponent(AppInfo.supportFolderName, isDirectory: true)
        let old = base.appendingPathComponent(AppInfo.legacySupportFolderName, isDirectory: true)
        if defaults.integer(forKey: "legacyMigrationVersion") < 1,
           !FileManager.default.fileExists(atPath: new.path),
           FileManager.default.fileExists(atPath: old.path) { return old }
        return new
    }

    /// Freier Platz auf dem Laufwerk des Datenordners (Bytes; nil = unbekannt)
    public var availableBytes: Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public var recordingsDir: URL { dir("Recordings") }
    public var modelsDir: URL { dir("Models") }

    public func dir(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Ordner einer Aufnahme. Wird erst beim Schreiben angelegt (`createFolder`/`save`), damit nach dem
    /// Löschen nicht durch bloßes Nachsehen wieder ein leerer Ordner entsteht.
    public func folder(for id: UUID) -> URL {
        recordingsDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func createFolder(for id: UUID) {
        try? FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
    }

    public func micURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("mic.caf") }
    public func systemURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("system.caf") }
    public func mixURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("audio.wav") }
    public func transcriptURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("transcript.json") }
    public func summaryURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("summary.md") }
    public func metaURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("meta.json") }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
        }
        catch { Log.error("Speichern fehlgeschlagen: \(url.lastPathComponent): \(error)") }
    }

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
