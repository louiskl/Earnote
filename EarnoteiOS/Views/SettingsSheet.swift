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
                NoteWaySection()
                MacSection()
                Section("Aufnahme") {
                    Picker("Standardbereich", selection: $library.settings.defaultCategoryID) {
                        Text("Ohne Bereich").tag(UUID?.none)
                        ForEach(library.categories) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
                    }
                    Toggle("Audio nach der Notiz behalten", isOn: $library.settings.keepAudioFiles)
                    NavigationLink("Wörterbuch") { GlossaryView() }
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
}

/// Weg B (docs/IPHONE.md, Abschnitt 6a): Abgleich mit dem Mac über iCloud, auf Wunsch schreibt der Mac die Notizen
struct MacSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HandoffSender.self) private var handoffs

    var body: some View {
        @Bindable var library = library
        Section {
            Toggle("Mit dem Mac abgleichen (iCloud)", isOn: $library.settings.syncWithCloud)
            if library.settings.syncWithCloud && !handoffs.macs.isEmpty {
                Toggle("Notizen schreibt mein Mac", isOn: $library.settings.processOnMac)
            }
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

/// Wo die Notiz entsteht (docs/IPHONE.md, Abschnitt 2): auf dem iPhone, mit Cloud-KI und eigenem Schlüssel, oder gar nicht.
/// Weg B (der Mac verarbeitet) steht in `MacSection`.
struct NoteWaySection: View {
    @Environment(LibraryStore.self) private var library
    @State private var apiKey = ""

    static var providers: [AIProviderKind] {
        (DeviceCapabilities.supportsLocalModel ? [.localModel] : []) + [.gemini, .anthropic, .openAI, .mistral, .none]
    }
    static let languages = ["Deutsch", "Englisch", "Französisch", "Spanisch", "Italienisch", "Sprache der Aufnahme"]

    var body: some View {
        @Bindable var library = library
        let provider = library.settings.ai.provider
        Section {
            Picker("KI für die Notiz", selection: $library.settings.ai.provider) {
                ForEach(Self.providers, id: \.self) { Text($0.label).tag($0) }
            }
            if provider.needsAPIKey {
                SecureField("API-Schlüssel", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Keychain.setAPIKey(apiKey, for: provider) }
                    .onChange(of: apiKey) { Keychain.setAPIKey(apiKey, for: provider) }
            }
            if provider == .localModel {
                LocalModelRow()
            }
            Picker("Sprache der Notiz", selection: $library.settings.ai.summaryLanguage) {
                ForEach(Self.languages, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
            }
        } header: {
            Text("Notiz")
        } footer: {
            Text(footer(provider))
        }
        .task(id: provider) { apiKey = Keychain.apiKey(for: provider) ?? "" }
    }

    private func footer(_ provider: AIProviderKind) -> String {
        switch provider {
        case .localModel:
            String(localized: "Alles bleibt auf deinem iPhone. Das Modell (~2,5 GB) wird einmal geladen – am besten im WLAN.")
        case .gemini:
            String(localized: "Nur der Text geht an Google, nie das Audio. Einen kostenlosen Schlüssel gibt es auf aistudio.google.com.")
        case .none:
            String(localized: "Earnote schreibt nur das Transkript.")
        default:
            String(localized: "Nur der Text geht an \(provider.label), nie das Audio. Abgerechnet wird nach Nutzung über deinen Schlüssel.")
        }
    }
}

/// Stand des lokalen Modells: geladen, lädt gerade, oder Knopf zum Laden
private struct LocalModelRow: View {
    @ObservedObject private var manager = LocalModelManager.shared

    var body: some View {
        if LocalModelManager.isInstalled(manager.selected) {
            LabeledContent(manager.selected.name) { Label("Geladen", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        } else if manager.isDownloading {
            ProgressView(value: manager.progress) { Text("Modell wird geladen …") }
        } else {
            Button("Modell jetzt laden (~2,5 GB)", systemImage: "arrow.down.circle") { manager.download() }
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
