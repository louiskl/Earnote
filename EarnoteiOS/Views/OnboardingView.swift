import AVFoundation
import EarnoteCore
import SwiftUI

/// Erster Start in sechs Schritten (docs/IPHONE.md, Abschnitt 4). Nur das Mikrofon ist Pflicht.
/// Jede Seite hat denselben Aufbau: oben Zurück und Fortschritt, in der Mitte die Frage, unten der Hauptknopf –
/// immer an derselben Stelle, darunter höchstens ein leiser zweiter Knopf.
struct OnboardingView: View {
    @Environment(LibraryStore.self) private var library
    @State private var step = 0
    @State private var usage: Usage?
    @State private var microphoneAllowed = AVAudioApplication.shared.recordPermission == .granted
    @State private var suggestedWay = false
    private let lastStep = 5

    var body: some View {
        ZStack {
            // Der besondere Moment: nur auf der ersten Seite kräftig, danach ein Hauch
            BrandGlow(intensity: step == 0 ? 1 : 0.35)
            VStack(spacing: 0) {
                topBar
                page
                    .id(step)
                    .transition(.blurReplace)
                    .frame(maxHeight: .infinity)
                actions
            }
            // iPad: eine lesbare Spalte statt Knöpfen über die ganze Breite
            .frame(maxWidth: 560)
        }
        .animation(.smooth, value: step)
        .interactiveDismissDisabled()
    }

