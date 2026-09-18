import AppKit
import EarnoteCore
import SwiftUI

/// Ziele: erst an- oder abschalten, darunter die Einrichtung der eingeschalteten Ziele.
struct DestinationsSettings: View {
    @Environment(LibraryStore.self) private var library

    private var enabledDestinations: [DestinationInfo] {
        Destinations.all.filter { library.settings.destinations.enabled.contains($0.id) }
    }

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                ForEach(Destinations.all, id: \.id) { destination in
                    Toggle(isOn: isEnabled(destination.id)) {
                        Text(destination.name)
                        Text(destination.detail)
                    }
                }
            } header: {
                Text("Wohin \(AppInfo.name) fertige Notizen legt")
            } footer: {
                Text("Ohne Ziel bleiben die Notizen einfach in \(AppInfo.name).")
            }

            ForEach(enabledDestinations, id: \.id) { destination in
                Section(destination.name) {
                    if let problem = problem(destination) {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    DestinationSetup(id: destination.id, settings: $library.settings.destinations)
                }
            }

            if !enabledDestinations.isEmpty {
                Section {
                    Toggle("Vollständiges Transkript mitexportieren", isOn: $library.settings.destinations.includeTranscript)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func problem(_ destination: DestinationInfo) -> String? {
        guard library.settings.destinations.enabled.contains(destination.id) else { return nil }
        return Destinations.setupProblem(destination.id, library.settings.destinations)
    }

    private func isEnabled(_ id: String) -> Binding<Bool> {
        Binding(get: { library.settings.destinations.enabled.contains(id) },
                set: { on in
                    if on { library.settings.destinations.enabled.insert(id) }
                    else { library.settings.destinations.enabled.remove(id) }
                })
    }
}

/// Die Felder, die ein einzelnes Ziel braucht.
private struct DestinationSetup: View {
    let id: String
    @Binding var settings: DestinationSettings

    var body: some View {
        switch id {
        case NotionDestination.id:
            NotionSetup(settings: $settings)
        case ObsidianDestination.id:
            FolderRow(title: "Vault", path: $settings.obsidianVaultPath, prompt: "Kein Vault gewählt",
                      message: "Wähle deinen Obsidian-Vault")
            TextField("Unterordner im Vault", text: $settings.obsidianFolder)
        case MarkdownDestination.id:
            FolderRow(title: "Ordner", path: $settings.markdownFolderPath,
                      prompt: MarkdownDestination.defaultFolder.path, message: "Ordner für Markdown-Dateien")
        case AppleNotesDestination.id:
            TextField("Ordner in Apple Notizen", text: $settings.appleNotesFolder)
            Text("Beim ersten Export fragt macOS, ob \(AppInfo.name) Notizen steuern darf – bitte erlauben.")
                .font(.callout).foregroundStyle(.secondary)
        case BearDestination.id:
            TextField("Tags (durch Komma getrennt)", text: $settings.bearTags)
        case CraftDestination.id:
            TextField("Space-ID", text: $settings.craftSpaceID)
            Text("Die Space-ID findest du in Craft mit einem Rechtsklick auf ein Dokument › „Kopieren als“ › „Deeplink“ (Wert von spaceId=…).")
                .font(.callout).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

/// Ordnerauswahl: Pfad anzeigen, per Knopf einen anderen wählen.
private struct FolderRow: View {
    let title: String
    @Binding var path: String
    let prompt: String
    let message: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? prompt : path)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Wählen …") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.message = message
                    if panel.runModal() == .OK, let url = panel.url { path = url.path }
                }
            }
        }
    }
}

/// Notion in vier Schritten verbinden. Danach nur noch Status und „Trennen“.
private struct NotionSetup: View {
    @Binding var settings: DestinationSettings
    @Environment(LibraryStore.self) private var library

    @State private var token = Keychain.notionToken ?? ""
    @State private var pageLink = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        if !settings.notionDatabaseID.isEmpty {
            LabeledContent("Verbunden") {
                HStack {
                    Label("Datenbank „\(AppInfo.name)“", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let url = URL(string: settings.notionDatabaseURL), !settings.notionDatabaseURL.isEmpty {
                        Button("In Notion öffnen") { NSWorkspace.shared.open(url) }
                    }
                    Button("Trennen") {
                        settings.notionDatabaseID = ""
                        settings.notionDatabaseURL = ""
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Auf notion.so eine interne Integration anlegen (z. B. „\(AppInfo.name)“).")
                if let url = URL(string: "https://www.notion.so/profile/integrations") {
                    Link("Integrationen in Notion öffnen", destination: url)
                }
                Text("2. Das „Internal Integration Secret“ unten einsetzen.")
                Text("3. In Notion die Seite öffnen, unter der die Datenbank entstehen soll: „•••“ › „Verbindungen“ › deine Integration hinzufügen.")
                Text("4. Den Link dieser Seite unten einsetzen.")
            }
            .font(.callout)
            SecureField("Integration Secret (ntn_…)", text: $token)
            TextField("Link der Notion-Seite", text: $pageLink)
            HStack {
                Button("Datenbank anlegen") { Task { await connect() } }
                    .disabled(token.isEmpty || pageLink.isEmpty || busy)
                if busy { ProgressView().controlSize(.small) }
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        Keychain.notionToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let workspace = try await NotionDestination.testToken()
            status = "Verbunden mit \(workspace) – Datenbank wird angelegt …"
            let database = try await NotionDestination.createDatabase(parentLink: pageLink, categories: library.categories)
            settings.notionDatabaseID = database.id
            settings.notionDatabaseURL = database.url
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }
}
