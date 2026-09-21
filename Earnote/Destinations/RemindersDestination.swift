import EarnoteCore
import EventKit
import Foundation

/// Offene Aufgaben aus der Notiz landen in Apple Erinnerungen – je Bereich eine eigene Liste,
/// damit „Lineare Algebra“ und „Kundentermin“ nicht im selben Haufen liegen.
struct RemindersDestination: Destination {
    static let id = "reminders"

    func export(_ p: ExportPayload) async throws -> String? {
        let tasks = NoteMarkdown.openTasks(p.summary?.markdown ?? "")
        guard !tasks.isEmpty else { return nil }   // Nichts abzuhaken ist kein Fehler

        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else {
            throw DestinationNotConfigured(hint: String(localized: "Zugriff auf Erinnerungen nicht erlaubt"))
        }
        let list = try list(named: listName(for: p), in: store)
        let note = String(localized: "Aus „\(p.title)“ · \(MarkdownDocument.metaLine(p))")
        for task in tasks {
            let reminder = EKReminder(eventStore: store)
            reminder.title = task
            reminder.notes = note
            reminder.calendar = list
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return nil
    }

    /// Feste Liste aus den Einstellungen – sonst eine Liste je Bereich, sonst „Earnote“
    private func listName(for p: ExportPayload) -> String {
        let fixed = p.settings.remindersList.trimmingCharacters(in: .whitespaces)
        if !fixed.isEmpty { return fixed }
        return p.category?.name ?? AppInfo.name
    }

    /// Vorhandene Liste nehmen, sonst eine anlegen
    private func list(named name: String, in store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) { return existing }
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            throw DestinationNotConfigured(hint: String(localized: "Keine Liste für Erinnerungen gefunden"))
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }
}
