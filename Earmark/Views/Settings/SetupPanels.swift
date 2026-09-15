import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - Berechtigungen

struct PermissionsPanel: View {
    @EnvironmentObject var app: AppState
    @State private var mic = MicRecorder.permission == .authorized
    @State private var systemAudioRequested = UserDefaults.standard.bool(forKey: "systemAudioRequested")
    @State private var notifications: Bool?

    var body: some View {
        VStack(spacing: 10) {
            PermissionRow(icon: "mic.fill", title: "Mikrofon",
                          detail: "Damit Earmark deine Stimme aufnehmen kann.",
                          granted: mic) {
                Task {
                    if MicRecorder.permission == .denied { SystemSettingsLink.microphone() }
                    mic = await MicRecorder.requestPermission()
                }
            }
            PermissionRow(icon: "speaker.wave.2.fill", title: "Systemaudio",
                          detail: "Damit die anderen Teilnehmer in Zoom, Teams & Co. mit aufgenommen werden – ohne Zusatzsoftware.",
                          granted: systemAudioRequested ? true : nil,
                          action: {
                              Task {
                                  await SystemAudioTap.requestPermission()
                                  UserDefaults.standard.set(true, forKey: "systemAudioRequested")
                                  systemAudioRequested = true
                              }
                          },
                          actionTitle: "Erlauben")
            if systemAudioRequested {
                Button("Systemaudio-Berechtigung in den Systemeinstellungen prüfen") { SystemSettingsLink.systemAudio() }
                    .buttonStyle(.link).font(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            PermissionRow(icon: "bell.badge.fill", title: "Mitteilungen",
                          detail: "Damit du erfährst, wann deine Notizen fertig sind.",
                          granted: notifications) {
                Task { notifications = await Notifier.requestPermission() }
            }
        }
        .task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            notifications = s.authorizationStatus == .authorized ? true : nil
        }
    }
}

// MARK: - Transkription

struct TranscriptionPanel: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var models = WhisperModelManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Sprache der Aufnahmen", selection: $app.settings.language) {
                ForEach(AppSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
            }

            VStack(spacing: 8) {
                engineCard(.apple,
                           detail: TranscriberFactory.appleSpeechAvailable
                           ? "In macOS eingebaut. Schnell, kein Download – die Sprachdaten lädt macOS bei Bedarf selbst."
                           : "Erst ab macOS 26 verfügbar.",
                           enabled: TranscriberFactory.appleSpeechAvailable)
                engineCard(.whisperKit,
                           detail: "OpenAIs Whisper, lokal auf deinem Mac. Sehr genau, auch bei Fachbegriffen. Einmaliger Download.",
                           enabled: true)
            }

