import AppKit
import EarnoteCore
import Foundation

/// Alle Ziele der Mac-App: die gemeinsamen aus EarnoteCore plus Apple Notizen, Bear und Craft
/// (AppleScript bzw. `NSWorkspace`).
struct AppDestinations: DestinationProvider {
    private let core = CoreDestinations()

    var all: [DestinationInfo] {
        let shared = core.all
        func coreInfo(_ id: String) -> [DestinationInfo] { shared.filter { $0.id == id } }
        return coreInfo(NotionDestination.id) + coreInfo(ObsidianDestination.id) + [
            DestinationInfo(id: AppleNotesDestination.id, name: "Apple Notizen", symbol: "note.text",
                            detail: "Notiz im Ordner deiner Wahl, synchron über iCloud."),
        ] + coreInfo(MarkdownDestination.id) + [
            DestinationInfo(id: BearDestination.id, name: "Bear", symbol: "pawprint.fill",
                            detail: "Neue Notiz in Bear mit Tags."),
            DestinationInfo(id: CraftDestination.id, name: "Craft", symbol: "doc.richtext.fill",
                            detail: "Neues Dokument in einem Craft-Space."),
        ]
    }

    func make(_ id: String) -> (any Destination)? {
        switch id {
        case AppleNotesDestination.id: return AppleNotesDestination()
        case BearDestination.id: return BearDestination()
        case CraftDestination.id: return CraftDestination()
        default: return core.make(id)
        }
    }

    func setupProblem(_ id: String, _ s: DestinationSettings) -> String? {
        switch id {
        case CraftDestination.id:
            if s.craftSpaceID.isEmpty { return "Craft-Space-ID fehlt" }
        case BearDestination.id:
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.shinyfrog.bear") == nil { return "Bear ist nicht installiert" }
        default:
            return core.setupProblem(id, s)
        }
        return nil
    }
}

/// Kurzform für die Oberfläche
enum Destinations {
    static var all: [DestinationInfo] { AppDestinations().all }
    static func info(_ id: String) -> DestinationInfo? { AppDestinations().info(id) }
    static func setupProblem(_ id: String, _ s: DestinationSettings) -> String? { AppDestinations().setupProblem(id, s) }
}

// MARK: - App-basierte Ziele

struct AppleNotesDestination: Destination {
    static let id = "applenotes"

    func export(_ p: ExportPayload) async throws -> String? {
        var md = "# \(p.title)\n\n> \(MarkdownDocument.metaLine(p))\n\n"
        if let s = p.summary { md += s.markdown + "\n\n" }
        if p.includeTranscript { md += "## Transkript\n\n" + p.transcript }
        let html = MarkdownDocument.html(md)
        let folder = p.settings.appleNotesFolder.isEmpty ? AppInfo.name : p.settings.appleNotesFolder

        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let script = """
        tell application "Notes"
            set acc to default account
            if not (exists folder \(q(folder)) of acc) then
                make new folder at acc with properties {name:\(q(folder))}
            end if
            set n to make new note at folder \(q(folder)) of acc with properties {body:\(q(html))}
            return id of n
        end tell
        """
        return try await MainActor.run { () throws -> String? in
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
                throw LLMError(message: "Apple Notizen: \(msg). Bitte in Systemeinstellungen › Datenschutz › Automation erlauben.")
            }
            _ = result
            return nil
        }
    }
}

struct BearDestination: Destination {
    static let id = "bear"

    func export(_ p: ExportPayload) async throws -> String? {
        var payload = p
        if p.transcript.count > 150_000 { payload.settings.includeTranscript = false }
        let body = MarkdownDocument.build(payload, frontmatter: false)
            .components(separatedBy: "\n").dropFirst().joined(separator: "\n")   // Titel übergibt Bear separat
        var tags = p.settings.bearTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let c = p.category { tags.append("\(AppInfo.name.lowercased())/\(MarkdownDocument.tag(c.name))") }
        var comps = URLComponents(string: "bear://x-callback-url/create")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: p.title),
            URLQueryItem(name: "text", value: body),
            URLQueryItem(name: "tags", value: tags.joined(separator: ",")),
            URLQueryItem(name: "open_note", value: "no"),
            URLQueryItem(name: "show_window", value: "no"),
        ]
        guard let url = comps.url else { throw LLMError(message: "Bear-Link konnte nicht erstellt werden") }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        if !ok { throw LLMError(message: "Bear konnte nicht geöffnet werden") }
        return nil
    }
}

struct CraftDestination: Destination {
    static let id = "craft"

    func export(_ p: ExportPayload) async throws -> String? {
        guard !p.settings.craftSpaceID.isEmpty else { throw DestinationNotConfigured(hint: "Noch keine Craft-Space-ID eingetragen.") }
        var payload = p
        if p.transcript.count > 150_000 { payload.settings.includeTranscript = false }
        let body = MarkdownDocument.build(payload, frontmatter: false)
            .components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        var comps = URLComponents(string: "craftdocs://createdocument")!
        comps.queryItems = [
            URLQueryItem(name: "spaceId", value: p.settings.craftSpaceID),
            URLQueryItem(name: "title", value: p.title),
            URLQueryItem(name: "content", value: body),
            URLQueryItem(name: "folderId", value: ""),
        ]
        guard let url = comps.url else { throw LLMError(message: "Craft-Link konnte nicht erstellt werden") }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        if !ok { throw LLMError(message: "Craft konnte nicht geöffnet werden") }
        return nil
    }
}
