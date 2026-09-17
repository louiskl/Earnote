import Foundation

/// Liest die Bibliothek im alten Dateiformat (bis Version 0.2): ein Ordner pro Aufnahme mit meta.json,
/// transcript.json und summary.md.json. Nur für die einmalige Übernahme; schreibt und löscht nichts.
public struct LegacyFileLibraryReader: Sendable {
    public let storage: Storage

    public init(storage: Storage = .standard) {
        self.storage = storage
    }

    /// Eine Aufnahme im alten Format
    public struct Entry: Sendable {
        public var recording: Recording
        public var transcript: Transcript?
        public var summary: Summary?
    }

    public enum ReadError: LocalizedError, Sendable {
        case unreadable(folder: String, file: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let folder, let file, let reason): return "\(folder)/\(file) nicht lesbar: \(reason)"
            }
        }
    }

    private var fm: FileManager { .default }

    /// Ordner, die eine meta.json enthalten (andere Ordner sind Überbleibsel und werden ignoriert)
    public func recordingFolders() -> [URL] {
        let dirs = (try? fm.contentsOfDirectory(at: storage.root.appendingPathComponent("Recordings", isDirectory: true),
                                                includingPropertiesForKeys: nil)) ?? []
        return dirs.filter { fm.fileExists(atPath: $0.appendingPathComponent("meta.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Nur die Metadaten lesen (schnell, z. B. um schon übernommene Aufnahmen zu überspringen)
    public func readRecording(in folder: URL) throws -> Recording {
        try decode(Recording.self, folder: folder, file: "meta.json")
    }

    /// Transkript und Notiz dazu lesen. Existiert eine Datei, ist aber kaputt, gilt die ganze Aufnahme als nicht lesbar –
    /// sonst würde sie ohne Transkript übernommen und beim nächsten Versuch nicht mehr ergänzt.
    public func readEntry(in folder: URL, recording: Recording) throws -> Entry {
        let transcript = try decodeIfPresent(Transcript.self, folder: folder, file: "transcript.json")
        let summary = try decodeIfPresent(Summary.self, folder: folder, file: "summary.md.json")
        return Entry(recording: recording, transcript: transcript, summary: summary)
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, folder: URL, file: String) throws -> T? {
        guard fm.fileExists(atPath: folder.appendingPathComponent(file).path) else { return nil }
        return try decode(type, folder: folder, file: file)
    }

    private func decode<T: Decodable>(_ type: T.Type, folder: URL, file: String) throws -> T {
        do {
            let data = try Data(contentsOf: folder.appendingPathComponent(file))
            return try Storage.decoder.decode(T.self, from: data)
        } catch {
            throw ReadError.unreadable(folder: folder.lastPathComponent, file: file, reason: String(describing: error))
        }
    }
}
