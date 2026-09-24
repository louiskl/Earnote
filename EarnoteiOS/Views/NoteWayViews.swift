import EarnoteCore
import EarnoteML
import FoundationModels
import SwiftUI

/// Wo die Notiz entsteht – für Einsteiger (docs/IPHONE.md, Abschnitt 2): höchstens drei verständliche Wege mit Häkchen,
/// Fachbegriffe erst unter „Weitere Anbieter“. Die Auswahl steht nur in den Einstellungen (`ai.provider`, `processOnMac`).
enum NoteWay: Equatable {
    /// Auf dem iPhone: lokales Modell oder, wo das nicht passt, Apple Intelligence – beides ohne Schlüssel
    case onDevice
    case mac
    case google
    /// Einer der weiteren Anbieter oder „Nur Transkript“
    case other

    /// Welche Art „auf diesem iPhone“ hier geht (nil = keine)
    static var onDeviceProvider: AIProviderKind? {
        if DeviceCapabilities.supportsLocalModel { return .localModel }
        if appleIntelligenceEligible { return .appleIntelligence }
        return nil
    }

    /// Das Gerät kann Apple Intelligence – eingeschaltet oder nicht (dann erklären wir es)
    static var appleIntelligenceEligible: Bool {
        if case .unavailable(.deviceNotEligible) = SystemLanguageModel.default.availability { return false }
        return true
    }

    /// Anbieter unter „Weitere Anbieter“
    static var otherProviders: [AIProviderKind] {
        // OpenRouter zuerst: kostenlos wie Google, nur mit anderem Konto
        var list: [AIProviderKind] = [.openRouter, .anthropic, .openAI, .mistral]
        if onDeviceProvider == .localModel && appleIntelligenceEligible { list.insert(.appleIntelligence, at: 0) }
        return list + [.none]
    }

    /// Vorschlag beim ersten Start: auf dem Gerät, sonst Google
    static var suggestedProvider: AIProviderKind { onDeviceProvider ?? .gemini }

    /// Der Standard des Kerns („lokal, sonst Apple Intelligence“) passt nicht zu jedem iPhone – z. B. iPhone 15 (6 GB, ohne Apple Intelligence)
    static func worksHere(_ provider: AIProviderKind) -> Bool {
        switch provider {
        case .none: false
        case .localModel: DeviceCapabilities.supportsLocalModel
        case .appleIntelligence: appleIntelligenceEligible
        default: true
        }
    }
}

// MARK: - Auswahl

struct NoteWayPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HandoffSender.self) private var handoffs
    @State private var settingUpGoogle = false

    private var current: NoteWay {
        let provider = library.settings.ai.provider
        if library.settings.processOnMac && library.settings.syncWithCloud { return .mac }
        if provider == NoteWay.onDeviceProvider { return .onDevice }
        return provider == .gemini ? .google : .other
    }

    private var googleReady: Bool { !(Keychain.apiKey(for: .gemini) ?? "").isEmpty }

    var body: some View {
        @Bindable var library = library
        Section {
            if let provider = NoteWay.onDeviceProvider {
                WayRow(title: "Auf diesem iPhone", detail: onDeviceDetail(provider), symbol: "iphone",
                       isSelected: current == .onDevice) { choose(provider) }
                if current == .onDevice && provider == .localModel { LocalModelRow() }
                if current == .onDevice, provider == .appleIntelligence, let problem = appleIntelligenceProblem {
                    Text(problem).font(.footnote).foregroundStyle(.orange)
                }
            }
            WayRow(title: "Mit meinem Mac", detail: macDetail, symbol: "macbook",
                   isSelected: current == .mac) { chooseMac() }
            WayRow(title: "Kostenlos mit Google-Konto",
                   detail: googleReady ? String(localized: "Eingerichtet · nur der Text geht an Google")
                                       : String(localized: "Einmal einrichten, dauert zwei Minuten"),
                   symbol: "g.circle", isSelected: current == .google,
                   accessory: googleReady ? nil : String(localized: "Einrichten")) {
                if googleReady { choose(.gemini) } else { settingUpGoogle = true }
            }
            // Am Zeileninhalt statt an der Section: Blätter an einer Section in einer Form schließen das umgebende Blatt
            .background { Color.clear.sheet(isPresented: $settingUpGoogle) { GoogleSetupSheet { choose(.gemini) } } }
            NavigationLink {
                OtherProvidersView()
            } label: {
                LabeledContent("Weitere Anbieter", value: current == .other ? library.settings.ai.provider.label : "")
            }
            Picker("Sprache der Notiz", selection: $library.settings.ai.summaryLanguage) {
                ForEach(Self.languages, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
            }
        } header: {
            Text("So entsteht die Notiz")
        } footer: {
            NavigationLink("Welcher Weg passt zu mir?") { NoteWayHelpView() }
                .font(.footnote)
        }
    }

    static let languages = ["Deutsch", "Englisch", "Französisch", "Spanisch", "Italienisch", "Sprache der Aufnahme"]

    private func choose(_ provider: AIProviderKind) {
        library.settings.ai.provider = provider
        library.settings.processOnMac = false
    }

    /// Mac: Abgleich einschalten (wirkt ab dem nächsten Start) und den Mac schreiben lassen, sobald er gefunden ist
    private func chooseMac() {
        library.settings.syncWithCloud = true
        library.settings.processOnMac = true
    }

    private func onDeviceDetail(_ provider: AIProviderKind) -> String {
        provider == .localModel ? String(localized: "Ohne Internet · alles bleibt auf dem iPhone")
                                : String(localized: "Mit Apple Intelligence · ohne Internet, ohne Einrichtung")
    }

    private var appleIntelligenceProblem: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled):
            String(localized: "Schalte Apple Intelligence in den iPhone-Einstellungen ein, dann geht es sofort.")
        case .unavailable(.modelNotReady): String(localized: "Apple Intelligence wird gerade geladen – das dauert einen Moment.")
        default: nil
        }
    }

    private var macDetail: String {
        if !library.settings.syncWithCloud {
            return String(localized: "Dein Mac schreibt die Notiz · braucht Earnote auf dem Mac")
        }
        if handoffs.macs.isEmpty {
            return String(localized: "Suche deinen Mac … Öffne Earnote dort und schalte den Abgleich ein.")
        }
        return String(localized: "\(handoffs.macs.map(\.name).joined(separator: ", ")) schreibt die Notiz, schont den Akku")
    }
}

