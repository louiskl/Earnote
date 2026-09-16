import Foundation

/// Einfaches Protokoll als Textdatei im Datenordner.
public enum Log {
    private static let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    private static let lock = NSLock()
    nonisolated(unsafe) private static var customURL: URL?

    /// Protokolldatei. Standard: earnote.log im Datenordner; Tests leiten sie in einen temporären Ordner um.
    public static var url: URL {
        get {
            lock.lock(); defer { lock.unlock() }
            return customURL ?? Storage.standard.root.appendingPathComponent(AppInfo.logFileName)
        }
        set {
            lock.lock(); defer { lock.unlock() }
            customURL = newValue
        }
    }

    public static func info(_ msg: String) { write("INFO", msg) }
    public static func error(_ msg: String) { write("FEHLER", msg) }

    private static func write(_ level: String, _ msg: String) {
        let line = "[\(formatter.string(from: Date()))] \(level): \(msg)\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        let url = url
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