    // MARK: Rahmen

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                step -= 1
            } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Zurück")
            ProgressView(value: Double(step), total: Double(lastStep))
                .accessibilityLabel("Schritt \(step + 1) von \(lastStep + 1)")
        }
        .padding(.horizontal, 28)
        .frame(height: 52)
        // Die erste Seite ist die Begrüßung – ohne Zurück und Fortschritt, der Platz bleibt, damit nichts springt
        .opacity(step == 0 ? 0 : 1)
        .disabled(step == 0)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0: welcome
        case 1: usagePage
        case 2: microphone
        case 3: notifications
        case 4: noteWay
        default: done
        }
    }

    /// Hauptknopf und zweiter Knopf; der zweite Platz bleibt auch leer stehen, damit der Hauptknopf nie wandert
    @ViewBuilder private var actions: some View {
        VStack(spacing: 6) {
            switch step {
            case 0:
                PrimaryButton("Los geht's") { step = 1 }
                SecondarySlot()
            case 1:
                PrimaryButton("Weiter") { step = 2 }
                    .disabled(usage == nil)
                SecondarySlot {
                    Button("Überspringen") {
                        usage = nil
                        step = 2
                    }
                }
            case 2:
                if microphoneAllowed {
                    PrimaryButton("Weiter") { step = 3 }
                } else {
                    PrimaryButton("Mikrofon erlauben") { requestMicrophone() }
                }
                SecondarySlot {
                    if !microphoneAllowed && AVAudioApplication.shared.recordPermission == .denied {
                        Link("In den Einstellungen erlauben", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            case 3:
                PrimaryButton("Mitteilungen erlauben") {
                    Task {
                        _ = await Notifier.requestPermission()
                        step = 4
                    }
                }
                SecondarySlot {
                    Button("Später") { step = 4 }
                }
            case 4:
                PrimaryButton("Weiter") { step = 5 }
                SecondarySlot()
            default:
                PrimaryButton("Loslegen") { finish() }
                    .disabled(!microphoneAllowed)
                SecondarySlot {
                    if !microphoneAllowed {
                        Text("Ohne Mikrofon kann Earnote nicht aufnehmen.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    // MARK: Schritte

    private var welcome: some View {
        Page(symbol: "waveform", effect: .variableColor, title: "Earnote schreibt für dich mit",
             text: "Vorlesung, Unterricht oder Meeting: aufnehmen, iPhone weglegen – danach steht die Notiz da.") {
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "text.page", text: "Zusammenfassung und Aufgaben")
                Feature(symbol: "rectangle.on.rectangle.angled", text: "Karteikarten zum Lernen")
                Feature(symbol: "lock.shield", text: "Bleibt auf deinem iPhone")
                Feature(symbol: "gift", text: "Kostenlos, ohne Konto, ohne Abo")
            }
        }
    }

    /// Einstiegsfrage (ROADMAP Phase 7): Jede Gruppe bekommt ihre Bereiche und sieht nur, was zu ihr passt.
    /// Angewendet wird die Antwort erst bei „Loslegen“ – so kann man zurückgehen und umentscheiden.
    private var usagePage: some View {
        Page(symbol: "hand.wave.fill", effect: .wiggle, title: "Wofür nutzt du Earnote?",
             text: "Danach richtet Earnote die passenden Bereiche ein. Ändern kannst du es jederzeit.") {
            ForEach(Usage.allCases) { choice in
                UsageButton(usage: choice, isSelected: usage == choice) { usage = choice }
            }
        }
        .sensoryFeedback(.selection, trigger: usage)
    }

    private var microphone: some View {
        Page(symbol: "mic.fill", effect: .bounce, title: "Mikrofon erlauben",
             text: "Damit Earnote aufnehmen kann. Die Aufnahme bleibt auf deinem iPhone.") {
            if microphoneAllowed {
                Label("Erlaubt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: microphoneAllowed)
    }

    private func requestMicrophone() {
        Task {
            let allowed = await AVAudioApplication.requestRecordPermission()
            withAnimation(.bouncy) { microphoneAllowed = allowed }
            if allowed {
                try? await Task.sleep(for: .milliseconds(600))
                step = 3
            }
        }
    }

    private var notifications: some View {
        Page(symbol: "bell.badge.fill", effect: .wiggle, title: "Bescheid sagen, wenn die Notiz fertig ist?",
             text: "Earnote schreibt die Notiz nach dem Stopp – eine Mitteilung sagt dir, wann sie da ist.") {
            SampleNotification()
        }
    }

    private var noteWay: some View {
        // Eigener Stapel: „Weitere Anbieter“ und „Welcher Weg passt zu mir?“ öffnen sich als Seiten
        NavigationStack {
            Form {
                Section {
                    // Kleiner Kopf als auf den anderen Seiten: Hier zählt die Auswahl darunter, sie soll ohne Scrollen sichtbar sein
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "text.page")
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
            }
            .scrollContentBackground(.hidden)
            .toolbarVisibility(.hidden, for: .navigationBar)
            // Der Schimmer der anderen Seiten soll durchscheinen – sonst legt der Stapel eine weiße Fläche darüber
            .containerBackground(.clear, for: .navigation)
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

    private var done: some View {
        Page(symbol: "checkmark.seal.fill", effect: .bounce, title: "Alles bereit",
             text: "Eine Bitte: Frag vor jeder Aufnahme alle, ob du aufnehmen darfst – in Vorlesungen die Lehrperson.") {
            // Die Antwort von vorhin sichtbar machen: Das richtet Earnote daraus ein
            if let usage {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(CategoryTemplate.suggested(for: usage), id: \.self) { id in
                            if let template = CategoryTemplate.all.first(where: { $0.id == id }) {
                                HStack(spacing: 10) {
                                    Text(template.emoji)
                                    Text(template.name)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Deine Bereiche")
                }
            }
        }
    }

    private func finish() {
        if let usage { apply(usage) }
        library.settings.onboardingCompleted = true
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
}

/// Eine Seite: Kopf und darunter der Inhalt, zusammen mittig. Passt es nicht (größte Schrift), wird die Seite scrollbar.
private struct Page<Content: View>: View {
    let symbol: String
    let effect: PageHeader.Effect
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            stack.frame(maxHeight: .infinity)
            ScrollView { stack.padding(.vertical, 24) }
        }
    }

    private var stack: some View {
        VStack(spacing: 28) {
            PageHeader(symbol: symbol, effect: effect, title: title, text: text)
            VStack(spacing: 14) { content }
        }
        .padding(.horizontal, 28)
    }
}

/// Bewegtes Symbol, Überschrift, Text – auf jeder Seite gleich (außer „Wie soll die Notiz entstehen?“)
private struct PageHeader: View {
    enum Effect { case variableColor, bounce, wiggle }

    let symbol: String
    let effect: Effect
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @State private var appeared = false
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            icon
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 112, height: 112)
                .glassEffect(.regular.tint(skin.tint.opacity(0.12)), in: .circle)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
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

/// Platz für den zweiten Knopf unter dem Hauptknopf – immer gleich hoch, auch wenn er leer bleibt
private struct SecondarySlot<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Eine leere Fläche hält die Höhe – ein leerer Inhalt allein hätte keine
        ZStack {
            Color.clear.frame(height: 44)
            content.font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity)
    }
}

extension SecondarySlot where Content == EmptyView {
    init() { content = EmptyView() }
}

/// So sieht die Mitteilung aus, um die gleich gefragt wird – erst der Nutzen, dann die Frage
private struct SampleNotification: View {
    var body: some View {
        HStack(spacing: 12) {
            AppIconChoice.current.preview
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(.rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: "Earnote").font(.subheadline.bold())
                    Spacer()
                    Text("jetzt").font(.caption).foregroundStyle(.secondary)
                }
                Text("Deine Notiz ist fertig").font(.subheadline)
                Text("Eigenwerte und Eigenvektoren").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Beispiel: Mitteilung „Deine Notiz ist fertig“")
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

/// Eine Antwort auf „Wofür nutzt du Earnote?“ – Symbol, Titel, was dazugehört; die gewählte trägt einen Haken
private struct UsageButton: View {
    let usage: Usage
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.skin) private var skin

    private var symbol: String {
        switch usage {
        case .university: "graduationcap"
        case .school: "backpack"
        case .work: "briefcase"
        }
    }

    private var detail: LocalizedStringKey {
        switch usage {
        case .university: "Vorlesungen und Seminare"
        case .school: "Unterricht, Oberstufe, Berufsschule"
        case .work: "Meetings, Calls, Gespräche"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(skin.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(usage.label).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(skin.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        // Glas färbt die Beschriftung sonst ganz in der Akzentfarbe – Titel sollen schwarz lesbar bleiben
        .tint(.primary)
        .overlay {
            Capsule().strokeBorder(skin.tint, lineWidth: 2).opacity(isSelected ? 1 : 0)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
