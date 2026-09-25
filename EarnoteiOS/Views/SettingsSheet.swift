import EarnoteCore
import EarnoteML
import StoreKit
import SwiftUI

/// Einstellungen als Blatt: wo die Notiz entsteht, Aufnahme, Bereiche, Über.
struct SettingsSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.loadDemoLibrary) private var loadDemoLibrary
    @State private var tips: [Product] = []

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                NoteWayPicker()
                MacSection()
                Section {
                    Picker("Sprache der Aufnahme", selection: $library.settings.language) {
                        ForEach(Self.recordingLanguages(current: library.settings.language), id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Picker("Standardbereich", selection: $library.settings.defaultCategoryID) {
                        Text("Ohne Bereich").tag(UUID?.none)
                        ForEach(library.categories) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
                    }
                    Toggle("Audio nach der Notiz behalten", isOn: $library.settings.keepAudioFiles)
                    NavigationLink("Wörterbuch") { GlossaryView() }
                } header: {
                    Text("Aufnahme")
                } footer: {
                    Text("Für eine englische Vorlesung stellst du die Sprache vorher auf Englisch. Das gilt für alle neuen Aufnahmen.")
                }
                Section {
                    NavigationLink {
                        ExportSettingsView()
                    } label: {
                        LabeledContent("Export", value: exportSummary)
                    }
                } footer: {
                    Text("Fertige Notizen automatisch in Notion, Obsidian, einen Ordner, Todoist oder Erinnerungen legen.")
                }
                Section {
                    Toggle("Erst am Ladekabel verarbeiten", isOn: $library.settings.processOnlyOnPower)
                } header: {
                    Text("Akku")
                } footer: {
                    Text("Die Notiz entsteht dann, sobald das iPhone lädt, zum Beispiel nachts. Im Stromsparmodus wartet Earnote auch ohne diese Einstellung aufs Ladekabel.")
                }
                #if DEBUG
                if let loadDemoLibrary {
                    Section {
                        Button("Beispieldaten laden", systemImage: "sparkles.rectangle.stack") {
                            Task {
                                await loadDemoLibrary()
                                dismiss()
                            }
                        }
                    } header: {
                        Text(verbatim: "Test")
                    } footer: {
                        Text(verbatim: "Nur in Test-Fassungen und nur bei leerer Bibliothek: Bereiche, Notizen, Aufgaben und Karteikarten wie am Mac.")
                    }
                }
                #endif
                // Kein Spendenlink am iPhone: Apple lässt Trinkgeld nur als In-App-Kauf zu
                if !tips.isEmpty { TipSection(products: tips) }
                Section {
                    // Mundpropaganda ist der wichtigste Weg zu neuen Nutzern (docs/STRATEGIE.md) – sobald die App im
                    // App Store ist, hier den App-Store-Link statt der Website teilen
                    ShareLink(item: AppInfo.website,
                              message: Text("Kennst du Earnote? Die App nimmt Vorlesungen auf und schreibt die Mitschrift – mit Karteikarten und Lernzettel als PDF. Kostenlos und ohne Konto, für iPhone und Mac.")) {
                        Label("Earnote empfehlen", systemImage: "heart.text.square")
                    }
                    Link(destination: AppInfo.website) { Label("earnote.dev", systemImage: "safari") }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                } header: {
                    Text("Über")
                } footer: {
                    Text("Earnote ist kostenlos und quelloffen (MIT). Deine Aufnahmen bleiben auf deinem iPhone.")
                }
            }
            .task { tips = await TipJar.products() }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    /// Kurz, was eingeschaltet ist: „Notion, Obsidian“ oder „Aus“
    private var exportSummary: String {
        let names = PhoneDestinations().all.filter { library.settings.destinations.enabled.contains($0.id) }.map(\.name)
        return names.isEmpty ? String(localized: "Aus") : names.joined(separator: ", ")
    }

    /// Apples Spracherkennung kennt kein „Automatisch“: Sie braucht eine feste Sprache
    static func recordingLanguages(current: String) -> [(code: String, name: String)] {
        let list = AppSettings.languages.filter { $0.code != "auto" }
        if list.contains(where: { $0.code == current }) { return list }
        return list + [(code: current, name: Locale.current.localizedString(forLanguageCode: current)?.localizedCapitalized ?? current)]
    }
}

/// Weg B (docs/IPHONE.md, Abschnitt 6a): Abgleich mit dem Mac über iCloud, auf Wunsch schreibt der Mac die Notizen
struct MacSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HandoffSender.self) private var handoffs

    var body: some View {
        @Bindable var library = library
        Section {
            // Wer die Notiz schreibt, steht oben in „So entsteht die Notiz“ – hier nur der Abgleich selbst
            Toggle("Mit dem Mac abgleichen (iCloud)", isOn: $library.settings.syncWithCloud)
        } header: {
            Text("Mac")
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if !library.settings.syncWithCloud {
            Text("Mit Earnote auf deinem Mac und derselben iCloud hast du deine Notizen auf beiden Geräten. Gilt ab dem nächsten Start.")
        } else if handoffs.macs.isEmpty {
            Text("Noch kein Mac gefunden. Öffne Earnote auf deinem Mac und schalte dort in den Einstellungen den Abgleich über iCloud ein.")
        } else if library.settings.processOnMac {
            Text("\(handoffs.macs.map(\.name).joined(separator: ", ")) schreibt die Notiz. Das Audio geht dafür über deine iCloud zum Mac und wird danach aus iCloud gelöscht.")
        } else {
            Text("Dein Mac kann die Notizen schreiben – das schont den Akku und nutzt die KI auf dem Mac.")
        }
    }
}

/// Wörterbuch: richtige Schreibweisen von Namen und Fachbegriffen – Spracherkennung und KI bekommen sie mit
struct GlossaryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var term = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Neuer Begriff, z. B. Eigenwert", text: $term)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Hinzufügen", systemImage: "plus.circle.fill", action: add)
                        .labelStyle(.iconOnly)
                        .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Namen von Lehrenden, Fachbegriffe, Abkürzungen – Earnote schreibt sie dann richtig.")
            }
            if !library.glossary.isEmpty {
                Section {
                    ForEach(library.glossary) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.term)
                            if !entry.variants.isEmpty {
                                Text(entry.variants.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { library.deleteGlossaryTerm(library.glossary[index].id) }
                    }
                }
            }
        }
        .navigationTitle("Wörterbuch")
    }

    private func add() {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        library.addGlossaryTerm(GlossaryTerm(term: trimmed))
        term = ""
    }
}
