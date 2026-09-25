import AVFoundation
import EarnoteCore
import SwiftUI

/// Erster Start in sechs Schritten (docs/IPHONE.md, Abschnitt 4). Nur das Mikrofon ist Pflicht.
struct OnboardingView: View {
    @Environment(LibraryStore.self) private var library
    @State private var step = 0
    @State private var microphoneAllowed = AVAudioApplication.shared.recordPermission == .granted
    @State private var suggestedWay = false

    var body: some View {
        ZStack {
            // Der besondere Moment: nur auf der ersten Seite kräftig, danach ein Hauch
            BrandGlow(intensity: step == 0 ? 1 : 0.35)
            TabView(selection: $step) {
                welcome.tag(0)
                usage.tag(1)
                microphone.tag(2)
                notifications.tag(3)
                noteWay.tag(4)
                done.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        }
        .animation(.smooth, value: step)
        .interactiveDismissDisabled()
    }

    // MARK: Schritte

    private var welcome: some View {
        Page(symbol: "waveform", effect: .variableColor, title: "Earnote schreibt deine Vorlesungen mit",
             text: "Aufnehmen, iPhone weglegen – danach steht die Notiz da.") {
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "text.page", text: "Zusammenfassung und Aufgaben")
                Feature(symbol: "rectangle.on.rectangle.angled", text: "Karteikarten zum Lernen")
                Feature(symbol: "lock.shield", text: "Bleibt auf deinem iPhone")
                Feature(symbol: "gift", text: "Kostenlos, ohne Konto, ohne Abo")
            }
            .padding(.bottom, 8)
            PrimaryButton("Los geht's") { step = 1 }
        }
    }

    /// Einstiegsfrage (ROADMAP Phase 7): Jede Gruppe bekommt ihre Bereiche und sieht nur, was zu ihr passt
    private var usage: some View {
        Page(symbol: "person.crop.circle.badge.questionmark", effect: .bounce, title: "Wofür nutzt du Earnote?",
             text: "Danach richtet Earnote die passenden Bereiche ein. Ändern kannst du es jederzeit.") {
            ForEach(Usage.allCases) { choice in
                UsageButton(usage: choice) {
                    apply(choice)
                    step = 2
                }
            }
            Button("Überspringen") { step = 2 }
                .font(.subheadline)
                .padding(.top, 4)
        }
    }

    private var microphone: some View {
        Page(symbol: "mic.fill", effect: .bounce, title: "Mikrofon erlauben",
             text: "Damit Earnote aufnehmen kann. Die Aufnahme bleibt auf deinem iPhone.") {
            if microphoneAllowed {
                Label("Erlaubt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                    .transition(.scale.combined(with: .opacity))
                PrimaryButton("Weiter") { step = 3 }
            } else {
                PrimaryButton("Mikrofon erlauben") {
                    Task {
                        let allowed = await AVAudioApplication.requestRecordPermission()
                        withAnimation(.bouncy) { microphoneAllowed = allowed }
                        if allowed {
                            try? await Task.sleep(for: .milliseconds(600))
                            step = 3
                        }
                    }
                }
                if AVAudioApplication.shared.recordPermission == .denied {
                    Link("In den Einstellungen erlauben", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            }
        }
        .sensoryFeedback(.success, trigger: microphoneAllowed)
    }

    private var notifications: some View {
        Page(symbol: "bell.badge.fill", effect: .wiggle, title: "Bescheid sagen, wenn die Notiz fertig ist?",
             text: "Earnote schreibt die Notiz nach dem Stopp – eine Mitteilung sagt dir, wann sie da ist.") {
            PrimaryButton("Mitteilungen erlauben") {
                Task {
                    _ = await Notifier.requestPermission()
                    step = 4
                }
            }
            Button("Später") { step = 4 }
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }

    private var noteWay: some View {
        // Eigener Stapel: „Weitere Anbieter“ und „Welcher Weg passt zu mir?“ öffnen sich als Seiten
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                            .symbolEffect(.bounce, value: step == 4)
                        Text("Wie soll die Notiz entstehen?").font(.title2.bold())
                        Text(NoteWay.onDeviceProvider != nil
                             ? "Dein iPhone kann die Notiz selbst schreiben – ganz ohne Internet."
                             : "Hast du Earnote auf dem Mac, schreibt er die Notiz. Sonst geht es kostenlos mit deinem Google-Konto – dabei geht nur der Text an Google, nie das Audio.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                NoteWayPicker()
                Section {
                    PrimaryButton("Weiter") { step = 5 }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .onAppear {
            // Vorschlag je nach Gerät (docs/IPHONE.md, Abschnitt 2), nur beim ersten Mal. Der Mac-Weg greift, sobald
            // nach dem Einschalten von iCloud ein Mac gefunden ist; bis dahin gilt dieser Weg.
            guard !suggestedWay else { return }
            suggestedWay = true
            if !NoteWay.worksHere(library.settings.ai.provider) {
                library.settings.ai.provider = NoteWay.suggestedProvider
            }
        }
    }

    /// Bereiche und Voreinstellungen zur Antwort. Die Standardbereiche werden nur ersetzt, solange nichts aufgenommen
    /// und nichts abgeglichen ist – sonst verschwänden Bereiche auch auf dem Mac. Andernfalls kommen die neuen dazu.
    private func apply(_ usage: Usage) {
        library.settings.usage = usage
        if usage == .school { library.settings.ai.simpleNotes = true }
        if usage == .work { library.settings.detectSpeakers = true }
        let templates = CategoryTemplate.suggested(for: usage)
        let untouched = Set(library.categories.map(\.id)) == Set(RecordingCategory.defaults.map(\.id))
        if untouched && library.recordings.isEmpty && !library.settings.syncWithCloud {
            let categories = templates.compactMap { id in CategoryTemplate.all.first { $0.id == id }?.makeCategory() }
            library.categories = categories
            library.settings.defaultCategoryID = categories.first?.id
        } else {
            _ = library.addCategories(templates: Set(templates), subjects: [])
        }
    }

    private var done: some View {
        Page(symbol: "checkmark.seal.fill", effect: .bounce, title: "Fertig",
             text: "Bitte hole vor jeder Aufnahme das Einverständnis aller Beteiligten ein – in Vorlesungen die Erlaubnis der Lehrperson.") {
            PrimaryButton("Erste Aufnahme") {
                library.settings.onboardingCompleted = true
            }
            .disabled(!microphoneAllowed)
            if !microphoneAllowed {
                Text("Ohne Mikrofon kann Earnote nicht aufnehmen.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Eine Seite: bewegtes Symbol, Überschrift, Text, darunter der Inhalt
private struct Page<Content: View>: View {
    enum Effect { case variableColor, bounce, wiggle }

    let symbol: String
    let effect: Effect
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder let content: Content
    @State private var appeared = false
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            icon
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 128, height: 128)
                .glassEffect(.regular.tint(skin.tint.opacity(0.12)), in: .circle)
                .accessibilityHidden(true)
                .padding(.bottom, 8)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 14) { content }
            Spacer().frame(height: 56)
        }
        .padding(.horizontal, 28)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    @ViewBuilder private var icon: some View {
        let image = Image(systemName: symbol)
        switch effect {
        case .variableColor:
            image.symbolEffect(.variableColor.iterative.reversing, isActive: !reduceMotion)
        case .bounce:
            image.symbolEffect(.bounce, value: appeared)
        case .wiggle:
            image.symbolEffect(.wiggle, value: appeared)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text).font(.body.weight(.medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 28)
        }
    }
}

/// Eine Antwort auf „Wofür nutzt du Earnote?“ – Symbol, Titel, was dazugehört
private struct UsageButton: View {
    let usage: Usage
    let action: () -> Void

    private var symbol: String {
        switch usage {
        case .university: "graduationcap"
        case .school: "backpack"
        case .work: "briefcase"
        }
    }

    private var detail: LocalizedStringKey {
        switch usage {
        case .university: "Vorlesungen, Seminare, Lerngruppen"
        case .school: "Unterricht, Oberstufe, Berufsschule"
        case .work: "Meetings, Calls, Gespräche"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(usage.label).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

/// Hauptknopf einer Seite: volle Breite, Liquid Glass in Earnote-Rot
struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
    }
}