/// Eine wählbare Zeile mit Häkchen – wie die Auswahllisten in den iOS-Einstellungen
private struct WayRow: View {
    let title: LocalizedStringKey
    let detail: String
    let symbol: String
    let isSelected: Bool
    var accessory: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                } else if let accessory {
                    Text(accessory).font(.subheadline).foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Stand des lokalen Modells: geladen, lädt gerade, oder Knopf zum Laden
struct LocalModelRow: View {
    @ObservedObject private var manager = LocalModelManager.shared

    var body: some View {
        if LocalModelManager.isInstalled(manager.selected) {
            Label("Bereit – alles bleibt auf dem iPhone", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        } else if manager.isDownloading {
            ProgressView(value: manager.progress) { Text("Wird geladen …").font(.footnote) }
        } else {
            Button("Jetzt laden (~\(manager.selected.sizeGB.formatted(.number.precision(.fractionLength(1)))) GB, am besten im WLAN)",
                   systemImage: "arrow.down.circle") { manager.download() }
                .font(.footnote)
        }
    }
}

// MARK: - Google einrichten

/// Geführt durch drei Schritte: Seite öffnen, Schlüssel erstellen, einfügen – danach sofort prüfen
struct GoogleSetupSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var state = CheckState.idle

    enum CheckState: Equatable { case idle, checking, ok, failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Step(number: 1, text: "Öffne die Seite von Google und melde dich mit deinem Google-Konto an.")
                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        Label("Google AI Studio öffnen", systemImage: "safari")
                    }
                    Step(number: 2, text: "Tippe auf „Create API key“ und kopiere den Schlüssel.")
                    Step(number: 3, text: "Komm zurück und füge ihn hier ein.")
                } footer: {
                    Text("Kostenlos, ohne Kreditkarte, ab 18 Jahren (Bedingung von Google). Earnote schickt nur den Text der Aufnahme an Google, nie das Audio.")
                }
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        Task { @MainActor in
                            key = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            await check()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    status
                }
            }
            .navigationTitle("Google einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onDone()
                        dismiss()
                    }
                    .disabled(state != .ok)
                }
            }
            .sensoryFeedback(.success, trigger: state == .ok)
        }
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            Label { Text("Wird geprüft …") } icon: { ProgressView() }
        case .ok:
            Label("Klappt! Earnote schreibt deine Notizen jetzt mit Google.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    /// Mini-Anfrage mit dem eingefügten Schlüssel; gespeichert wird er erst, wenn sie klappt
    private func check() async {
        guard !key.isEmpty else { return }
        state = .checking
        do {
            _ = try await GeminiClient(apiKey: key, model: "").complete(system: "Antworte mit einem Wort.", prompt: "Sag OK.")
            Keychain.setAPIKey(key, for: .gemini)
            state = .ok
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.tint, in: .circle)
            Text(text)
        }
    }
}

