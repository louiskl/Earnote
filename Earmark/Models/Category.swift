import SwiftUI

/// Eine vom Nutzer definierte Kategorie (z. B. "Vorlesung", "Kundencall").
/// Jede Kategorie hat eigene Anweisungen für die KI-Zusammenfassung.
struct RecordingCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var colorHex: String
    var instructions: String
    /// Leeres Set = alle aktivierten Ziele verwenden
    var destinationIDs: Set<String> = []

    var color: Color { Color(hex: colorHex) ?? .accentColor }

    static let defaults: [RecordingCategory] = [
        RecordingCategory(
            name: "Meeting", symbol: "person.3.fill", colorHex: "#4F7CFF",
            instructions: """
            Schwerpunkt: Entscheidungen, Aufgaben (mit verantwortlicher Person und Frist, falls genannt) und nächste Schritte.
            Abschnitte: Kurzfassung, Themen, Entscheidungen, Aufgaben, Nächste Schritte, Offene Fragen.
            """),
        RecordingCategory(
            name: "Vorlesung", symbol: "graduationcap.fill", colorHex: "#9B5CFF",
            instructions: """
            Schwerpunkt: Lernstoff. Erkläre Inhalte so, dass man damit für eine Prüfung lernen kann.
            Abschnitte: Kurzfassung, Gliederung der Vorlesung, Kernaussagen, Begriffe & Definitionen,
            Normen/Formeln/Quellen, Prüfungshinweise (alles, was die Lehrkraft als prüfungsrelevant betont hat),
            Lernzettel (die wichtigsten Punkte zum Wiederholen), Aufgaben/Termine.
            """),
        RecordingCategory(
            name: "Kundengespräch", symbol: "briefcase.fill", colorHex: "#16A34A",
            instructions: """
            Schwerpunkt: Anforderungen und Wünsche des Kunden, Budget/Zeitrahmen, Zusagen, nächste Schritte.
            Abschnitte: Kurzfassung, Anforderungen, Offene Punkte, Vereinbarungen, Aufgaben, Nächste Schritte.
            """),
        RecordingCategory(
            name: "Interview", symbol: "mic.fill", colorHex: "#F59E0B",
            instructions: """
            Schwerpunkt: Aussagen der befragten Person, wichtige Zitate (wörtlich, mit Zeitmarke), Erkenntnisse.
            Abschnitte: Kurzfassung, Kernaussagen, Zitate, Erkenntnisse, Offene Fragen.
            """),
        RecordingCategory(
            name: "Notiz", symbol: "note.text", colorHex: "#64748B",
            instructions: """
            Kurze, klare Zusammenfassung der gesprochenen Gedanken mit Aufgaben, falls vorhanden.
            Abschnitte: Kurzfassung, Punkte, Aufgaben.
            """),
    ]

    static let symbolChoices = [
        "person.3.fill", "graduationcap.fill", "briefcase.fill", "mic.fill", "note.text",
        "phone.fill", "video.fill", "book.fill", "lightbulb.fill", "heart.fill",
        "star.fill", "hammer.fill", "chart.bar.fill", "person.2.wave.2.fill", "brain.head.profile",
        "cart.fill", "stethoscope", "building.2.fill", "leaf.fill", "gamecontroller.fill",
    ]
    static let colorChoices = ["#4F7CFF", "#9B5CFF", "#16A34A", "#F59E0B", "#EF4444", "#EC4899", "#06B6D4", "#64748B"]
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
