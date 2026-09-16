import SwiftUI

/// Eine vom Nutzer definierte Kategorie (z. B. "Vorlesung", "Kundencall").
/// Jede Kategorie hat eigene Anweisungen für die KI-Zusammenfassung.
struct RecordingCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Emoji des Bereichs (optional, damit ältere gespeicherte Kategorien lesbar bleiben)
    var emoji: String?
    var symbol: String
    var colorHex: String
    var instructions: String
    /// Leeres Set = alle aktivierten Ziele verwenden
    var destinationIDs: Set<String> = []

    var color: Color { Color(hex: colorHex) ?? .accentColor }

    /// Emoji zur Anzeige – ältere Kategorien ohne Emoji bekommen eines passend zu ihrem Symbol.
    var displayEmoji: String {
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

    static let defaults: [RecordingCategory] = [
        RecordingCategory(
            name: "Meeting", emoji: "💼", symbol: "person.3.fill", colorHex: "#4F7CFF",
            instructions: """
            Achte besonders darauf, wer welche Position vertreten hat, was entschieden wurde, \
            wer was bis wann erledigt und was noch offen ist.
            """),
        RecordingCategory(
            name: "Vorlesung", emoji: "🎓", symbol: "graduationcap.fill", colorHex: "#9B5CFF",
            instructions: """
            Die Notizen sollen zum Lernen taugen: Erkläre Kernaussagen und Zusammenhänge verständlich, \
            halte Begriffe mit Definitionen, Formeln, Beispiele und Quellen fest. Markiere alles, was als \
            prüfungsrelevant betont wurde. Bei längeren Vorlesungen zum Schluss ein kurzer Abschnitt \
            "## Zum Wiederholen" mit den wichtigsten Punkten.
            """),
        RecordingCategory(
            name: "Kundengespräch", emoji: "🤝", symbol: "briefcase.fill", colorHex: "#16A34A",
            instructions: """
            Achte besonders auf Anliegen und Anforderungen des Kunden, Rahmenbedingungen wie Budget und Zeitplan, \
            Zusagen beider Seiten und die nächsten Schritte.
            """),
        RecordingCategory(
            name: "Interview", emoji: "🎙️", symbol: "mic.fill", colorHex: "#F59E0B",
            instructions: """
            Gib die Sicht der befragten Person möglichst genau wieder. Übernimm prägnante oder wichtige \
            Aussagen als wörtliche Zitate mit Zeitmarke.
            """),
        RecordingCategory(
            name: "Notiz", emoji: "💭", symbol: "note.text", colorHex: "#64748B",
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
    static func migrated(_ categories: [RecordingCategory]) -> [RecordingCategory] {
        categories.map { c in
            guard let name = legacyInstructions[c.instructions] else { return c }
            var updated = c
            updated.instructions = defaults.first { $0.name == name }?.instructions ?? ""
            return updated
        }
    }

    /// Emojis zur Auswahl im Editor – nach Themen sortiert, damit man schnell das passende findet.
    static let emojiChoices = [
        "💼", "🤝", "👥", "📞", "🎙️", "🧠", "💡", "📊", "🛠️", "🚀",
        "🎓", "📚", "📐", "🧮", "🧪", "🧬", "⚖️", "💻", "🌍", "📖",
        "💭", "📝", "🩺", "🏠", "❤️", "🎧", "🎬", "🌿", "✈️", "⭐️",
    ]

    static let symbolChoices = [
        "person.3.fill", "graduationcap.fill", "briefcase.fill", "mic.fill", "note.text",
        "phone.fill", "video.fill", "book.fill", "lightbulb.fill", "heart.fill",
        "star.fill", "hammer.fill", "chart.bar.fill", "person.2.wave.2.fill", "brain.head.profile",
        "cart.fill", "stethoscope", "building.2.fill", "leaf.fill", "gamecontroller.fill",
    ]
    /// Kräftige, aber freundliche Farben – sie färben später auch den Fensterhintergrund des Bereichs.
    static let colorChoices = ["#4F7CFF", "#8B5CF6", "#EC4899", "#FF5A4E", "#F59E0B", "#10B981", "#06B6D4", "#64748B"]
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
