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
                    // Von der Organisation gesperrte Anbieter stehen gar nicht erst zur Wahl
                    ForEach(AIProviderKind.allCases.filter { $0 != .localModel && library.managed.allows($0) }) {
                        Text($0.label).tag($0)
                    }
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
                    if !library.managed.allowsCloudAI {
                        Label("Deine Organisation erlaubt nur KI, die auf dem Mac bleibt.", systemImage: "building.2")
                    }
                    if provider.sendsDataOffDevice {
                        Label("Das Transkript wird zur Zusammenfassung an \(provider.label) gesendet. Für vertrauliche Gespräche ist die lokale KI die sichere Wahl.",
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
        // Nur Anbieter mit Schlüssel im Schlüsselbund nachsehen – jede Abfrage kann einen
        // Passwort-Dialog auslösen, und die eingebaute KI braucht gar keinen Schlüssel.
        .onAppear { apiKey = provider.needsAPIKey ? (Keychain.apiKey(for: provider) ?? "") : "" }
        .onChange(of: provider) { _, new in
            apiKey = new.needsAPIKey ? (Keychain.apiKey(for: new) ?? "") : ""
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
            guard let client = try llm.make(library.settings.ai) else { testResult = String(localized: "Keine KI ausgewählt"); return }
            let answer = try await client.complete(system: "Antworte sehr kurz.", prompt: "Sag auf Deutsch Hallo und nenne dein Modell.")
            testResult = "✓ " + answer.prefix(120)
        } catch {
            testResult = String(localized: "Fehler: \(error.localizedDescription)")
        }
    }
}

/// Die eingebaute KI: Modell wählen, einmal laden, danach privat, kostenlos und offline.
/// Vorausgewählt ist, was zu diesem Mac passt – größer ist nicht automatisch besser.
struct LocalModelSection: View {
    @Environment(LibraryStore.self) private var library
    @ObservedObject private var manager = LocalModelManager.shared

    private var selected: LocalModelInfo { LocalModels.resolved(library.settings) }
    private var recommended: LocalModelInfo { LocalModelCatalog.recommended() }
    /// Was „Automatisch“ gerade bedeutet – ein schon geladenes Modell geht der Empfehlung vor
    private var automatic: LocalModelInfo {
        var withoutChoice = library.settings
        withoutChoice.ai.localModel = ""
        return LocalModels.resolved(withoutChoice)
    }

    var body: some View {
        @Bindable var library = library
        Section {
            Picker("Modell", selection: $library.settings.ai.localModel) {
                // Leere Kennung heißt „nimm, was zu diesem Mac passt“ – auch wenn der Mac später wechselt
                Text("Automatisch (\(automatic.name))").tag("")
                Divider()
                ForEach(LocalModelCatalog.all) { model in
                    Text(label(for: model)).tag(model.id)
                }
            }
            .disabled(manager.isDownloading)
            Text(selected.detail)
                .font(.callout).foregroundStyle(.secondary)
            LabeledContent("Status") { status }
        } header: {
            Text("Eingebaute KI")
        } footer: {
            Text(footerText)
        }
    }

    /// „Qwen3 4B · 2,3 GB · empfohlen“ bzw. „… · braucht 16 GB“
    private func label(for model: LocalModelInfo) -> String {
        var parts = [model.name, model.sizeText]
        if !LocalModelCatalog.fits(model) {
            parts.append(String(localized: "braucht \(Int(model.minMemoryGB)) GB"))
        } else if model.id == recommended.id {
            parts.append(String(localized: "empfohlen"))
        }
        if manager.installedModels.contains(model.id) { parts.append(String(localized: "geladen")) }
        return parts.joined(separator: " · ")
    }

    private var footerText: String {
        if let reason = LocalModelManager.unsupportedReason { return reason }
        if manager.isInstalled {
            return String(localized: "Die Notizen entstehen direkt auf deinem Mac – ohne Konto, ohne Abo, auch ohne Internet.")
        }
        if !LocalModelCatalog.fits(selected) {
            return String(localized: "Dieses Modell braucht mindestens \(Int(selected.minMemoryGB)) GB Arbeitsspeicher. Dieser Mac hat \(Int(DeviceCapabilities.memoryGB)) GB – nimm lieber „\(recommended.name)“.")
        }
        return String(localized: "Einmaliger Download: \(selected.sizeText). Danach schreibt \(AppInfo.name) die Notizen direkt auf deinem Mac – ohne Konto, ohne Abo, auch ohne Internet.")
    }

    @ViewBuilder private var status: some View {
        if let reason = LocalModelManager.unsupportedReason {
            Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else if manager.isDownloading {
            HStack {
                ProgressView(value: manager.progress).frame(width: 120)
                Text("\(Int(manager.progress * 100)) %").font(.callout.monospacedDigit())
                Button("Abbrechen") { manager.cancelDownload() }
            }
        } else if manager.isInstalled {
            HStack {
                Label("Bereit", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
                Button("Löschen") { manager.delete(selected) }
                    .help("Gibt \(selected.sizeText) Speicherplatz frei.")
            }
        } else if let error = manager.lastError {
            HStack {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Erneut laden") { manager.download(selected) }
            }
        } else {
            Button("Laden (\(selected.sizeText))") { manager.download(selected) }
        }
    }
}
