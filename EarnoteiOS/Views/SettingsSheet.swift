import EarnoteCore
import EarnoteML
import SwiftUI

/// Einstellungen als Blatt: wo die Notiz entsteht, Aufnahme, Bereiche, Über.
struct SettingsSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.loadDemoLibrary) private var loadDemoLibrary

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                NoteWaySection()
                Section("Aufnahme") {
                    Picker("Standardbereich", selection: $library.settings.defaultCategoryID) {
                        Text("Ohne Bereich").tag(UUID?.none)
                        ForEach(library.categories) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
                    }
                    Toggle("Audio nach der Notiz behalten", isOn: $library.settings.keepAudioFiles)
                    NavigationLink("Bereiche") { CategoriesView() }
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
                Section {
                    Link(destination: AppInfo.sponsor) { Label("Earnote unterstützen", systemImage: "heart") }
                    Link(destination: AppInfo.website) { Label("earnote.dev", systemImage: "safari") }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                } header: {
                    Text("Über")
                } footer: {
                    Text("Earnote ist kostenlos und quelloffen (MIT). Deine Aufnahmen bleiben auf deinem iPhone.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}

/// Wo die Notiz entsteht (docs/IPHONE.md, Abschnitt 2): auf dem iPhone, mit Cloud-KI und eigenem Schlüssel, oder gar nicht.
/// Weg B (der Mac verarbeitet) folgt mit dem iCloud-Abgleich.
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

/// Bereiche anlegen, umbenennen, sortieren und löschen
struct CategoriesView: View {
    @Environment(LibraryStore.self) private var library
    @State private var renaming: RecordingCategory?
    @State private var name = ""

    var body: some View {
        List {
            ForEach(library.categories) { category in
                Button { rename(category) } label: {
                    Label { Text(category.name).foregroundStyle(.primary) } icon: { CategoryBadge(category: category) }
                }
            }
            .onMove { from, to in
                var ids = library.categories.map(\.id)
                ids.move(fromOffsets: from, toOffset: to)
                library.setCategoryOrder(ids)
            }
            .onDelete { offsets in
                for index in offsets { library.deleteCategory(library.categories[index].id) }
            }
        }
        .navigationTitle("Bereiche")
        .toolbar {
            EditButton()
            Button("Neuer Bereich", systemImage: "plus") { rename(library.addCategory()) }
        }
        .alert("Bereich umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Sichern") { if let renaming { library.renameCategory(renaming.id, to: name) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func rename(_ category: RecordingCategory) {
        name = category.name
        renaming = category
    }
}
