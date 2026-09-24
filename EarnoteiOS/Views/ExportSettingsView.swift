import EarnoteCore
import EventKit
import SwiftUI

/// Wohin fertige Notizen automatisch gehen – wie am Mac: oben an- und abschalten, darunter die Einrichtung.
struct ExportSettingsView: View {
    @Environment(LibraryStore.self) private var library
    private let destinations = PhoneDestinations()

    private var enabled: [DestinationInfo] {
        destinations.all.filter { library.settings.destinations.enabled.contains($0.id) }
    }

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                ForEach(destinations.all) { destination in
                    Toggle(isOn: isEnabled(destination.id)) {
                        Label {
                            Text(destination.name)
                            Text(destination.detail)
                        } icon: {
                            Image(systemName: destination.symbol)
                        }
                    }
                }
            } header: {
                Text("Wohin fertige Notizen gehen")
            } footer: {
                Text("Ohne Ziel bleiben die Notizen in Earnote. Einzelne Notizen teilst du jederzeit über das Teilen-Menü.")
            }

            ForEach(enabled) { destination in
                Section {
                    if let problem = destinations.setupProblem(destination.id, library.settings.destinations) {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    PhoneDestinationSetup(id: destination.id, settings: $library.settings.destinations)
                } header: {
                    Text(destination.name)
                }
            }

            if !enabled.isEmpty {
                Section {
                    Toggle("Vollständiges Transkript mitexportieren", isOn: $library.settings.destinations.includeTranscript)
                }
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isEnabled(_ id: String) -> Binding<Bool> {
        Binding(get: { library.settings.destinations.enabled.contains(id) },
                set: { on in
                    if on { library.settings.destinations.enabled.insert(id) }
                    else { library.settings.destinations.enabled.remove(id) }
                    // Einmal jetzt fragen: Später läuft der Export oft im Hintergrund, da kann iOS nicht fragen
                    if on && id == RemindersDestination.id {
                        Task { _ = try? await EKEventStore().requestFullAccessToReminders() }
                    }
                })
    }
}

/// Die Felder, die ein einzelnes Ziel braucht
private struct PhoneDestinationSetup: View {
    let id: String
    @Binding var settings: DestinationSettings

    var body: some View {
        switch id {
        case NotionDestination.id:
            PhoneNotionSetup(settings: $settings)
        case ObsidianDestination.id:
            FolderPickerRow(id: id, title: "Vault", placeholder: "Kein Vault gewählt", settings: $settings)
            TextField("Unterordner im Vault", text: $settings.obsidianFolder)
            Text("Wähle den Ordner deines Obsidian-Vaults, meist in iCloud Drive › Obsidian.")
                .font(.footnote).foregroundStyle(.secondary)
        case MarkdownDestination.id:
            FolderPickerRow(id: id, title: "Ordner", placeholder: "Auf meinem iPhone › Earnote", settings: $settings)
            Text("Eine Datei pro Notiz. Ohne eigenen Ordner findest du sie in der Dateien-App unter „Auf meinem iPhone › Earnote“.")
                .font(.footnote).foregroundStyle(.secondary)
        case LogseqDestination.id:
            FolderPickerRow(id: id, title: "Graph", placeholder: "Kein Graph gewählt", settings: $settings)
            Text("Die Seite landet im Unterordner „pages“ – Aufgaben werden zu TODO-Blöcken.")
                .font(.footnote).foregroundStyle(.secondary)
        case TodoistDestination.id:
            PhoneTodoistSetup(settings: $settings)
        case RemindersDestination.id:
            TextField("Liste (leer = je Bereich eine eigene)", text: $settings.remindersList)
        default:
            EmptyView()
        }
    }
}

/// Ordner über die Dateien-App wählen; die Freigabe merkt sich `FolderAccess`
private struct FolderPickerRow: View {
    let id: String
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var settings: DestinationSettings
    @State private var picking = false
    @State private var failed = false

    private var path: String {
        FolderAccess.keyPath(for: id).map { settings[keyPath: $0] } ?? ""
    }

    var body: some View {
        Button { picking = true } label: {
            LabeledContent(title) {
                if path.isEmpty { Text(placeholder) } else { Text(FileManager.default.displayName(atPath: path)) }
            }
        }
        .foregroundStyle(.primary)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result, let keyPath = FolderAccess.keyPath(for: id) else { return }
            if FolderAccess.remember(url, for: id) { settings[keyPath: keyPath] = url.path } else { failed = true }
        }
        .alert("Auf diesen Ordner darf Earnote nicht zugreifen. Wähle einen anderen.", isPresented: $failed) {}
        if !path.isEmpty, id == MarkdownDestination.id {
            Button("Zurück zu „Auf meinem iPhone“", role: .destructive) {
                FolderAccess.forget(id)
                settings.markdownFolderPath = ""
            }
        }
    }
}

/// Notion in vier Schritten – wie am Mac. Danach nur noch Status und „Trennen“.
private struct PhoneNotionSetup: View {
    @Binding var settings: DestinationSettings
    @Environment(LibraryStore.self) private var library
    @State private var token = ""
    @State private var pageLink = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        if !settings.notionDatabaseID.isEmpty {
            Label("Verbunden mit der Datenbank „Earnote“", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            if let url = URL(string: settings.notionDatabaseURL), !settings.notionDatabaseURL.isEmpty {
                Link("In Notion öffnen", destination: url)
            }
            Button("Trennen", role: .destructive) {
                settings.notionDatabaseID = ""
                settings.notionDatabaseURL = ""
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Auf notion.so eine interne Integration anlegen (z. B. „\(AppInfo.name)“).")
                Link("Integrationen in Notion öffnen", destination: URL(string: "https://www.notion.so/profile/integrations")!)
                Text("2. Das „Internal Integration Secret“ unten einsetzen.")
                Text("3. In Notion die Seite öffnen, unter der die Datenbank entstehen soll: „•••“ › „Verbindungen“ › deine Integration hinzufügen.")
                Text("4. Den Link dieser Seite unten einsetzen.")
            }
            .font(.footnote)
            SecureField("Integration Secret (ntn_…)", text: $token)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onAppear { if token.isEmpty { token = Keychain.notionToken ?? "" } }
            TextField("Link der Notion-Seite", text: $pageLink)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Text("Datenbank anlegen")
                    if busy { Spacer(); ProgressView() }
                }
            }
            .disabled(token.isEmpty || pageLink.isEmpty || busy)
            if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        Keychain.notionToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let workspace = try await NotionDestination.testToken()
            status = String(localized: "Verbunden mit \(workspace) – Datenbank wird angelegt …")
            let database = try await NotionDestination.createDatabase(parentLink: pageLink, categories: library.categories)
            settings.notionDatabaseID = database.id
            settings.notionDatabaseURL = database.url
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }
}

/// Todoist: Schlüssel im Schlüsselbund, Projekt optional
private struct PhoneTodoistSetup: View {
    @Binding var settings: DestinationSettings
    @State private var token = ""

    var body: some View {
        SecureField("API-Schlüssel", text: $token)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .onAppear { token = Keychain.todoistToken ?? "" }
            .onChange(of: token) { _, new in
                guard !new.isEmpty else { return }
                Keychain.todoistToken = new
            }
        TextField("Projekt (leer = je Bereich ein eigenes)", text: $settings.todoistProject)
        Link("Schlüssel in den Todoist-Einstellungen holen …", destination: URL(string: "https://app.todoist.com/app/settings/integrations/developer")!)
            .font(.footnote)
    }
}
