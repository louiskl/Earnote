import EarnoteCore
import EventKit
import Foundation

/// Ein Termin, so weit ihn Earnote braucht
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    /// Name des Kalenders, aus dem er kommt („Uni“, „Outlook“)
    let calendar: String
    let start: Date
    let end: Date
}

/// Ein Kalender zur Auswahl in den Einstellungen
struct CalendarChoice: Identifiable, Hashable {
    let id: String
    let title: String
    /// Konto, zu dem der Kalender gehört („iCloud“, „Exchange“)
    let source: String
}

/// Titel aus dem Kalender: Läuft gerade „Analysis II“, heißt die Aufnahme auch so –
/// statt „Uni – 21. Sep, 10:15“. Welche Kalender zählen, entscheidet der Nutzer.
@MainActor
enum CalendarTitles {
    private static let store = EKEventStore()

    /// Termine, die länger dauern, sind Rahmen wie „Arbeit 9–17 Uhr“ und keine Vorlesung.
    static let longestEvent: TimeInterval = 4 * 3600

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var isAuthorized: Bool { status == .fullAccess }

    /// Fragt einmalig nach Zugriff. Antwortet der Nutzer mit Nein, bleibt es dabei –
    /// der Schalter geht wieder aus und der Weg in die Systemeinstellungen steht daneben.
    static func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Alle Kalender, aus denen gelesen werden könnte – für die Auswahl in den Einstellungen
    static func availableCalendars() -> [CalendarChoice] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "") }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Termin, der gerade läuft (oder in zehn Minuten beginnt), aus den gewählten Kalendern.
    /// Leere Auswahl heißt: alle Kalender.
    static func current(in selected: Set<String> = [], now: Date = Date()) -> CalendarEvent? {
        guard isAuthorized else { return nil }
        let calendars = store.calendars(for: .event).filter { selected.isEmpty || selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return nil }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-longestEvent),
                                                 end: now.addingTimeInterval(10 * 60), calendars: calendars)
        return pick(from: store.events(matching: predicate), now: now)
    }

    /// Die Auswahl aus den gefundenen Terminen – getrennt, damit sie ohne Kalenderzugriff prüfbar ist.
    /// Ganztägige, abgesagte, beendete, abgelehnte und sehr lange Termine zählen nicht;
    /// bei mehreren gewinnt der kürzeste, denn das ist der konkrete.
    static func pick(from events: [EKEvent], now: Date) -> CalendarEvent? {
        let candidates = events.compactMap { event -> CalendarEvent? in
            guard !event.isAllDay, event.status != .canceled,
                  let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let start = event.startDate, start <= now.addingTimeInterval(10 * 60),
                  let end = event.endDate, end > now,
                  end.timeIntervalSince(start) <= longestEvent,
                  // Abgesagte Teilnahme des Nutzers zählt nicht als „läuft gerade“
                  event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus != .declined
            else { return nil }
            return CalendarEvent(id: event.eventIdentifier ?? title, title: title,
                                 calendar: event.calendar?.title ?? "", start: start, end: end)
        }
        return candidates.min { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
    }
}
