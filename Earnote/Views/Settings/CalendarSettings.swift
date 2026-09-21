import EarnoteCore
import SwiftUI

/// Kalender-Abschnitt in den Aufnahme-Einstellungen: Schalter, Auswahl der Kalender
/// und was gerade laufen würde – damit man vorher sieht, wie die Aufnahme heißen wird.
struct CalendarSettings: View {
    @Environment(LibraryStore.self) private var library

    @State private var calendars: [CalendarChoice] = []
    @State private var current: CalendarEvent?
    @State private var denied = false

    var body: some View {
        @Bindable var library = library
        Section {
            Toggle("Titel aus dem Kalender übernehmen", isOn: $library.settings.calendarTitles)
                .onChange(of: library.settings.calendarTitles) { _, on in
                    guard on else { return }
                    Task {
                        // Ohne Zugriff bleibt der Schalter aus, statt still nichts zu tun
                        denied = await !CalendarTitles.requestAccess()
                        if denied { library.settings.calendarTitles = false } else { await refresh() }
                    }
                }
            // Auch wenn der Zugriff später in den Systemeinstellungen entzogen wurde
            if denied || (library.settings.calendarTitles && !CalendarTitles.isAuthorized) {
                LabeledContent("Kalender") {
                    Button("In den Systemeinstellungen erlauben …") { SystemSettingsLink.calendars() }
                }
            }
            if library.settings.calendarTitles, CalendarTitles.isAuthorized {
                LabeledContent("Gerade") {
                    if let current {
                        Text("\(current.title) · \(current.calendar)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Kein passender Termin")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text("Läuft während der Aufnahme ein Termin, heißt die Aufnahme wie er – sonst wie der Bereich "
                 + "mit Datum. Ganztägige Termine und lange Rahmen wie „Arbeit 9–17 Uhr“ zählen nicht.")
        }
        // Beim Öffnen der Einstellungen den Stand holen – der Termin ändert sich ja ständig
        .task { await refresh() }

        if library.settings.calendarTitles, CalendarTitles.isAuthorized {
            Section {
                ForEach(calendars) { calendar in
                    Toggle(isOn: binding(for: calendar)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(calendar.title)
                            if !calendar.source.isEmpty {
                                Text(calendar.source).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Diese Kalender zählen")
            } footer: {
                Text("Ohne Auswahl zählen alle. Schalte den Arbeitskalender ab, wenn „Arbeit“ nicht "
                     + "als Titel auftauchen soll.")
            }
        }
    }

    /// Leere Auswahl heißt „alle“. Wer den ersten Kalender abschaltet, legt damit die Auswahl fest.
    private func binding(for calendar: CalendarChoice) -> Binding<Bool> {
        Binding(get: { library.settings.calendarIDs.isEmpty || library.settings.calendarIDs.contains(calendar.id) },
                set: { on in
                    var ids = library.settings.calendarIDs.isEmpty
                        ? Set(calendars.map(\.id))
                        : library.settings.calendarIDs
                    if on { ids.insert(calendar.id) } else { ids.remove(calendar.id) }
                    // Alle wieder an = wieder „alle“, damit neue Kalender automatisch dazugehören
                    library.settings.calendarIDs = ids == Set(calendars.map(\.id)) ? [] : ids
                    Task { await refresh() }
                })
    }

    private func refresh() async {
        guard library.settings.calendarTitles, CalendarTitles.isAuthorized else {
            calendars = []
            current = nil
            return
        }
        calendars = CalendarTitles.availableCalendars()
        current = CalendarTitles.current(in: library.settings.calendarIDs)
    }
}

/// „Termin: Analysis II“ – steht im Fenster der Menüleiste über dem Aufnahmeknopf,
/// damit vor dem Start klar ist, wie die Aufnahme heißen wird.
struct CalendarEventLine: View {
    @Environment(LibraryStore.self) private var library
    @State private var current: CalendarEvent?

    var body: some View {
        Group {
            if let current {
                Label {
                    Text(current.title)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("Die Aufnahme bekommt diesen Titel (aus „\(current.calendar)“).")
            }
        }
        // Menüleisten-Fenster: bei jedem Öffnen frisch, danach minütlich
        .task(id: library.settings.calendarTitles) {
            while !Task.isCancelled {
                current = library.settings.calendarTitles ? CalendarTitles.current(in: library.settings.calendarIDs) : nil
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