// MARK: - Weitere Anbieter

/// Für Fortgeschrittene: andere KI-Anbieter mit eigenem Schlüssel, Apple Intelligence, oder nur das Transkript
struct OtherProvidersView: View {
    @Environment(LibraryStore.self) private var library
    @State private var apiKey = ""

    var body: some View {
        let provider = library.settings.ai.provider
        Form {
            Section {
                ForEach(NoteWay.otherProviders, id: \.self) { kind in
                    Button {
                        library.settings.ai.provider = kind
                        library.settings.processOnMac = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.label).foregroundStyle(.primary)
                                Text(kind.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if provider == kind { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            } footer: {
                Text("Diese Anbieter rechnen nach Nutzung über deinen eigenen API-Schlüssel ab. Nur der Text geht an sie, nie das Audio.")
            }
            if provider.needsAPIKey {
                Section {
                    SecureField("Schlüssel einfügen", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: apiKey) { Keychain.setAPIKey(apiKey, for: provider) }
                    if provider == .openRouter {
                        Link(destination: OpenRouterClient.keysPage) { Label("Schlüssel bei OpenRouter erstellen", systemImage: "key") }
                        Link(destination: OpenRouterClient.privacyPage) { Label("Kostenlose Modelle freigeben", systemImage: "hand.raised") }
                    }
                } header: {
                    Text("API-Schlüssel für \(provider.label)")
                } footer: {
                    if provider == .openRouter {
                        Text("Kostenlos, ohne Kreditkarte, ab 18 Jahren (Bedingung von OpenRouter). Earnote wählt selbst ein gutes kostenloses Modell. OpenRouter verlangt, dass du kostenlose Modelle in den Datenschutz-Einstellungen freigibst – deren Anbieter dürfen den Text zum Training nutzen. Für vertrauliche Aufnahmen nimm lieber „Auf diesem iPhone“ oder „Mit meinem Mac“.")
                    }
                }
            }
        }
        .navigationTitle("Weitere Anbieter")
        .task(id: provider) { apiKey = Keychain.apiKey(for: provider) ?? "" }
    }
}

// MARK: - Hilfe

struct NoteWayHelpView: View {
    var body: some View {
        List {
            Section {
                DisclosureGroup("Welcher Weg passt zu mir?") {
                    Text("Hast du Earnote auf dem Mac, nimm „Mit meinem Mac“: Das iPhone nimmt nur auf, der Mac schreibt die Notiz und schont deinen Akku. Ohne Mac: „Auf diesem iPhone“, wenn es angeboten wird – sonst „Kostenlos mit Google-Konto“.")
                }
                DisclosureGroup("Was kostet das?") {
                    Text("Nichts. Auf dem iPhone und mit dem Mac rechnet die KI auf deinen eigenen Geräten. Google und OpenRouter bieten ein kostenloses Kontingent, das für Vorlesungen reicht – beide erst ab 18 Jahren. Claude, OpenAI und Mistral rechnen nach Nutzung über deinen eigenen Schlüssel ab.")
                }
                DisclosureGroup("Was passiert mit meinen Daten?") {
                    Text("Die Aufnahme verlässt dein iPhone nie – außer beim Weg „Mit meinem Mac“, dann geht sie über deine eigene iCloud zum Mac und wird danach gelöscht. Bei Google und den weiteren Anbietern geht nur der geschriebene Text dorthin, nie das Audio. Google nutzt ihn in der EU, der Schweiz und Großbritannien auch im kostenlosen Kontingent nicht zum Training, anderswo schon. Bei OpenRouter dürfen die Anbieter kostenloser Modelle ihn nutzen. Für Vertrauliches nimm das iPhone oder den Mac.")
                }
                DisclosureGroup("Der Google-Schlüssel geht nicht") {
                    Text("Kopiere den Schlüssel noch einmal vollständig (er beginnt meist mit „AIza“) und füge ihn erneut ein. Meldet Earnote, das Kontingent sei aufgebraucht, warte ein paar Minuten. Hilft das nicht, erstelle auf aistudio.google.com einen neuen Schlüssel.")
                }
            }
        }
        .navigationTitle("Hilfe")
    }
}
