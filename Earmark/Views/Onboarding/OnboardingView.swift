import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    var onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, permissions, transcription, ai, destinations, categories, done

        var title: String {
            switch self {
            case .welcome: return "Willkommen bei Earmark"
            case .permissions: return "Berechtigungen"
            case .transcription: return "Transkription"
            case .ai: return "KI für die Zusammenfassung"
            case .destinations: return "Wohin mit deinen Notizen?"
            case .categories: return "Deine Kategorien"
            case .done: return "Alles bereit!"
            }
        }
        var subtitle: String {
            switch self {
            case .welcome: return "Deine kostenlose, private Alternative zu KI-Meeting-Notizen."
            case .permissions: return "Earmark braucht ein paar Freigaben, um aufnehmen zu können. Du kannst sie jederzeit ändern."
            case .transcription: return "Die Spracherkennung läuft komplett lokal auf deinem Mac – nichts verlässt dein Gerät."
            case .ai: return "Wähle, wer aus dem Transkript deine Notizen schreibt. Lokale Modelle sind kostenlos und privat."
            case .destinations: return "Earmark legt die fertigen Notizen automatisch dort ab, wo du arbeitest. Mehrfachauswahl möglich."
            case .categories: return "Mit Kategorien bekommt jede Art von Termin die passende Zusammenfassung."
            case .done: return "Earmark wartet ab jetzt oben in der Menüleiste."
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Theme.accent : Color.primary.opacity(0.12))
                        .frame(width: s == step ? 26 : 8, height: 8)
                }
            }
            .animation(.spring(duration: 0.35), value: step)
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.system(size: 26, weight: .bold))
                Text(step.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36).padding(.top, 22).padding(.bottom, 14)

            ScrollView {
                content
                    .padding(.horizontal, 36)
                    .padding(.bottom, 20)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                    .id(step)
            }

            Divider()
            HStack {
                if step != .welcome && step != .done {
                    Button("Zurück") { go(-1) }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                if step == .ai || step == .destinations {
                    Button("Überspringen") { go(1) }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                Button(step == .done ? "Los geht’s" : step == .welcome ? "Einrichten" : "Weiter") {
                    if step == .done { finish() } else { go(1) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36).padding(.vertical, 16)
        }
        .frame(width: 720, height: 640)
    }

    private func go(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            step = Step(rawValue: step.rawValue + delta) ?? step
        }
    }

    private func finish() {
        app.settings.onboardingCompleted = true
        LoginItem.set(launchAtLogin)
        onFinish()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: PermissionsPanel()
        case .transcription: TranscriptionPanel()
        case .ai: AIPanel()
        case .destinations: DestinationsPanel()
        case .categories: CategoriesPanel()
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 110, height: 110)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 14) {
                feature("waveform", "Nimmt Meetings, Calls & Vorlesungen auf", "Mikrofon und Systemton – ganz ohne Zusatzsoftware.")
                feature("phone.bubble.fill", "Erkennt Calls automatisch", "Zoom, Teams, Meet, Webex, FaceTime … Earmark fragt, ob du aufnehmen willst.")
                feature("lock.shield.fill", "Transkribiert lokal", "Deine Audiodaten bleiben auf deinem Mac.")
                feature("sparkles", "Schreibt deine Notizen", "Themen, Entscheidungen, Aufgaben – mit der KI deiner Wahl.")
                feature("square.and.arrow.up.fill", "Legt sie dort ab, wo du arbeitest", "Notion, Obsidian, Apple Notizen, Markdown, Bear, Craft.")
            }
            .card(padding: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 70)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 12) {
                tip("menubar.arrow.up.rectangle", "Du findest Earmark oben in der Menüleiste – ein Klick startet die Aufnahme.")
                tip("phone.fill", "Sobald ein Call beginnt, fragt Earmark automatisch nach.")
                tip("hand.raised.fill", "Bitte hole vor jeder Aufnahme das Einverständnis aller Beteiligten ein.")
                tip("arrow.down.doc.fill", "Vorhandene Audiodateien kannst du einfach ins Fenster ziehen.")
            }
            .card(padding: 20)
            Toggle("Earmark beim Anmelden automatisch starten", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
        }
        .frame(maxWidth: .infinity)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
            Text(text).font(.system(size: 13))
        }
    }
}
