import Foundation

/// Was die Widgets zeigen – die App schreibt es in den gemeinsamen App-Group-Ordner, die Widget-Erweiterung liest es.
/// Bewusst nur fertige Texte: Die Erweiterung kennt weder Bibliothek noch Kern.
struct WidgetSnapshot: Codable {
    struct Note: Codable, Identifiable {
        var id: UUID
        var title: String
        var area: String?
        var emoji: String?
        var colorHex: String?
        var preview: String?
        var date: Date
        var openTasks: Int
    }

    struct OpenTask: Codable, Identifiable {
        var id: String
        var recordingID: UUID
        var text: String
    }

    var notes: [Note] = []
    var tasks: [OpenTask] = []
    var openTaskCount = 0
    var isRecording = false

    static let appGroup = "group.app.earnote.Earnote"
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("widgets.json")
    }

    static func load() -> WidgetSnapshot {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Links aus Widgets in die App
enum EarnoteLink {
    static let scheme = "earnote"
    static func recording(_ id: UUID) -> URL { URL(string: "\(scheme)://recording/\(id.uuidString)")! }
    static let tasks = URL(string: "\(scheme)://tasks")!
    static let record = URL(string: "\(scheme)://record")!
}
