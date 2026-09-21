import EarnoteCore
import SwiftUI

/// Kalender-Abschnitt in den Aufnahme-Einstellungen: Schalter, Auswahl der Kalender
/// und was gerade laufen würde – damit man vorher sieht, wie die Aufnahme heißen wird.
struct CalendarSettings: View {
    @Environment(LibraryStore.self) private var library

    /// Maßgeblich ist, was wir tatsächlich lesen können: `authorizationStatus` meldet einen frisch
    /// erteilten Zugriff erst verzögert, gefundene Kalender sind der ehrlichere Beweis.
    @State private var calendars: [CalendarChoice] = []
    @State private var current: CalendarEvent?
    @State private var askedAndDenied = false

    private var hasAccess: Bool { !calendars.isEmpty }

    var body: some View {
        @Bindable var library = library
        Section {
            Toggle("Titel aus dem Kalender übernehmen", isOn: $library.settings.calendarTitles)
                .onChange(of: library.settings.calendarTitles) { _, on in
                    guard on else { return }
                    Task {
                        // Beim Einschalten gleich fragen; klappt es nicht, steht der Knopf darunter
                        let granted = await CalendarTitles.requestAccess()
                        await refresh()
                        askedAndDenied = !granted && !hasAccess
                    }
                }
            if library.settings.calendarTitles, hasAccess {
                LabeledContent("Gerade") {
                    Group {
                        if let current {
                            Text("\(current.title) · \(current.calendar)")
                        } else {
                            Text("Kein passender Termin")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            // Kein Zugriff (nie erteilt oder später entzogen): erst noch einmal fragen,
            // und erst wenn das nichts bringt, in die Systemeinstellungen führen.
            if library.settings.calendarTitles, !hasAccess {
                LabeledContent("Kalender") {
                    Button(askedAndDenied ? "In den Systemeinstellungen erlauben …" : "Zugriff erlauben …") {
                        if askedAndDenied {
                            SystemSettingsLink.calendars()
                        } else {
                            Task {
                                let granted = await CalendarTitles.requestAccess()
                                await refresh()
                                askedAndDenied = !granted && !hasAccess
                            }
                        }
                    }
                }
            }
        }
        // Beim Öffnen der Einstellungen den Stand holen – der Termin ändert sich ja ständig
        .task { await refresh() }

        if library.settings.calendarTitles, hasAccess {
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
        guard library.settings.calendarTitles else {
            calendars = []
            current = nil
            return
        }
        calendars = CalendarTitles.availableCalendars()
        current = CalendarTitles.current(in: library.settings.calendarIDs)
        Log.info("Kalender: \(calendars.count) gefunden, Termin gerade: \(current != nil ? "ja" : "nein")")
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
