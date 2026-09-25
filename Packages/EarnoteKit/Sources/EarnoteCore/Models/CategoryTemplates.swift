import Foundation

/// Vorlagen, aus denen man sich beim Einrichten seine Bereiche zusammenklickt.
/// Jede bringt passende Hinweise für die KI mit – man muss nichts selbst formulieren.
public struct CategoryTemplate: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        /// Übersetzter Name der Gruppe (der Rohwert bleibt Deutsch, weil er gespeichert wird)
        public var label: String { t(String.LocalizationValue(rawValue)) }

        // Reihenfolge ist die Reihenfolge im Einrichtungsassistenten: Studierende sind die Zielgruppe,
        // also steht ihr Fall oben – sonst scrollen sie an sechs Arbeitsvorlagen vorbei.
        case study = "Studium & Schule"
        case work = "Arbeit"
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
        CategoryTemplate(id: "meeting", group: .work, emoji: "💼", name: t("Meeting"),
                         detail: t("Teammeetings, Jour fixe, Abstimmungen"), colorHex: "#4F7CFF",
                         instructions: RecordingCategory.defaults[0].instructions),
        CategoryTemplate(id: "oneonone", group: .work, emoji: "👥", name: t("1:1-Gespräch"),
                         detail: t("Mitarbeitergespräche, Feedback, Coaching"), colorHex: "#06B6D4",
                         instructions: t("Halte vertraulich und sachlich fest, welche Themen, Anliegen und Vereinbarungen besprochen wurden. Achte auf Entwicklungsziele und Feedback.")),
        CategoryTemplate(id: "client", group: .work, emoji: "🤝", name: t("Kundengespräch"),
                         detail: t("Sales, Beratung, Anforderungen"), colorHex: "#10B981",
                         instructions: RecordingCategory.defaults[2].instructions),
        CategoryTemplate(id: "interview", group: .work, emoji: "🎙️", name: t("Interview"),
                         detail: t("Bewerbungsgespräche, Nutzer-Interviews, Recherche"), colorHex: "#F59E0B",
                         instructions: RecordingCategory.defaults[3].instructions),
        CategoryTemplate(id: "brainstorm", group: .work, emoji: "💡", name: t("Brainstorming"),
                         detail: t("Ideen, Workshops, Konzepte"), colorHex: "#EC4899",
                         instructions: t("Sammle alle Ideen und Vorschläge mit ihren Argumenten. Gruppiere ähnliche Ideen und halte fest, welche weiterverfolgt werden sollen.")),
        CategoryTemplate(id: "call", group: .work, emoji: "📞", name: t("Telefonat"),
                         detail: t("Kurze Calls und Rückrufe"), colorHex: "#64748B",
                         instructions: t("Meist kurz: Halte fest, mit wem worüber gesprochen wurde, was vereinbart ist und was als Nächstes zu tun ist.")),

        CategoryTemplate(id: "lecture", group: .study, emoji: "🎓", name: t("Vorlesung"),
                         detail: t("Pro Fach oder Modul ein eigener Bereich"), colorHex: "#8B5CF6",
                         instructions: RecordingCategory.defaults[1].instructions),
        CategoryTemplate(id: "seminar", group: .study, emoji: "🧪", name: t("Seminar & Übung"),
                         detail: t("Diskussionen, Übungsaufgaben, Referate"), colorHex: "#06B6D4",
                         instructions: t("Halte die besprochenen Aufgaben, Lösungswege und Diskussionsbeiträge verständlich fest. Markiere Abgaben und Termine.")),
        CategoryTemplate(id: "lesson", group: .study, emoji: "🏫", name: t("Unterricht"),
                         detail: t("Schulstunden, Kurse, Berufsschule"), colorHex: "#F59E0B",
                         instructions: t("Fasse den Unterricht so zusammen, dass man damit für die nächste Arbeit lernen kann: wichtige Begriffe mit kurzer Erklärung, Beispiele, Hausaufgaben und angekündigte Tests.")),
        CategoryTemplate(id: "studygroup", group: .study, emoji: "📚", name: t("Lerngruppe"),
                         detail: t("Gemeinsam lernen und wiederholen"), colorHex: "#10B981",
                         instructions: t("Fasse die erklärten Inhalte so zusammen, dass man damit lernen kann. Halte offene Fragen und Aufgabenverteilungen fest.")),

        CategoryTemplate(id: "memo", group: .personal, emoji: "💭", name: t("Sprachnotiz"),
                         detail: t("Gedanken, To-dos, Ideen unterwegs"), colorHex: "#64748B",
                         instructions: RecordingCategory.defaults[4].instructions),
        CategoryTemplate(id: "doctor", group: .personal, emoji: "🩺", name: t("Arzttermin"),
                         detail: t("Befunde, Empfehlungen, Medikamente"), colorHex: "#FF5A4E",
                         instructions: t("Halte Befunde, Empfehlungen, Medikamente mit Dosierung und nächste Termine genau fest. Nichts interpretieren oder ergänzen.")),
        CategoryTemplate(id: "media", group: .personal, emoji: "🎧", name: t("Podcast & Video"),
                         detail: t("Wissen aus Videos und Podcasts festhalten"), colorHex: "#EC4899",
                         instructions: t("Gib die wichtigsten Aussagen, Tipps und Beispiele wieder. Es gibt hier in der Regel keine Aufgaben oder Entscheidungen.")),
    ]

    /// Vorausgewählt für Neue: deckt die häufigsten Fälle ab, ohne zu überladen.
    public static let suggested: Set<String> = ["lecture", "memo"]

    /// Bereiche nach der Einstiegsfrage „Wofür nutzt du Earnote?“ – der erste ist der Standardbereich
    public static func suggested(for usage: Usage) -> [String] {
        switch usage {
        case .university: ["lecture", "seminar", "studygroup", "memo"]
        case .school: ["lesson", "studygroup", "memo"]
        case .work: ["meeting", "oneonone", "client", "call"]
        }
    }

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