            if app.settings.transcriptionEngine == .whisperKit {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Whisper-Modell").font(.system(size: 13, weight: .semibold))
                    ForEach(WhisperModelManager.curated) { m in modelRow(m) }
                    if let err = models.lastError { Text(err).font(.caption).foregroundStyle(.orange) }
                }
            }

            Toggle("Sprecher unterscheiden („Ich“ / „Andere“)", isOn: $app.settings.speakerLabels)
            Text("Earmark erkennt anhand von Mikrofon und Systemton, wer gerade spricht.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            if app.settings.whisperModel.isEmpty { app.settings.whisperModel = WhisperModelManager.curated[0].id }
            if TranscriberFactory.appleSpeechAvailable && !app.settings.onboardingCompleted
                && models.installed.isEmpty {
                app.settings.transcriptionEngine = .apple
            }
        }
    }

    private func engineCard(_ kind: TranscriptionEngineKind, detail: String, enabled: Bool) -> some View {
        let selected = app.settings.transcriptionEngine == kind
        return Button { if enabled { app.settings.transcriptionEngine = kind } } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                }
                Spacer()
            }
            .card(padding: 12)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func modelRow(_ m: WhisperModelManager.ModelInfo) -> some View {
        let installed = models.installed[m.id] != nil
        let selected = app.settings.whisperModel == m.id
        return HStack(spacing: 10) {
            Button { app.settings.whisperModel = m.id } label: {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).font(.system(size: 13, weight: .medium))
                Text(m.detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if models.downloading == m.id {
                ProgressView(value: models.downloadProgress).frame(width: 110)
                Text("\(Int(models.downloadProgress * 100)) %").font(.caption.monospacedDigit())
            } else if installed {
                Label("Geladen", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                Button { models.delete(m.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Modell löschen")
            } else {
                Button("Laden") {
                    app.settings.whisperModel = m.id
                    Task { _ = await models.download(m.id) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(models.downloading != nil)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - KI

struct AIPanel: View {
    @EnvironmentObject var app: AppState
    @State private var apiKey = ""
    @State private var testState: String?
    @State private var testing = false
    @State private var availableModels: [String] = []

    private var provider: AIProviderKind { app.settings.ai.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                ForEach(AIProviderKind.allCases) { p in providerTile(p) }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(provider.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)

                if provider == .appleIntelligence { appleHint }
                if provider == .ollama { linkHint("Ollama herunterladen", "https://ollama.com/download",
                                                  "Danach z. B. „qwen3:8b“ oder „llama3.1:8b“ in Ollama laden.") }
                if provider == .lmStudio { linkHint("LM Studio herunterladen", "https://lmstudio.ai",
                                                    "In LM Studio unter „Developer“ den lokalen Server starten.") }
                if provider == .claudeCode {
                    cliHint(found: CLIClient.locate(.claude) != nil, name: "Claude Code",
                            url: "https://docs.claude.com/en/docs/claude-code/setup")
                }
                if provider == .codex {
                    cliHint(found: CLIClient.locate(.codex) != nil, name: "Codex CLI", url: "https://github.com/openai/codex")
                }

                if provider.needsAPIKey {
                    HStack {
                        SecureField("API-Schlüssel", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Keychain.setAPIKey(apiKey, for: provider) }
                        Button("Speichern") { Keychain.setAPIKey(apiKey, for: provider); testState = "Gespeichert" }
                    }
                    if let link = keyLink { Link("API-Schlüssel erstellen ↗", destination: link).font(.caption) }
                }

                if [AIProviderKind.ollama, .lmStudio, .openAICompatible].contains(provider) {
                    TextField("Server-Adresse", text: $app.settings.ai.baseURL, prompt: Text(provider.defaultBaseURL))
                        .textFieldStyle(.roundedBorder)
                }

                if ![AIProviderKind.appleIntelligence, AIProviderKind.none].contains(provider) {
                    HStack {
                        TextField("Modell", text: $app.settings.ai.model,
                                  prompt: Text(provider.defaultModel.isEmpty ? "Standard" : provider.defaultModel))
                            .textFieldStyle(.roundedBorder)
                        if !availableModels.isEmpty {
                            Menu("Auswählen") {
                                ForEach(availableModels, id: \.self) { m in Button(m) { app.settings.ai.model = m } }
                            }
                            .fixedSize()
                        }
                    }
                }

                Picker("Sprache der Zusammenfassung", selection: $app.settings.ai.summaryLanguage) {
                    ForEach(["Deutsch", "Englisch", "Französisch", "Spanisch", "Italienisch", "Sprache der Aufnahme"], id: \.self) { Text($0) }
                }

                if provider != AIProviderKind.none {
                    HStack {
                        Button { Task { await test() } } label: {
                            if testing { ProgressView().controlSize(.small) } else { Text("Verbindung testen") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(testing)
                        if let testState { Text(testState).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    }
                }
            }
            .card()
        }
        .onAppear { apiKey = Keychain.apiKey(for: provider) ?? "" }
        .onChange(of: app.settings.ai.provider) { _, p in
            apiKey = Keychain.apiKey(for: p) ?? ""
            app.settings.ai.model = ""
            app.settings.ai.baseURL = ""
            availableModels = []
            testState = nil
        }
    }

    private var keyLink: URL? {
        switch provider {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .openAICompatible: return URL(string: "https://openrouter.ai/keys")
        default: return nil
        }
    }

    private func providerTile(_ p: AIProviderKind) -> some View {
        let selected = provider == p
        return Button { app.settings.ai.provider = p } label: {
            HStack(spacing: 10) {
                Image(systemName: p.symbol).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? .white : Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.accent : Theme.accentSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(p.isLocal ? "Lokal · kostenlos" : p.needsAPIKey ? "API-Schlüssel" : p == AIProviderKind.none ? "Aus" : "Abo")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var appleHint: some View {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let problem = AppleIntelligenceClient.availabilityText {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            } else {
                Label("Apple Intelligence ist bereit.", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
        } else {
            Label("Benötigt macOS 26.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
        #else
        Label("Benötigt macOS 26.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        #endif
    }

    private func linkHint(_ title: String, _ url: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Link("\(title) ↗", destination: URL(string: url)!).font(.caption)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func cliHint(found: Bool, name: String, url: String) -> some View {
        HStack {
            Label(found ? "\(name) gefunden" : "\(name) nicht gefunden",
                  systemImage: found ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .foregroundStyle(found ? Color.green : Color.orange)
            if !found { Link("Installieren ↗", destination: URL(string: url)!) }
        }
        .font(.caption)
    }

    private func test() async {
        testing = true
        defer { testing = false }
        if provider.needsAPIKey { Keychain.setAPIKey(apiKey, for: provider) }
        do {
            if let models = try? await LLMFactory.listModels(app.settings.ai), !models.isEmpty { availableModels = models }
            guard let client = try LLMFactory.make(app.settings.ai) else { testState = "Keine KI ausgewählt"; return }
            let answer = try await client.complete(system: "Antworte sehr kurz.", prompt: "Sag auf Deutsch Hallo und nenne dein Modell.")
            testState = "✓ " + answer.prefix(120)
        } catch {
            testState = "Fehler: \(error.localizedDescription)"
        }
    }
}

// MARK: - Ziele

struct DestinationsPanel: View {
    @EnvironmentObject var app: AppState
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Destinations.all) { d in
                destinationCard(d)
            }
            Toggle("Vollständiges Transkript mit exportieren", isOn: $app.settings.destinations.includeTranscript)
                .padding(.top, 4)
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { app.settings.destinations.enabled.contains(id) },
            set: { on in
                if on { app.settings.destinations.enabled.insert(id); expanded = id }
                else { app.settings.destinations.enabled.remove(id) }
            })
    }

    private func destinationCard(_ d: DestinationInfo) -> some View {
        let enabled = app.settings.destinations.enabled.contains(d.id)
        let problem = Destinations.setupProblem(d.id, app.settings.destinations)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: d.symbol).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.system(size: 13, weight: .semibold))
                    if enabled, let problem {
                        Label(problem, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange)
                    } else {
                        Text(d.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
                    }
                }
                Spacer()
                if enabled {
                    Button { expanded = expanded == d.id ? nil : d.id } label: {
                        Image(systemName: "chevron.down").rotationEffect(.degrees(expanded == d.id ? 180 : 0))
                    }
                    .buttonStyle(.borderless)
                }
                Toggle("", isOn: binding(d.id)).toggleStyle(.switch).labelsHidden()
            }
            if enabled && expanded == d.id {
                Divider()
                config(for: d.id)
            }
        }
        .card(padding: 12)
    }

    @ViewBuilder
    private func config(for id: String) -> some View {
        switch id {
        case NotionDestination.id: NotionSetupView()
        case ObsidianDestination.id:
            HStack {
                Text(app.settings.destinations.obsidianVaultPath.isEmpty ? "Kein Vault gewählt" : app.settings.destinations.obsidianVaultPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Vault wählen …") {
                    if let url = pickFolder("Wähle deinen Obsidian-Vault") {
                        app.settings.destinations.obsidianVaultPath = url.path
                    }
                }
            }
            TextField("Unterordner im Vault", text: $app.settings.destinations.obsidianFolder).textFieldStyle(.roundedBorder)
        case MarkdownDestination.id:
            HStack {
                Text(app.settings.destinations.markdownFolderPath.isEmpty
                     ? MarkdownDestination.defaultFolder.path : app.settings.destinations.markdownFolderPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Ordner wählen …") {
                    if let url = pickFolder("Ordner für Markdown-Dateien") {
                        app.settings.destinations.markdownFolderPath = url.path
                    }
                }
            }
        case AppleNotesDestination.id:
            TextField("Ordner in Apple Notizen", text: $app.settings.destinations.appleNotesFolder).textFieldStyle(.roundedBorder)
            Text("Beim ersten Export fragt macOS, ob Earmark Notizen steuern darf – bitte erlauben.")
                .font(.caption).foregroundStyle(.secondary)
        case BearDestination.id:
            TextField("Tags (durch Komma getrennt)", text: $app.settings.destinations.bearTags).textFieldStyle(.roundedBorder)
        case CraftDestination.id:
            TextField("Space-ID", text: $app.settings.destinations.craftSpaceID).textFieldStyle(.roundedBorder)
            Text("Die Space-ID findest du in Craft über einen Rechtsklick auf ein Dokument › „Kopieren als“ › „Deeplink“ (Wert von spaceId=…).")
                .font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    private func pickFolder(_ message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct NotionSetupView: View {
    @EnvironmentObject var app: AppState
    @State private var token = Keychain.notionToken ?? ""
    @State private var pageLink = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !app.settings.destinations.notionDatabaseID.isEmpty {
                HStack {
                    Label("Verbunden mit der Datenbank „Earmark“", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    if let url = URL(string: app.settings.destinations.notionDatabaseURL), !app.settings.destinations.notionDatabaseURL.isEmpty {
                        Button("In Notion öffnen") { NSWorkspace.shared.open(url) }
                    }
                    Button("Trennen") {
                        app.settings.destinations.notionDatabaseID = ""
                        app.settings.destinations.notionDatabaseURL = ""
                    }
                }
                .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Öffne notion.so/profile/integrations und erstelle eine neue interne Integration (z. B. „Earmark“).",
                         link: "https://www.notion.so/profile/integrations")
                    step(2, "Kopiere das „Internal Integration Secret“ und füge es unten ein.")
                    step(3, "Öffne in Notion die Seite, unter der Earmark die Datenbank anlegen soll: „•••“ › „Verbindungen“ › deine Integration hinzufügen.")
                    step(4, "Kopiere den Link dieser Seite („Link kopieren“) und füge ihn unten ein.")
                }
                SecureField("Integration Secret (ntn_…)", text: $token).textFieldStyle(.roundedBorder)
                TextField("Link der Notion-Seite", text: $pageLink).textFieldStyle(.roundedBorder)
                HStack {
                    Button { Task { await connect() } } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text("Datenbank anlegen") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(token.isEmpty || pageLink.isEmpty || busy)
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary).fixedSize() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String, link: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 12)).fixedSize()
                if let link, let url = URL(string: link) { Link("Öffnen ↗", destination: url).font(.caption) }
            }
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        Keychain.notionToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let workspace = try await NotionDestination.testToken()
            status = "Verbunden mit \(workspace) – lege Datenbank an …"
            let db = try await NotionDestination.createDatabase(parentLink: pageLink, categories: app.categories)
            app.settings.destinations.notionDatabaseID = db.id
            app.settings.destinations.notionDatabaseURL = db.url
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }
}

// MARK: - Kategorien

struct CategoriesPanel: View {
    @EnvironmentObject var app: AppState
    @State private var editing: RecordingCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(app.categories) { c in
                HStack(spacing: 12) {
                    CategoryIcon(category: c, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(c.name).font(.system(size: 13, weight: .semibold))
                            if app.settings.defaultCategoryID == c.id {
                                Text("Standard").font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.accentSoft)).foregroundStyle(Theme.accent)
                            }
                        }
                        Text(c.instructions.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Bearbeiten") { editing = c }.buttonStyle(SecondaryButtonStyle())
                }
                .card(padding: 10)
            }
            .onMove { app.categories.move(fromOffsets: $0, toOffset: $1) }

            Button {
                editing = RecordingCategory(name: "", symbol: "star.fill", colorHex: RecordingCategory.colorChoices.randomElement()!,
                                            instructions: "Abschnitte: Kurzfassung, Themen, Aufgaben, Nächste Schritte.")
            } label: {
                Label("Neue Kategorie", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .sheet(item: $editing) { cat in
            CategoryEditor(category: cat) { edited in
                if let i = app.categories.firstIndex(where: { $0.id == edited.id }) { app.categories[i] = edited }
                else { app.categories.append(edited) }
                editing = nil
            } onDelete: {
                app.categories.removeAll { $0.id == cat.id }
                editing = nil
            } onCancel: {
                editing = nil
            }
            .environmentObject(app)
        }
    }
}

struct CategoryEditor: View {
    @EnvironmentObject var app: AppState
    @State var category: RecordingCategory
    var onSave: (RecordingCategory) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CategoryIcon(category: category, size: 48)
                TextField("Name der Kategorie", text: $category.name)
                    .textFieldStyle(.plain).font(.system(size: 20, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Symbol").font(.caption.bold()).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 10), spacing: 6) {
                    ForEach(RecordingCategory.symbolChoices, id: \.self) { s in
                        Button { category.symbol = s } label: {
                            Image(systemName: s).frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 7).fill(category.symbol == s ? category.color.opacity(0.25) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Farbe").font(.caption.bold()).foregroundStyle(.secondary)
                HStack {
                    ForEach(RecordingCategory.colorChoices, id: \.self) { hex in
                        Button { category.colorHex = hex } label: {
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.white, lineWidth: category.colorHex == hex ? 3 : 0))
                                .shadow(radius: category.colorHex == hex ? 2 : 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Anweisungen für die Zusammenfassung").font(.caption.bold()).foregroundStyle(.secondary)
                TextEditor(text: $category.instructions)
                    .font(.system(size: 12))
                    .frame(height: 120)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                Text("Beschreibe, worauf die KI achten soll und welche Abschnitte die Notizen haben sollen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Ziele für diese Kategorie").font(.caption.bold()).foregroundStyle(.secondary)
                Text("Nichts ausgewählt = alle aktivierten Ziele.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(Destinations.all.filter { app.settings.destinations.enabled.contains($0.id) }) { d in
                        Toggle(d.name, isOn: Binding(
                            get: { category.destinationIDs.contains(d.id) },
                            set: { if $0 { category.destinationIDs.insert(d.id) } else { category.destinationIDs.remove(d.id) } }))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Toggle("Als Standard-Kategorie verwenden", isOn: Binding(
                get: { app.settings.defaultCategoryID == category.id },
                set: { app.settings.defaultCategoryID = $0 ? category.id : nil }))
            HStack {
                if app.categories.contains(where: { $0.id == category.id }) && app.categories.count > 1 {
                    Button("Löschen", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Abbrechen", action: onCancel)
                Button("Sichern") { onSave(category) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
