import EarnoteCore
import Foundation

/// Ziele am iPhone: alles aus dem Kern (Notion, Obsidian, Markdown-Ordner, Logseq, Todoist) plus Apple Erinnerungen.
/// Apple Notizen, Bear, Craft und Things fehlen: Sie gehen nur über AppleScript oder das Öffnen der App,
/// und das klappt nicht, während Earnote im Hintergrund arbeitet – dafür gibt es das Teilen-Menü.
struct PhoneDestinations: DestinationProvider {
    private let core = CoreDestinations()

    var all: [DestinationInfo] {
        core.all + [
            DestinationInfo(id: RemindersDestination.id, name: String(localized: "Apple Erinnerungen"), symbol: "checklist",
                            detail: String(localized: "Offene Aufgaben aus der Notiz, je Bereich eine eigene Liste.")),
        ]
    }

    func make(_ id: String) -> (any Destination)? {
        if id == RemindersDestination.id { return RemindersDestination() }
        guard let destination = core.make(id) else { return nil }
        return FolderAccess.keyPath(for: id) == nil ? destination : ScopedFolderDestination(id: id, inner: destination)
    }

    func setupProblem(_ id: String, _ s: DestinationSettings) -> String? {
        core.setupProblem(id, s)
    }
}

/// Ordner außerhalb der App (iCloud Drive, Obsidian-Tresor) darf iOS nur mit einer gespeicherten Freigabe
/// (Lesezeichen) öffnen. Der Pfad in den Einstellungen dient nur der Anzeige und der Prüfung „eingerichtet?“.
enum FolderAccess {
    static func keyPath(for id: String) -> WritableKeyPath<DestinationSettings, String>? {
        switch id {
        case ObsidianDestination.id: \.obsidianVaultPath
        case MarkdownDestination.id: \.markdownFolderPath
        case LogseqDestination.id: \.logseqGraphPath
        default: nil
        }
    }

    private static func key(_ id: String) -> String { "folderBookmark.\(id)" }

    /// Nach der Auswahl im Dateien-Dialog: Freigabe merken
    static func remember(_ url: URL, for id: String, defaults: UserDefaults = .standard) -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else { return false }
        defaults.set(data, forKey: key(id))
        return true
    }

    static func forget(_ id: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(id))
    }

    /// Den gemerkten Ordner öffnen; die Freigabe gilt, solange `body` läuft
    static func withFolder<T>(for id: String, defaults: UserDefaults = .standard,
                              _ body: (URL) async throws -> T) async throws -> T {
        guard let data = defaults.data(forKey: key(id)) else {
            throw DestinationNotConfigured(hint: String(localized: "Wähle den Ordner in den Einstellungen unter „Export“ noch einmal aus."))
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
            throw DestinationNotConfigured(hint: String(localized: "Kein Zugriff mehr auf den Ordner – wähle ihn unter „Export“ noch einmal aus."))
        }
        defer { url.stopAccessingSecurityScopedResource() }
        if stale, let fresh = try? url.bookmarkData() { defaults.set(fresh, forKey: key(id)) }
        return try await body(url)
    }
}

/// Führt ein Datei-Ziel mit geöffneter Ordnerfreigabe aus. Ohne gewählten Ordner schreibt der Markdown-Export
/// in den eigenen Ordner der App (in „Dateien“ unter „Auf meinem iPhone › Earnote“).
struct ScopedFolderDestination: Destination {
    let id: String
    let inner: any Destination

    func export(_ payload: ExportPayload) async throws -> String? {
        guard let keyPath = FolderAccess.keyPath(for: id), !payload.settings[keyPath: keyPath].isEmpty else {
            return try await inner.export(payload)
        }
        return try await FolderAccess.withFolder(for: id) { url in
            var p = payload
            p.settings[keyPath: keyPath] = url.path
            return try await inner.export(p)
        }
    }
}
