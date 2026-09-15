import Foundation

/// Dateiablage: ~/Library/Application Support/Earmark
enum Storage {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Earmark", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var recordingsDir: URL { dir("Recordings") }
    static var modelsDir: URL { dir("Models") }

    static func dir(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folder(for id: UUID) -> URL {
        let url = recordingsDir.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func micURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("mic.caf") }
    static func systemURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("system.caf") }
    static func mixURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("audio.wav") }
    static func transcriptURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("transcript.json") }
    static func summaryURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("summary.md") }
    static func metaURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("meta.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do { try encoder.encode(value).write(to: url, options: .atomic) }
        catch { Log.error("Speichern fehlgeschlagen: \(url.lastPathComponent): \(error)") }
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

enum Log {
    static let url = Storage.root.appendingPathComponent("earmark.log")
    private static let queue = DispatchQueue(label: "earmark.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    static func info(_ msg: String) { write("INFO", msg) }
    static func error(_ msg: String) { write("FEHLER", msg) }

    private static func write(_ level: String, _ msg: String) {
        let line = "[\(formatter.string(from: Date()))] \(level): \(msg)\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
