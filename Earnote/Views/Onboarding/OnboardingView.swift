import EarnoteCore
import EarnoteML
import SwiftUI

/// Einrichtungsassistent: ein Blatt, feste Kopfzeile, Inhalt aus den Einstellungen, Knöpfe unten.
/// Die Schritte sind bewusst wenige – Ziele, Anbieter und Feineinstellungen kommen später in den Einstellungen.
struct OnboardingView: View {
    @Environment(LibraryStore.self) private var library
    var onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, categories, permissions, ai, transcription, done

        var title: String {
            switch self {
            case .welcome: return "Willkommen bei \(AppInfo.name)"
            case .categories: return "Wofür nutzt du \(AppInfo.name)?"
            case .permissions: return "Kurz ein paar Freigaben"
            case .ai: return "Wer schreibt deine Notizen?"
            case .transcription: return "Spracherkennung"
            case .done: return "Alles bereit"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: return "Deine Vorlesungen, Meetings und Calls – automatisch als Notizen, privat auf deinem Mac."
            case .categories: return "Daraus werden deine Bereiche. Du kannst sie jederzeit ändern."
            case .permissions: return "Damit \(AppInfo.name) aufnehmen und dich benachrichtigen kann."
            case .ai: return "\(AppInfo.name) bringt eine eigene KI mit, die komplett auf deinem Mac läuft."
            case .transcription: return "Die Spracherkennung läuft immer lokal. Die Voreinstellung passt für die meisten."
            case .done: return "\(AppInfo.name) wartet ab jetzt oben in der Menüleiste auf dich."
            }
        }
    }

    /// Im Debug-Build kann `EARNOTE_ONBOARDING_STEP` einen Schritt direkt öffnen (Bildschirmfotos, Design-Review)
    @State private var step: Step = Step(rawValue: Int(ProcessInfo.processInfo.environment["EARNOTE_ONBOARDING_STEP"] ?? "") ?? 0) ?? .welcome
    @State private var selectedTemplates: Set<String> = []
    @State private var subjects: [String] = []
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.title2.weight(.semibold))
                Text(step.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()
            content
            Divider()

            HStack {
                if step != .welcome {
                    Text("Schritt \(step.rawValue) von \(Step.allCases.count - 1)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if library.settings.onboardingCompleted {
                    Button("Schließen", action: onFinish).keyboardShortcut(.cancelAction)
                }
                if step != .welcome && step != .done {
                    Button("Zurück") { go(-1) }
                }
                Button(primaryTitle) { step == .done ? finish() : go(1) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == .categories && selectedTemplates.isEmpty && subjects.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
        .onAppear(perform: preselect)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .categories:
            CategoryTemplateList(selected: $selectedTemplates, subjects: $subjects)
        case .permissions: PermissionsSettings()
        case .ai: AIStep()
        case .transcription: TranscriptionSettings()
        case .done: DoneStep(launchAtLogin: $launchAtLogin)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Los geht’s"
        case .done: return "\(AppInfo.name) öffnen"
        default: return "Weiter"
        }
    }

    private func go(_ delta: Int) {
        if step == .categories && delta > 0 { applyCategories() }
        step = Step(rawValue: step.rawValue + delta) ?? step
    }

    /// Erste Einrichtung: sinnvolle Vorauswahl. Erneuter Durchlauf: das, was schon da ist.
    private func preselect() {
        let existing = Set(library.categories.map(\.name))
        selectedTemplates = library.settings.onboardingCompleted
            ? Set(CategoryTemplate.all.filter { existing.contains($0.name) }.map(\.id))
            : CategoryTemplate.suggested
        // Erster Start ohne geladenes Whisper-Modell: die eingebaute Spracherkennung von macOS ist sofort einsatzbereit.
        if !library.settings.onboardingCompleted, TranscriberFactory.appleSpeechAvailable,
           WhisperModelManager.shared.installed.isEmpty {
            library.settings.transcriptionEngine = .apple
        }
    }

    /// Übernimmt die Auswahl: Nicht gewählte, unbenutzte Bereiche verschwinden, neue kommen dazu.
    private func applyCategories() {
        let chosen = Set(CategoryTemplate.all.filter { selectedTemplates.contains($0.id) }.map(\.name)).union(subjects)
        let used = Set(library.recordings.compactMap(\.categoryID))
        library.categories.removeAll { !chosen.contains($0.name) && !used.contains($0.id) }
        library.addCategories(templates: selectedTemplates, subjects: subjects)
        if library.category(library.settings.defaultCategoryID) == nil {
            library.settings.defaultCategoryID = library.categories.first?.id
        }
        if library.categories.isEmpty { library.categories = RecordingCategory.defaults }
    }

    private func finish() {
        library.settings.onboardingCompleted = true
        LoginItem.set(launchAtLogin)
        onFinish()
    }
}

/// Was die App macht – in vier Zeilen, ohne Kacheln.
private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("\(AppInfo.name) hört zu, schreibt mit und macht daraus Notizen mit Aufgaben – "
                     + "während du dich aufs Zuhören konzentrierst.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Nimmt Mikrofon und den Ton aus Zoom, Teams und Meet auf", systemImage: "mic")
                Label("Transkription und KI laufen auf deinem Mac – nichts geht in die Cloud", systemImage: "lock")
                Label("Notiz mit Kurzfassung, Themen und Aufgaben zum Abhaken", systemImage: "list.bullet.rectangle")
                Label("Auf Wunsch zusätzlich in Notion, Obsidian, Apple Notizen und mehr", systemImage: "square.and.arrow.up")
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// KI-Schritt: nur die eingebaute KI. Alles andere steckt in den Einstellungen.
private struct AIStep: View {
    var body: some View {
        Form {
            LocalModelSection()
            Section {
                Text("Andere KI-Anbieter – Apple Intelligence, Claude, ChatGPT, eigene Server – "
                     + "findest du später in den Einstellungen unter „KI“.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Letzter Schritt: Start-Verhalten und die wichtigsten Handgriffe.
private struct DoneStep: View {
    @Environment(LibraryStore.self) private var library
    @Binding var launchAtLogin: Bool

    var body: some View {
        @Bindable var library = library
        Form {
            Section("Start") {
                Toggle("\(AppInfo.name) beim Start des Macs automatisch öffnen", isOn: $launchAtLogin)
                Toggle("Fenster beim Start zeigen", isOn: $library.settings.openWindowAtLaunch)
            }
            Section("Gut zu wissen") {
                Label("In der Menüleiste startest du eine Aufnahme mit einem Klick.", systemImage: "menubar.arrow.up.rectangle")
                Label("Sobald ein Call beginnt, fragt \(AppInfo.name) von selbst nach.", systemImage: "phone")
                Label("⇧⌘R startet und stoppt, ⇧⌘P pausiert.", systemImage: "keyboard")
                Label("Bitte hole vor jeder Aufnahme das Einverständnis aller Beteiligten ein.", systemImage: "hand.raised")
            }
        }
        .formStyle(.grouped)
    }
}
