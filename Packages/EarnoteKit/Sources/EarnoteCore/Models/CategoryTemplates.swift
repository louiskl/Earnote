import Foundation

/// Vorlagen, aus denen man sich beim Einrichten seine Bereiche zusammenklickt.
/// Jede bringt passende Hinweise für die KI mit – man muss nichts selbst formulieren.
public struct CategoryTemplate: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case work = "Arbeit"
        case study = "Studium & Schule"
        case personal = "Privat"
        public var id: String { rawValue }
    }

    public let id: String
    public let group: Group
    public let emoji: String
    public let name: String
    public let detail: String
    public let colorHex: String
    public let instructions: String

    public func makeCategory() -> RecordingCategory {
        RecordingCategory(name: name, emoji: emoji, symbol: "star.fill", colorHex: colorHex, instructions: instructions)
    }

    /// Die Vorlage „Vorlesung“ bietet an, direkt Fächer bzw. Module anzulegen.
    public var supportsSubjects: Bool { id == "lecture" }

    public static let all: [CategoryTemplate] = [
        CategoryTemplate(id: "meeting", group: .work, emoji: "💼", name: "Meeting",
                         detail: "Teammeetings, Jour fixe, Abstimmungen", colorHex: "#4F7CFF",
                         instructions: RecordingCategory.defaults[0].instructions),
        CategoryTemplate(id: "oneonone", group: .work, emoji: "👥", name: "1:1-Gespräch",
                         detail: "Mitarbeitergespräche, Feedback, Coaching", colorHex: "#06B6D4",
                         instructions: "Halte vertraulich und sachlich fest, welche Themen, Anliegen und Vereinbarungen besprochen wurden. Achte auf Entwicklungsziele und Feedback."),
        CategoryTemplate(id: "client", group: .work, emoji: "🤝", name: "Kundengespräch",
                         detail: "Sales, Beratung, Anforderungen", colorHex: "#10B981",
                         instructions: RecordingCategory.defaults[2].instructions),
        CategoryTemplate(id: "interview", group: .work, emoji: "🎙️", name: "Interview",
                         detail: "Bewerbungsgespräche, Nutzer-Interviews, Recherche", colorHex: "#F59E0B",
                         instructions: RecordingCategory.defaults[3].instructions),
        CategoryTemplate(id: "brainstorm", group: .work, emoji: "💡", name: "Brainstorming",
                         detail: "Ideen, Workshops, Konzepte", colorHex: "#EC4899",
                         instructions: "Sammle alle Ideen und Vorschläge mit ihren Argumenten. Gruppiere ähnliche Ideen und halte fest, welche weiterverfolgt werden sollen."),
        CategoryTemplate(id: "call", group: .work, emoji: "📞", name: "Telefonat",
                         detail: "Kurze Calls und Rückrufe", colorHex: "#64748B",
                         instructions: "Meist kurz: Halte fest, mit wem worüber gesprochen wurde, was vereinbart ist und was als Nächstes zu tun ist."),

        CategoryTemplate(id: "lecture", group: .study, emoji: "🎓", name: "Vorlesung",
                         detail: "Pro Fach oder Modul ein eigener Bereich", colorHex: "#8B5CF6",
                         instructions: RecordingCategory.defaults[1].instructions),
        CategoryTemplate(id: "seminar", group: .study, emoji: "🧪", name: "Seminar & Übung",
                         detail: "Diskussionen, Übungsaufgaben, Referate", colorHex: "#06B6D4",
                         instructions: "Halte die besprochenen Aufgaben, Lösungswege und Diskussionsbeiträge verständlich fest. Markiere Abgaben und Termine."),
        CategoryTemplate(id: "studygroup", group: .study, emoji: "📚", name: "Lerngruppe",
                         detail: "Gemeinsam lernen und wiederholen", colorHex: "#10B981",
                         instructions: "Fasse die erklärten Inhalte so zusammen, dass man damit lernen kann. Halte offene Fragen und Aufgabenverteilungen fest."),

        CategoryTemplate(id: "memo", group: .personal, emoji: "💭", name: "Sprachnotiz",
                         detail: "Gedanken, To-dos, Ideen unterwegs", colorHex: "#64748B",
                         instructions: RecordingCategory.defaults[4].instructions),
        CategoryTemplate(id: "doctor", group: .personal, emoji: "🩺", name: "Arzttermin",
                         detail: "Befunde, Empfehlungen, Medikamente", colorHex: "#FF5A4E",
                         instructions: "Halte Befunde, Empfehlungen, Medikamente mit Dosierung und nächste Termine genau fest. Nichts interpretieren oder ergänzen."),
        CategoryTemplate(id: "media", group: .personal, emoji: "🎧", name: "Podcast & Video",
                         detail: "Wissen aus Videos und Podcasts festhalten", colorHex: "#EC4899",
                         instructions: "Gib die wichtigsten Aussagen, Tipps und Beispiele wieder. Es gibt hier in der Regel keine Aufgaben oder Entscheidungen."),
    ]

    /// Vorausgewählt für Neue: deckt die häufigsten Fälle ab, ohne zu überladen.
    public static let suggested: Set<String> = ["meeting", "memo"]

    /// Emojis und Farben, die Fächer nacheinander bekommen – so sind sie in der Seitenleiste sofort unterscheidbar.
    public static let subjectEmojis = ["📐", "📊", "🧬", "⚖️", "💻", "🌍", "📖", "🧮", "🧪", "🎨", "🏛️", "🔬"]
    public static let subjectColors = ["#8B5CF6", "#4F7CFF", "#10B981", "#F59E0B", "#EC4899", "#06B6D4", "#FF5A4E", "#64748B"]

    /// Legt für jedes Fach einen eigenen Bereich mit den Hinweisen der Vorlesungs-Vorlage an.
    public static func subjectCategories(_ names: [String]) -> [RecordingCategory] {
        let lecture = all.first { $0.id == "lecture" }!
        return names.enumerated().map { i, name in
            RecordingCategory(name: name, emoji: subjectEmojis[i % subjectEmojis.count], symbol: "graduationcap.fill",
                              colorHex: subjectColors[i % subjectColors.count], instructions: lecture.instructions)
        }
    }
}
