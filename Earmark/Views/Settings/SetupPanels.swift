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
                    Text("Whisper-Modell").font(Theme.Font.body.weight(.semibold))
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
                    .font(Theme.Font.heading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label).font(Theme.Font.body.weight(.semibold))
                    Text(detail).font(Theme.Font.small).foregroundStyle(.secondary).fittingHeight()
                }
                Spacer()
            }
            .card(padding: 12)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
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
                Text(m.title).font(Theme.Font.body.weight(.medium))
                Text(m.detail).font(Theme.Font.caption).foregroundStyle(.secondary)
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

    @State private var showOthers = false

    private var provider: AIProviderKind { app.settings.ai.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LocalModelCard(selected: provider == .localModel) {
                app.settings.ai.provider = .localModel
            }

            DisclosureGroup(isExpanded: $showOthers) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)], spacing: 8) {
                    ForEach(AIProviderKind.allCases.filter { $0 != .localModel }) { p in providerTile(p) }
                }
                .padding(.top, Theme.Space.s)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Andere KI-Anbieter").font(Theme.Font.body.weight(.semibold))
                    Text("Apple Intelligence, Claude, ChatGPT, Gemini, eigene Server … für Fortgeschrittene")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }

            if provider != .localModel {
            VStack(alignment: .leading, spacing: 10) {
                Text(provider.subtitle).font(Theme.Font.small).foregroundStyle(.secondary)

                if provider.sendsDataOffDevice {
                    Label("Das Transkript wird zur Zusammenfassung an \(provider.label) gesendet. "
                          + "Für vertrauliche Gespräche ist die Earmark-KI die sicherere Wahl.",
                          systemImage: "exclamationmark.shield")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.orange)
                        .fittingHeight()
                }

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

            if provider == .localModel {
                Picker("Sprache der Notizen", selection: $app.settings.ai.summaryLanguage) {
                    ForEach(["Deutsch", "Englisch", "Französisch", "Spanisch", "Italienisch", "Sprache der Aufnahme"], id: \.self) { Text($0) }
                }
            }
        }
        .onAppear {
            apiKey = Keychain.apiKey(for: provider) ?? ""
            showOthers = provider != .localModel
        }
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
            HStack(spacing: Theme.Space.m) {
                Image(systemName: p.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? .white : Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accentSoft)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.label).font(Theme.Font.small.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(p.isLocal ? "Lokal · kostenlos" : p.needsAPIKey ? "Cloud · API-Schlüssel" : p == AIProviderKind.none ? "Aus" : "Cloud · Abo")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.s + 2)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.07) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
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

/// Empfehlung für alle: Earmarks eigenes Modell, mit Erklärung, warum lokal gut ist.
struct LocalModelCard: View {
    @ObservedObject var model = LocalModelManager.shared
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Space.s) {
                        Text("Earmark-KI").font(Theme.Font.heading)
                        Text("Empfohlen")
                            .font(Theme.Font.caption.weight(.semibold))
                            .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentSoft))
                            .foregroundStyle(Theme.accent)
                    }
                    Text("Schreibt deine Notizen direkt auf deinem Mac – ganz ohne Cloud.")
                        .font(Theme.Font.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                benefit("hand.raised.fill", "Vertraulich",
                        "Kein Wort aus deinen Meetings verlässt den Mac. Ideal für Kundengespräche, Personalthemen, Gesundheit oder Interna.")
                benefit("eurosign.circle.fill", "Kostenlos", "Kein Abo, kein Konto, keine API-Schlüssel.")
                benefit("wifi.slash", "Funktioniert offline", "Auch im Zug oder Flugzeug – nach dem einmaligen Download.")
                benefit("sparkles", "Gute Notizen", "Deutlich genauer als Apple Intelligence und schafft auch lange Aufnahmen am Stück.")
            }
            .padding(.leading, 54)

            Divider().padding(.leading, 54)

            HStack(spacing: Theme.Space.m) {
                status
                Spacer()
                actions
            }
            .padding(.leading, 54)
        }
        .card(padding: Theme.Space.l, elevated: selected)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { if LocalModelManager.isSupported { onSelect() } }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        .animation(.easeOut(duration: 0.2), value: model.isDownloading)
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 16)
            (Text(title + ": ").font(Theme.Font.small.weight(.semibold)) + Text(detail).font(Theme.Font.small))
                .foregroundStyle(.primary)
                .fittingHeight()
        }
    }

    @ViewBuilder private var status: some View {
        if let reason = LocalModelManager.unsupportedReason {
            Label(reason, systemImage: "exclamationmark.triangle").font(Theme.Font.caption).foregroundStyle(.orange)
        } else if model.isInstalled {
            Label("Bereit – \(LocalModelManager.standard.name) ist geladen", systemImage: "checkmark.circle.fill")
                .font(Theme.Font.caption).foregroundStyle(.green)
        } else if model.isDownloading {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wird geladen … \(Int(model.progress * 100)) %")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                ProgressLine(progress: model.progress).frame(maxWidth: 260)
            }
        } else if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle").font(Theme.Font.caption).foregroundStyle(.orange)
        } else {
            Text("Einmaliger Download: \(LocalModelManager.standard.sizeText). Läuft auf Macs mit Apple-Chip.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        if LocalModelManager.isSupported {
            if model.isInstalled {
                Menu {
                    Button("Modell löschen (\(LocalModelManager.standard.sizeText) freigeben)", role: .destructive) { model.delete() }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            } else if model.isDownloading {
                Button("Abbrechen") { model.cancelDownload() }.buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    onSelect()
                    model.download()
                } label: {
                    Label("Laden", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
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
                Image(systemName: d.symbol).font(Theme.Font.heading)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(Theme.Font.body.weight(.semibold))
                    if enabled, let problem {
                        Label(problem, systemImage: "exclamationmark.circle").font(Theme.Font.caption).foregroundStyle(.orange)
                    } else {
                        Text(d.detail).font(Theme.Font.caption).foregroundStyle(.secondary).fittingHeight()
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
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary).fittingHeight() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String, link: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Theme.Font.caption.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(Theme.Font.small).fittingHeight()
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
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Bereiche ordnen deine Aufnahmen – z. B. pro Projekt, Kunde oder Studienfach. Jeder Bereich kann eigene Hinweise für die KI haben.")
                .font(Theme.Font.small).foregroundStyle(.secondary)
                .padding(.bottom, Theme.Space.s)
            ForEach(app.categories) { c in
                HStack(spacing: Theme.Space.m) {
                    c.badge(size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(c.name).font(Theme.Font.body.weight(.semibold))
                            if app.settings.defaultCategoryID == c.id {
                                Text("Standard").font(Theme.Font.caption.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(c.color.opacity(0.14))).foregroundStyle(c.color)
                            }
                        }
                        Text(c.instructions.isEmpty ? "Allgemeine Notizen" : c.instructions.replacingOccurrences(of: "\n", with: " "))
                            .font(Theme.Font.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Bearbeiten") { editing = c }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(Theme.Space.m)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.035)))
            }
            Button { adding = true } label: { Label("Bereich hinzufügen", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Theme.Space.s)
        }
        .sheet(item: $editing) { c in
            CategoryEditorSheet(category: c) { editing = nil }.environmentObject(app)
        }
        .sheet(isPresented: $adding) {
            AddCategorySheet { _ in adding = false }.environmentObject(app)
        }
    }
}

