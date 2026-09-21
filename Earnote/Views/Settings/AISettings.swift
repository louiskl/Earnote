import EarnoteCore
import EarnoteML
import SwiftUI

/// KI-Einstellungen: standardmäßig die eingebaute lokale KI, für Fortgeschrittene auch andere Anbieter.
struct AISettings: View {
    let llm: LLMFactory
    @Environment(LibraryStore.self) private var library

    static let summaryLanguages = ["Deutsch", "Englisch", "Französisch", "Spanisch", "Italienisch", "Sprache der Aufnahme"]

    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var knownModels: [String] = []

    private var provider: AIProviderKind { library.settings.ai.provider }

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Picker("KI für die Notizen", selection: $library.settings.ai.provider) {
                    Text("Lokale KI (empfohlen)").tag(AIProviderKind.localModel)
                    Divider()
                    ForEach(AIProviderKind.allCases.filter { $0 != .localModel }) { Text($0.label).tag($0) }
                }
                Toggle("Einfach erklärt", isOn: $library.settings.ai.simpleNotes)
                    .help("Kurze Sätze, alltägliche Wörter, Fachbegriffe werden erklärt.")
                Picker("Sprache der Notizen", selection: $library.settings.ai.summaryLanguage) {
                    // Der gespeicherte Wert bleibt deutsch (er geht so an die KI), übersetzt wird nur die Anzeige.
                    ForEach(Self.summaryLanguages, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.subtitle)
                    if provider.sendsDataOffDevice {
                        Label("Das Transkript wird zur Zusammenfassung an \(provider.label) gesendet. "
                              + "Für vertrauliche Gespräche ist die lokale KI die sichere Wahl.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if provider == .localModel {
                LocalModelSection()
            } else {
                providerSection(settings: $library.settings.ai)
            }
        }
        .formStyle(.grouped)
        .onAppear { apiKey = Keychain.apiKey(for: provider) ?? "" }
        .onChange(of: provider) { _, new in
            apiKey = Keychain.apiKey(for: new) ?? ""
            library.settings.ai.model = ""
            library.settings.ai.baseURL = ""
            knownModels = []
            testResult = nil
        }
    }

    // MARK: Andere Anbieter

    @ViewBuilder
    private func providerSection(settings: Binding<AIConfig>) -> some View {
        Section("Einrichtung") {
            switch provider {
            case .appleIntelligence: appleStatus
            case .ollama: link("Ollama herunterladen", "https://ollama.com/download",
                               "Danach in Ollama ein Modell laden, z. B. „qwen3:8b“.")
            case .lmStudio: link("LM Studio herunterladen", "https://lmstudio.ai",
                                 "In LM Studio unter „Developer“ den lokalen Server starten.")
            case .claudeCode: cliStatus(found: CLIClient.locate(.claude) != nil, name: "Claude Code",
                                        url: "https://docs.claude.com/en/docs/claude-code/setup")
            case .codex: cliStatus(found: CLIClient.locate(.codex) != nil, name: "Codex CLI",
                                   url: "https://github.com/openai/codex")
            default: EmptyView()
            }

            if provider.needsAPIKey {
                LabeledContent("API-Schlüssel") {
                    HStack {
                        SecureField("", text: $apiKey)
                            .onSubmit { Keychain.setAPIKey(apiKey, for: provider) }
                        Button("Speichern") {
                            Keychain.setAPIKey(apiKey, for: provider)
                            testResult = "Gespeichert"
                        }
                    }
                }
                if let url = keyLink { Link("API-Schlüssel erstellen", destination: url) }
            }

            if [AIProviderKind.ollama, .lmStudio, .openAICompatible].contains(provider) {
                TextField("Server-Adresse", text: settings.baseURL, prompt: Text(provider.defaultBaseURL))
            }

            if ![AIProviderKind.appleIntelligence, .none].contains(provider) {
                LabeledContent("Modell") {
                    HStack {
                        TextField("", text: settings.model,
                                  prompt: Text(provider.defaultModel.isEmpty ? "Standard" : provider.defaultModel))
                        if !knownModels.isEmpty {
                            Menu("Auswählen") {
                                ForEach(knownModels, id: \.self) { name in
                                    Button(name) { settings.model.wrappedValue = name }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
            }

            if provider != .none {
                LabeledContent("Verbindung") {
                    HStack {
                        Button("Testen") { Task { await test() } }
                            .disabled(testing)
                        if testing { ProgressView().controlSize(.small) }
                        if let testResult {
                            Text(testResult).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var appleStatus: some View {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let problem = AppleIntelligenceClient.availabilityText {
            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else if #available(macOS 26.0, *) {
            Label("Apple Intelligence ist bereit.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label("Benötigt macOS 26.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        #else
        Label("Benötigt macOS 26.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        #endif
    }

    private func cliStatus(found: Bool, name: String, url: String) -> some View {
        LabeledContent(name) {
            HStack {
                Label(found ? "gefunden" : "nicht gefunden", systemImage: found ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(found ? Color.green : Color.orange)
                if !found, let url = URL(string: url) { Link("Installieren", destination: url) }
            }
        }
    }

    private func link(_ title: String, _ url: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let url = URL(string: url) { Link(title, destination: url) }
            Text(detail).font(.callout).foregroundStyle(.secondary)
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

    private func test() async {
        testing = true
        defer { testing = false }
        if provider.needsAPIKey { Keychain.setAPIKey(apiKey, for: provider) }
        do {
            if let list = try? await llm.listModels(library.settings.ai), !list.isEmpty { knownModels = list }
            guard let client = try llm.make(library.settings.ai) else { testResult = "Keine KI ausgewählt"; return }
            let answer = try await client.complete(system: "Antworte sehr kurz.", prompt: "Sag auf Deutsch Hallo und nenne dein Modell.")
            testResult = "✓ " + answer.prefix(120)
        } catch {
            testResult = "Fehler: \(error.localizedDescription)"
        }
    }
}

/// Die eingebaute KI: einmal laden, danach privat, kostenlos und offline.
struct LocalModelSection: View {
    @ObservedObject private var model = LocalModelManager.shared

    var body: some View {
        Section {
            LabeledContent("Modell") {
                Text(LocalModelManager.standard.name).foregroundStyle(.secondary)
            }
            LabeledContent("Status") { status }
        } header: {
            Text("Eingebaute KI")
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        if let reason = LocalModelManager.unsupportedReason { return reason }
        if model.isInstalled {
            return "Die Notizen entstehen direkt auf deinem Mac – ohne Konto, ohne Abo, auch ohne Internet."
        }
        return "Einmaliger Download: \(LocalModelManager.standard.sizeText). Danach schreibt \(AppInfo.name) die Notizen "
            + "direkt auf deinem Mac – ohne Konto, ohne Abo, auch ohne Internet."
    }

    @ViewBuilder private var status: some View {
        if let reason = LocalModelManager.unsupportedReason {
            Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else if model.isDownloading {
            HStack {
                ProgressView(value: model.progress).frame(width: 120)
                Text("\(Int(model.progress * 100)) %").font(.callout.monospacedDigit())
                Button("Abbrechen") { model.cancelDownload() }
            }
        } else if model.isInstalled {
            HStack {
                Label("Bereit", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
                Button("Löschen") { model.delete() }
                    .help("Gibt \(LocalModelManager.standard.sizeText) Speicherplatz frei.")
            }
        } else if let error = model.lastError {
            HStack {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Erneut laden") { model.download() }
            }
        } else {
            Button("Laden") { model.download() }
        }
    }
}
