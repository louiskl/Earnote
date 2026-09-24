import AVFoundation
import EarnoteCore
import SwiftUI

/// Erster Start in fünf Schritten (docs/IPHONE.md, Abschnitt 4). Nur das Mikrofon ist Pflicht.
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
                microphone.tag(1)
                notifications.tag(2)
                noteWay.tag(3)
                done.tag(4)
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

    private var microphone: some View {
        Page(symbol: "mic.fill", effect: .bounce, title: "Mikrofon erlauben",
             text: "Damit Earnote aufnehmen kann. Die Aufnahme bleibt auf deinem iPhone.") {
            if microphoneAllowed {
                Label("Erlaubt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                    .transition(.scale.combined(with: .opacity))
                PrimaryButton("Weiter") { step = 2 }
            } else {
                PrimaryButton("Mikrofon erlauben") {
                    Task {
                        let allowed = await AVAudioApplication.requestRecordPermission()
                        withAnimation(.bouncy) { microphoneAllowed = allowed }
                        if allowed {
                            try? await Task.sleep(for: .milliseconds(600))
                            step = 2
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
                    step = 3
                }
            }
            Button("Später") { step = 3 }
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
                            .symbolEffect(.bounce, value: step == 3)
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
                    PrimaryButton("Weiter") { step = 4 }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            icon
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 128, height: 128)
                .glassEffect(.regular.tint(.accentColor.opacity(0.12)), in: .circle)
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
