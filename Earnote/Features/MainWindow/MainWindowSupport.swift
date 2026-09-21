import AppKit
import EarnoteCore
import SwiftUI

/// Notiz, Transkript oder beides nebeneinander im Detailbereich
enum DetailMode: String, CaseIterable {
    case note, transcript, both

    var label: LocalizedStringKey {
        switch self {
        case .note: return "Notiz"
        case .transcript: return "Transkript"
        case .both: return "Beides"
        }
    }

    var showsNote: Bool { self != .transcript }
    var showsTranscript: Bool { self != .note }
}

/// Eine UUID, die sich als `item` an ein Blatt übergeben lässt
struct IdentifiableID: Identifiable {
    let id: UUID
}

/// Durch die Fundstellen der Suche blättern (⌘G). Die Ansicht meldet, wie viele es sind;
/// das Menü zählt weiter, die Ansicht scrollt zur gezählten Stelle.
@MainActor
@Observable
final class SearchCursor {
    private(set) var count = 0
    /// Nummer der Fundstelle, zu der die Ansicht scrollen soll
    private(set) var index = 0

    /// Neue Suche oder neues Transkript: von vorn zählen
    func reset(count: Int) {
        self.count = count
        index = 0
    }

    func next() {
        guard count > 0 else { return }
        index = (index + 1) % count
    }

    func previous() {
        guard count > 0 else { return }
        index = (index + count - 1) % count
    }
}

/// Darstellung einer gespeicherten Aufnahme – dieselben Regeln wie beim Snapshot `Recording`.
extension LibraryRecording {
    /// Titel der Notiz, außer die Aufnahme wurde vom Nutzer benannt
    var displayTitle: String {
        if !isTitleCustom, let noteTitle = note?.title, !noteTitle.isEmpty { return noteTitle }
        return title
    }

    /// Aufgenommene Zeit ohne Pausen
    var duration: TimeInterval { max(0, (endedAt ?? Date()).timeIntervalSince(startedAt) - pausedDuration) }

    var isBusy: Bool { status.isBusy }
}

extension LibraryCategory {
    var displayEmoji: String { snapshot().displayEmoji }
}

/// Fundstellen der Suche im Text hervorheben – in der Notiz und im Transkript.
enum SearchHighlight {
    static func attributed(_ text: String, query: String, inlineMarkdown: Bool = false) -> AttributedString {
        var result: AttributedString
        if inlineMarkdown {
            result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(text)
        } else {
            result = AttributedString(text)
        }
        let ranges = SearchText.ranges(in: String(result.characters), query: query)
        guard !ranges.isEmpty else { return result }
        for range in ranges {
            guard let attributed = Range(range, in: result) else { continue }
            result[attributed].backgroundColor = Color(nsColor: .findHighlightColor)
            result[attributed].foregroundColor = .black
        }
        return result
    }

    /// Enthält der Text eine Fundstelle?
    static func matches(_ text: String, query: String) -> Bool {
        !SearchText.normalized(query).isEmpty && SearchText.matches(text, query: query)
    }
}

enum MainWindowFormat {
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func dateAndTime(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }

    /// Dauer gut lesbar und nicht mit einer Uhrzeit zu verwechseln: „48 Sek.“, „36 Min.“, „1 Std., 28 Min.“
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) Sek." }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Name einer Sprache aus den Einstellungen („de“ → „Deutsch“)
    static func language(_ code: String) -> String {
        AppSettings.languages.first { $0.code == code }?.name ?? code
    }

    /// Pegel (Effektivwert) auf 0…1 in Dezibel: −50 dB leer, 0 dB voll
    static func level(_ rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        return min(1, max(0, (Double(20 * log10(rms)) + 50) / 50))
    }
}

/// Öffnet das Hauptfenster – oder holt ein offenes nach vorn, statt ein weiteres anzulegen.
@MainActor
enum MainWindowOpener {
    static func showOrOpen(_ openWindow: OpenWindowAction) {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Teilen-Menü von macOS für einen Text, angebunden an das aktive Fenster (für den Menübefehl „Teilen …“).
@MainActor
enum SharePicker {
    static func show(_ text: String) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [text])
        let anchor = NSRect(x: view.bounds.maxX - 60, y: view.bounds.maxY - 8, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}

/// Auswahl von Audiodateien für den Import
@MainActor
enum AudioImportPanel {
    static func pick() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.message = "Audiodateien zum Transkribieren auswählen"
        return panel.runModal() == .OK ? panel.urls : []
    }
}

extension Notification.Name {
    /// Einrichtungsassistent erneut zeigen (aus den Einstellungen)
    static let showOnboarding = Notification.Name("\(AppInfo.bundleIdentifier).showOnboarding")
}
