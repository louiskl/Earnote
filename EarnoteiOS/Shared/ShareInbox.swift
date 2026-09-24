import Foundation

/// Übergabe aus der Share Extension („Mit Earnote teilen“ in Sprachmemos, WhatsApp, Dateien): Die Erweiterung legt
/// die Dateien in den gemeinsamen App-Group-Ordner, die App übernimmt sie beim nächsten Öffnen in die Bibliothek.
enum ShareInbox {
    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Kopiert eine geteilte Datei in einen eigenen Unterordner – zwei Dateien mit gleichem Namen überschreiben sich nicht.
    /// Der Ordnername beginnt mit der Uhrzeit, damit die Reihenfolge ohne Datei-Zeitstempel erhalten bleibt
    /// (die Erweiterung braucht so keinen Eintrag im Datenschutz-Manifest).
    static func add(_ file: URL) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        let name = String(format: "%015.0f-%@", Date().timeIntervalSince1970 * 1000, UUID().uuidString)
        // Erst unter anderem Namen kopieren, dann umbenennen – so übernimmt die App nie eine halbe Datei
        let partial = folder.appendingPathComponent(name + ".partial", isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: partial.appendingPathComponent(file.lastPathComponent))
        try FileManager.default.moveItem(at: partial, to: folder.appendingPathComponent(name, isDirectory: true))
    }

    /// Wartende Dateien, die älteste zuerst
    static func pending() -> [URL] {
        let manager = FileManager.default
        guard let folder, let folders = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return folders.filter { $0.pathExtension != "partial" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil).first }
    }

    /// Nach der Übernahme: Datei samt Unterordner löschen
    static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}
