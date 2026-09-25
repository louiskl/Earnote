import EarnoteCore
import EarnoteML
import SwiftUI

/// Einstellungen als Blatt: wo die Notiz entsteht, Aufnahme, Bereiche, Über.
struct SettingsSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.loadDemoLibrary) private var loadDemoLibrary
    @AppStorage(AppSkin.key) private var skin: AppSkin = .standard
    @AppStorage(TipJar.supporterKey) private var isSupporter = false
    @AppStorage(Pro.key) private var isPro = false
    @State private var showsPro = false

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                NoteWayPicker()
                Section {
                    Picker("Sprache der Aufnahme", selection: $library.settings.language) {
                        ForEach(Self.recordingLanguages(current: library.settings.language), id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Picker("Standardbereich", selection: $library.settings.defaultCategoryID) {
                        Text("Ohne Bereich").tag(UUID?.none)
                        ForEach(library.categories) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
                    }
                    Toggle(isOn: Binding(get: { library.settings.detectSpeakers }, set: { on in
                        // Einschalten ohne Pro geht, solange Probeversuche übrig sind (je Aufnahme einer)
                        if on && !Pro.isUnlocked && Pro.triesLeft(.speakers) == 0 { showsPro = true } else { library.settings.detectSpeakers = on }
                    })) {
                        Text("Sprecher erkennen")
                        Text(isPro ? "Wer hat was gesagt – im Transkript und in der Notiz." : "Pro · noch \(Pro.triesLeft(.speakers)) Aufnahmen kostenlos")
                    }
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
                    NavigationLink("Weitere Optionen") { MoreOptionsView() }
                } footer: {
                    Text("Fertige Notizen automatisch in Notion, Obsidian, einen Ordner, Todoist oder Erinnerungen legen.")
                }
                // Alles rund um Earnote selbst in einer Gruppe, statt über die ganze Seite verteilt (ROADMAP Phase 7)
                // Kein Spendenlink am iPhone: Apple lässt Trinkgeld nur als In-App-Kauf zu (Dankeschön-Paket)
                Section("Earnote") {
                    NavigationLink {
                        ProView()
                    } label: {
                        LabeledContent {
                            if isPro { Text("Freigeschaltet") }
                        } label: {
                            Label("Earnote Pro", systemImage: "star.circle")
                        }
                    }
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        LabeledContent {
                            Text(isSupporter || skin.isFree ? skin.name : AppSkin.standard.name)
                        } label: {
                            Label("Aussehen", systemImage: "paintpalette")
                        }
                    }
                    NavigationLink {
                        SupporterView()
                    } label: {
                        Label("Earnote unterstützen", systemImage: "gift")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("Über Earnote", systemImage: "info.circle")
                    }
                }
                #if DEBUG
                Section {
                    Toggle(isOn: $isPro) { Text(verbatim: "Pro freischalten") }
                } header: {
                    Text(verbatim: "Test: Pro")
                } footer: {
                    Text(verbatim: "Nur in Test-Fassungen – zum Ausprobieren ohne Kauf.")
                }
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
            }
            .sheet(isPresented: $showsPro) { ProSheet(highlight: .speakers) }
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

/// Seltenes, das die meisten nie ändern: Mac-Abgleich, Audio behalten, Akku, Einstiegsfrage
private struct MoreOptionsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            MacSection()
            Section {
                Toggle("Audio nach der Notiz behalten", isOn: $library.settings.keepAudioFiles)
            } footer: {
                Text("Aus: Nach der fertigen Notiz wird die Tonaufnahme gelöscht. Transkript und Notiz bleiben, nur Anhören geht dann nicht mehr.")
            }
            Section {
                Toggle("Erst am Ladekabel verarbeiten", isOn: $library.settings.processOnlyOnPower)
            } header: {
                Text("Akku")
            } footer: {
                Text("Die Notiz entsteht dann, sobald das iPhone lädt, zum Beispiel nachts. Im Stromsparmodus wartet Earnote auch ohne diese Einstellung aufs Ladekabel.")
            }
            Section {
                Picker("Earnote nutzen für", selection: $library.settings.usage) {
                    Text("Nicht festgelegt").tag(Usage?.none)
                    ForEach(Usage.allCases) { Text($0.label).tag(Optional($0)) }
                }
            } footer: {
                Text("Bei „Arbeit“ blendet Earnote Klausur-Radar und Prüfungshinweise aus.")
            }
        }
        .navigationTitle("Weitere Optionen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Über Earnote: weiterempfehlen, Website, Version
private struct AboutView: View {
    var body: some View {
        Form {
            Section {
                // Mundpropaganda ist der wichtigste Weg zu neuen Nutzern (docs/STRATEGIE.md) – sobald die App im
                // App Store ist, hier den App-Store-Link statt der Website teilen
                ShareLink(item: AppInfo.website,
                          message: Text("Kennst du Earnote? Die App nimmt Vorlesungen auf und schreibt die Mitschrift – mit Karteikarten und Lernzettel als PDF. Kostenlos und ohne Konto, für iPhone und Mac.")) {
                    Label("Earnote empfehlen", systemImage: "heart.text.square")
                }
                Link(destination: AppInfo.website) { Label("earnote.dev", systemImage: "safari") }
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            } footer: {
                Text("Earnote ist kostenlos und quelloffen (MIT). Deine Aufnahmen bleiben auf deinem iPhone.")
            }
        }
        .navigationTitle("Über Earnote")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Usage {
    var label: LocalizedStringKey {
        switch self {
        case .university: "Uni"
        case .school: "Schule"
        case .work: "Arbeit"
        }
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
