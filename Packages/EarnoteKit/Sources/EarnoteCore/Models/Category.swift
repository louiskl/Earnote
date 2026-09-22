import Foundation

/// Eine vom Nutzer definierte Kategorie (z. B. "Vorlesung", "Kundencall").
/// Jede Kategorie hat eigene Anweisungen für die KI-Zusammenfassung.
public struct RecordingCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    /// Emoji des Bereichs (optional, damit ältere gespeicherte Kategorien lesbar bleiben)
    public var emoji: String?
    public var symbol: String
    public var colorHex: String
    public var instructions: String
    /// Leeres Set = alle aktivierten Ziele verwenden
    public var destinationIDs: Set<String> = []

    public init(id: UUID = UUID(), name: String, emoji: String? = nil, symbol: String, colorHex: String,
                instructions: String, destinationIDs: Set<String> = []) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.symbol = symbol
        self.colorHex = colorHex
        self.instructions = instructions
        self.destinationIDs = destinationIDs
    }

    /// Emoji zur Anzeige – ältere Kategorien ohne Emoji bekommen eines passend zu ihrem Symbol.
    public var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return Self.emojiForSymbol[symbol] ?? "🗂️"
    }

    private static let emojiForSymbol: [String: String] = [
        "person.3.fill": "💼", "graduationcap.fill": "🎓", "briefcase.fill": "🤝", "mic.fill": "🎙️",
        "note.text": "💭", "phone.fill": "📞", "video.fill": "🎬", "book.fill": "📚", "lightbulb.fill": "💡",
        "heart.fill": "❤️", "star.fill": "⭐️", "hammer.fill": "🛠️", "chart.bar.fill": "📊",
        "person.2.wave.2.fill": "👥", "brain.head.profile": "🧠", "cart.fill": "🛒", "stethoscope": "🩺",
        "building.2.fill": "🏢", "leaf.fill": "🌿", "gamecontroller.fill": "🎮",
    ]

    /// Feste IDs für die Standardbereiche: Richten zwei Macs Earnote ein, legt jeder sie an – mit gleicher ID
    /// erkennt der iCloud-Abgleich sie als dieselben, auch wenn einer inzwischen umbenannt wurde.
    /// (Ältere Installationen haben zufällige IDs; dort greift der Name, siehe `LibraryMerge`.)
    static func defaultID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "EA7E0000-0000-4000-8000-%012ld", number))!
    }

    public static let defaults: [RecordingCategory] = [
        RecordingCategory(
            id: defaultID(1), name: "Meeting", emoji: "💼", symbol: "person.3.fill", colorHex: "#4F7CFF",
            instructions: """
            Achte besonders darauf, wer welche Position vertreten hat, was entschieden wurde, \
            wer was bis wann erledigt und was noch offen ist.
            """),
        RecordingCategory(
            id: defaultID(2), name: "Vorlesung", emoji: "🎓", symbol: "graduationcap.fill", colorHex: "#9B5CFF",
            instructions: """
            Die Notizen sollen zum Lernen taugen: Erkläre Kernaussagen und Zusammenhänge verständlich, \
            halte Begriffe mit Definitionen, Formeln, Beispiele und Quellen fest. Markiere alles, was als \
            prüfungsrelevant betont wurde. Bei längeren Vorlesungen zum Schluss ein kurzer Abschnitt \
            "## Zum Wiederholen" mit den wichtigsten Punkten.
            """),
        RecordingCategory(
            id: defaultID(3), name: "Kundengespräch", emoji: "🤝", symbol: "briefcase.fill", colorHex: "#16A34A",
            instructions: """
            Achte besonders auf Anliegen und Anforderungen des Kunden, Rahmenbedingungen wie Budget und Zeitplan, \
            Zusagen beider Seiten und die nächsten Schritte.
            """),
        RecordingCategory(
            id: defaultID(4), name: "Interview", emoji: "🎙️", symbol: "mic.fill", colorHex: "#F59E0B",
            instructions: """
            Gib die Sicht der befragten Person möglichst genau wieder. Übernimm prägnante oder wichtige \
            Aussagen als wörtliche Zitate mit Zeitmarke.
            """),
        RecordingCategory(
            id: defaultID(5), name: "Notiz", emoji: "💭", symbol: "note.text", colorHex: "#64748B",
            instructions: """
            Meist eine kurze Sprachnotiz: Halte die Gedanken knapp in eigenen Worten fest, Aufgaben als Checkliste.
            """),
    ]

    /// Anweisungen früherer Versionen, die feste Abschnitte vorgaben. Wurden sie nicht verändert,
    /// werden sie durch die neuen Standardtexte ersetzt (Schlüssel: alter Text, Wert: Kategoriename).
    private static let legacyInstructions: [String: String] = [
        "Schwerpunkt: Entscheidungen, Aufgaben (mit verantwortlicher Person und Frist, falls genannt) und nächste Schritte.\nAbschnitte: Kurzfassung, Themen, Entscheidungen, Aufgaben, Nächste Schritte, Offene Fragen.": "Meeting",
        "Schwerpunkt: Lernstoff. Erkläre Inhalte so, dass man damit für eine Prüfung lernen kann.\nAbschnitte: Kurzfassung, Gliederung der Vorlesung, Kernaussagen, Begriffe & Definitionen,\nNormen/Formeln/Quellen, Prüfungshinweise (alles, was die Lehrkraft als prüfungsrelevant betont hat),\nLernzettel (die wichtigsten Punkte zum Wiederholen), Aufgaben/Termine.": "Vorlesung",
        "Schwerpunkt: Anforderungen und Wünsche des Kunden, Budget/Zeitrahmen, Zusagen, nächste Schritte.\nAbschnitte: Kurzfassung, Anforderungen, Offene Punkte, Vereinbarungen, Aufgaben, Nächste Schritte.": "Kundengespräch",
        "Schwerpunkt: Aussagen der befragten Person, wichtige Zitate (wörtlich, mit Zeitmarke), Erkenntnisse.\nAbschnitte: Kurzfassung, Kernaussagen, Zitate, Erkenntnisse, Offene Fragen.": "Interview",
        "Kurze, klare Zusammenfassung der gesprochenen Gedanken mit Aufgaben, falls vorhanden.\nAbschnitte: Kurzfassung, Punkte, Aufgaben.": "Notiz",
        "Abschnitte: Kurzfassung, Themen, Aufgaben, Nächste Schritte.": "",
    ]

    /// Ersetzt unveränderte alte Standardanweisungen durch die aktuellen.
    public static func migrated(_ categories: [RecordingCategory]) -> [RecordingCategory] {
        categories.map { c in
            guard let name = legacyInstructions[c.instructions] else { return c }
            var updated = c
            updated.instructions = defaults.first { $0.name == name }?.instructions ?? ""
            return updated
        }
    }

    /// Emojis zur Auswahl im Editor – nach Themen sortiert, damit man schnell das passende findet.
    public static let emojiChoices = [
        "💼", "🤝", "👥", "📞", "🎙️", "🧠", "💡", "📊", "🛠️", "🚀",
        "🎓", "📚", "📐", "🧮", "🧪", "🧬", "⚖️", "💻", "🌍", "📖",
        "💭", "📝", "🩺", "🏠", "❤️", "🎧", "🎬", "🌿", "✈️", "⭐️",
    ]

    public static let symbolChoices = [
        "person.3.fill", "graduationcap.fill", "briefcase.fill", "mic.fill", "note.text",
        "phone.fill", "video.fill", "book.fill", "lightbulb.fill", "heart.fill",
        "star.fill", "hammer.fill", "chart.bar.fill", "person.2.wave.2.fill", "brain.head.profile",
        "cart.fill", "stethoscope", "building.2.fill", "leaf.fill", "gamecontroller.fill",
    ]
    /// Kräftige, aber freundliche Farben – sie färben später auch den Fensterhintergrund des Bereichs.
    public static let colorChoices = ["#4F7CFF", "#8B5CF6", "#EC4899", "#FF5A4E", "#F59E0B", "#10B981", "#06B6D4", "#64748B"]
}
