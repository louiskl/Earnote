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
        NavigationStack {
            TabView(selection: $step) {
                welcome.tag(0)
                microphone.tag(1)
                notifications.tag(2)
                noteWay.tag(3)
                done.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.snappy, value: step)
        }
        .interactiveDismissDisabled()
    }

    // MARK: Schritte

    private var welcome: some View {
        Page(symbol: "waveform", title: "Earnote schreibt deine Vorlesungen mit",
             text: "Aufnehmen, iPhone weglegen – danach steht die Notiz da: Zusammenfassung, Aufgaben und Karteikarten zum Lernen.") {
            Label("Bleibt auf deinem iPhone", systemImage: "lock.shield")
            Label("Kostenlos, ohne Konto, ohne Abo", systemImage: "gift")
            Button("Los geht's") { step = 1 }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var microphone: some View {
        Page(symbol: "mic.fill", title: "Mikrofon erlauben",
             text: "Damit Earnote aufnehmen kann. Die Aufnahme bleibt auf deinem iPhone.") {
            if microphoneAllowed {
                Label("Erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Weiter") { step = 2 }.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("Mikrofon erlauben") {
                    Task {
                        microphoneAllowed = await AVAudioApplication.requestRecordPermission()
                        if microphoneAllowed { step = 2 }
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                if AVAudioApplication.shared.recordPermission == .denied {
                    Link("In den Einstellungen erlauben", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            }
        }
    }

    private var notifications: some View {
        Page(symbol: "bell.badge", title: "Bescheid sagen, wenn die Notiz fertig ist?",
             text: "Earnote schreibt die Notiz nach dem Stopp – eine Mitteilung sagt dir, wann sie da ist.") {
            Button("Mitteilungen erlauben") {
                Task {
                    _ = await Notifier.requestPermission()
                    step = 3
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Später") { step = 3 }
        }
    }

    private var noteWay: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wie soll die Notiz entstehen?").font(.title2.bold())
                    Text(DeviceCapabilities.supportsLocalModel
                         ? "Dein iPhone kann die Notiz selbst schreiben – ganz ohne Internet."
                         : "Für die Notiz auf dem iPhone selbst reicht der Speicher nicht. Mit einem kostenlosen Gemini-Schlüssel geht es trotzdem – dabei geht nur der Text an Google, nie das Audio.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            NoteWaySection()
            Section {
                Button("Weiter") { step = 4 }
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            // Vorschlag je nach Gerät (docs/IPHONE.md, Abschnitt 2), nur beim ersten Mal; der Mac-Weg kommt mit dem iCloud-Abgleich
            guard !suggestedWay else { return }
            suggestedWay = true
            if library.settings.ai.provider == .none || !NoteWaySection.providers.contains(library.settings.ai.provider) {
                library.settings.ai.provider = DeviceCapabilities.supportsLocalModel ? .localModel : .gemini
            }
        }
    }

    private var done: some View {
        Page(symbol: "checkmark.seal", title: "Fertig",
             text: "Bitte hole vor jeder Aufnahme das Einverständnis aller Beteiligten ein – in Vorlesungen die Erlaubnis der Lehrperson.") {
            Button("Erste Aufnahme") {
                library.settings.onboardingCompleted = true
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!microphoneAllowed)
            if !microphoneAllowed {
                Text("Ohne Mikrofon kann Earnote nicht aufnehmen.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Eine Seite: Symbol, Überschrift, Text, darunter die Knöpfe
private struct Page<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 14) { actions }
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 28)
    }
}
