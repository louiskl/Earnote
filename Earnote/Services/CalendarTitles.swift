import EarnoteCore
import EventKit
import Foundation

/// Titel aus dem Kalender: Läuft gerade „Analysis II“, heißt die Aufnahme auch so –
/// statt „Uni – 21. Sep, 10:15“. Gelesen wird nur der Termin, der gerade läuft.
@MainActor
enum CalendarTitles {
    private static let store = EKEventStore()

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var isAuthorized: Bool { status == .fullAccess }

    /// Fragt einmalig nach Zugriff. Antwortet der Nutzer mit Nein, bleibt es dabei –
    /// der Schalter geht wieder aus und der Weg in die Systemeinstellungen steht daneben.
    static func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Termin, der gerade läuft (oder in zehn Minuten beginnt). Ganztägige Termine und
    /// Absagen zählen nicht; bei mehreren gewinnt der kürzeste – das ist meist der konkrete.
    static func currentTitle(now: Date = Date()) -> String? {
        guard isAuthorized else { return nil }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-4 * 3600),
                                                 end: now.addingTimeInterval(10 * 60), calendars: nil)
        return pick(from: store.events(matching: predicate), now: now)
    }

    /// Die Auswahl aus den gefundenen Terminen – getrennt, damit sie ohne Kalenderzugriff prüfbar ist.
    static func pick(from events: [EKEvent], now: Date) -> String? {
        let candidates = events.filter { event in
            guard !event.isAllDay, event.status != .canceled,
                  let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let start = event.startDate, start <= now.addingTimeInterval(10 * 60),
                  let end = event.endDate, end > now else { return false }
            // Abgesagte Teilnahme des Nutzers zählt nicht als „läuft gerade“
            return event.attendees?.first { $0.isCurrentUser }?.participantStatus != .declined
        }
        return candidates.min { $0.duration < $1.duration }?.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension EKEvent {
    var duration: TimeInterval {
        guard let start = startDate, let end = endDate else { return .greatestFiniteMagnitude }
        return end.timeIntervalSince(start)
    }
}
