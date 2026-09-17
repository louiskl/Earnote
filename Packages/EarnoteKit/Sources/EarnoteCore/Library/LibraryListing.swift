import Foundation

/// Was eine Aufnahme für Seitenleiste und Liste mindestens liefern muss. So bleibt die Logik testbar,
/// ohne ein `@Model` anzulegen.
public protocol LibraryListable {
    var listID: UUID { get }
    var listStartedAt: Date { get }
    var listCategoryID: UUID? { get }
    var listStatus: RecordingStatus { get }
    var listOpenTasks: Int { get }
}

extension LibraryRecording: LibraryListable {
    public var listID: UUID { id }
    public var listStartedAt: Date { startedAt }
    public var listCategoryID: UUID? { category?.id }
    public var listStatus: RecordingStatus { status }
    public var listOpenTasks: Int { note?.taskCount ?? 0 }
}

extension Recording: LibraryListable {
    public var listID: UUID { id }
    public var listStartedAt: Date { startedAt }
    public var listCategoryID: UUID? { categoryID }
    public var listStatus: RecordingStatus { status }
    public var listOpenTasks: Int { taskCount }
}

/// Auswahl in der Seitenleiste
public enum LibraryFilter: Hashable, Sendable, RawRepresentable {
    case all, openTasks, uncategorized, problems
    case category(UUID)

    public init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "openTasks": self = .openTasks
        case "uncategorized": self = .uncategorized
        case "problems": self = .problems
        default:
            guard rawValue.hasPrefix("category:"), let id = UUID(uuidString: String(rawValue.dropFirst(9))) else { return nil }
            self = .category(id)
        }
    }

    public var rawValue: String {
        switch self {
        case .all: return "all"
        case .openTasks: return "openTasks"
        case .uncategorized: return "uncategorized"
        case .problems: return "problems"
        case .category(let id): return "category:\(id.uuidString)"
        }
    }

    public func matches(_ item: some LibraryListable) -> Bool {
        switch self {
        case .all: return true
        case .openTasks: return item.listOpenTasks > 0
        case .uncategorized: return item.listCategoryID == nil
        case .problems: return item.listStatus == .failed
        case .category(let id): return item.listCategoryID == id
        }
    }
}

/// Anzahlen für die Seitenleiste
public struct LibraryCounts: Equatable, Sendable {
    public var all = 0
    public var openTasks = 0
    public var uncategorized = 0
    public var problems = 0
    public var perCategory: [UUID: Int] = [:]

    public init() {}

    public func count(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all: return all
        case .openTasks: return openTasks
        case .uncategorized: return uncategorized
        case .problems: return problems
        case .category(let id): return perCategory[id] ?? 0
        }
    }
}

/// Eine Tagesgruppe der Aufnahmeliste
public struct LibraryDaySection<Item>: Identifiable {
    public let id: Date
    public let title: String
    public let items: [Item]
}

public enum LibraryListing {
    public static func counts(_ items: [some LibraryListable]) -> LibraryCounts {
        var counts = LibraryCounts()
        for item in items {
            counts.all += 1
            if item.listOpenTasks > 0 { counts.openTasks += 1 }
            if item.listStatus == .failed { counts.problems += 1 }
            if let id = item.listCategoryID { counts.perCategory[id, default: 0] += 1 } else { counts.uncategorized += 1 }
        }
        return counts
    }

    /// Nach Tag gruppiert, neueste zuerst. Titel: „Heute“, „Gestern“, sonst Wochentag und Datum (mit Jahr, wenn nicht aktuell).
    public static func groupedByDay<Item: LibraryListable>(_ items: [Item], now: Date = Date(),
                                                           calendar: Calendar = .current,
                                                           locale: Locale = Locale(identifier: "de_DE")) -> [LibraryDaySection<Item>] {
        let sorted = items.sorted { $0.listStartedAt > $1.listStartedAt }
        var sections: [LibraryDaySection<Item>] = []
        var currentDay: Date?
        var bucket: [Item] = []
        func flush() {
            guard let day = currentDay, !bucket.isEmpty else { return }
            sections.append(LibraryDaySection(id: day, title: dayTitle(day, now: now, calendar: calendar, locale: locale), items: bucket))
            bucket = []
        }
        for item in sorted {
            let day = calendar.startOfDay(for: item.listStartedAt)
            if day != currentDay { flush(); currentDay = day }
            bucket.append(item)
        }
        flush()
        return sections
    }

    public static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .current,
                                locale: Locale = Locale(identifier: "de_DE")) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Heute" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Gestern"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "EEEEdMMMMyyyy")
        return formatter.string(from: day)
    }
}

/// Suchbegriffe tolerant machen: Groß-/Kleinschreibung und Akzente übernimmt die Datenbanksuche
/// (`localizedStandardContains`); hier kommen Schreibweisen ohne Umlaute dazu („Mueller“ findet „Müller“).
public enum SearchText {
    /// Bereinigter Suchbegriff (leer = keine Suche)
    public static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Varianten des Suchbegriffs, von denen eine passen muss
    public static func variants(_ query: String) -> [String] {
        let base = normalized(query)
        guard !base.isEmpty else { return [] }
        var result = [base]
        let replacements: [(String, String)] = [("ae", "ä"), ("oe", "ö"), ("ue", "ü"), ("Ae", "Ä"), ("Oe", "Ö"), ("Ue", "Ü")]
        var umlauts = base
        for (plain, umlaut) in replacements { umlauts = umlauts.replacingOccurrences(of: plain, with: umlaut) }
        if umlauts != base { result.append(umlauts) }
        if base.contains("ss") { result.append(base.replacingOccurrences(of: "ss", with: "ß")) }
        if base.contains("ß") { result.append(base.replacingOccurrences(of: "ß", with: "ss")) }
        return result
    }

    /// Dieselbe Regel für Text im Speicher (z. B. zum Hervorheben oder in Tests)
    public static func matches(_ text: String, query: String) -> Bool {
        let variants = variants(query)
        return variants.isEmpty || variants.contains { text.localizedStandardContains($0) }
    }
}
