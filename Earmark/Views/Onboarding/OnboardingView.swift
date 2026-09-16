import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    var onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, categories, permissions, ai, transcription, destinations, done

        var title: String {
            switch self {
            case .welcome: return "Willkommen bei Earmark"
            case .categories: return "Wofür nutzt du Earmark?"
            case .permissions: return "Kurz ein paar Freigaben"
            case .ai: return "Wer schreibt deine Notizen?"
            case .transcription: return "Spracherkennung"
            case .destinations: return "Wohin mit den Notizen?"
            case .done: return "Alles bereit ✨"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: return "Deine Meetings, Calls und Vorlesungen – automatisch als gute Notizen. Privat auf deinem Mac."
            case .categories: return "Wähle aus, was zu dir passt. Daraus werden deine Bereiche – du kannst sie jederzeit ändern."
            case .permissions: return "Damit Earmark aufnehmen und dich benachrichtigen kann. Alles bleibt auf deinem Mac."
            case .ai: return "Earmark bringt eine eigene KI mit, die komplett auf deinem Mac läuft. Einmal laden – danach privat, kostenlos und offline."
            case .transcription: return "Die Spracherkennung läuft immer lokal. Die Voreinstellung passt für die meisten."
            case .destinations: return "Earmark legt fertige Notizen automatisch dort ab, wo du arbeitest. Mehrfachauswahl möglich."
            case .done: return "Earmark wartet ab jetzt oben in der Menüleiste auf dich."
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var direction: Edge = .trailing
    @State private var selectedTemplates: Set<String> = []
    @State private var subjects: [String] = []
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.self) { s in
                        Capsule()
                            .fill(s.rawValue <= step.rawValue ? Color.white : Color.white.opacity(0.35))
                            .frame(width: s == step ? 28 : 8, height: 8)
                    }
                    Spacer()
                    if step != .welcome && step != .done {
                        Text("Schritt \(step.rawValue) von \(Step.allCases.count - 2)")
                            .font(Theme.Font.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    // Wer den Assistenten später erneut öffnet, muss nicht alles durchklicken
                    if app.settings.onboardingCompleted {
                        Button { onFinish() } label: { Image(systemName: "xmark") }
                            .buttonStyle(RoundIconButtonStyle(size: 26, fill: .white.opacity(0.35)))
                            .help("Schließen")
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)

                VStack(alignment: .leading, spacing: Theme.Space.xs + 2) {
                    Text(step.title)
                        .font(.system(size: 26, weight: .bold))
                    Text(step.subtitle)
                        .font(Theme.Font.body)
                        .foregroundStyle(.primary.opacity(0.7))
                        .fittingHeight()
                }
                .id(step)
                .transition(.opacity)
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.top, Theme.Space.xl + 4)
            .padding(.bottom, Theme.Space.l)

            ScrollView {
                content
                    .padding(Theme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity), removal: .opacity))
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardBackground)
                    .shadow(color: .black.opacity(0.1), radius: 18, y: 6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, Theme.Space.l)

            HStack {
                if step != .welcome && step != .done {
                    Button("Zurück") { go(-1) }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                if [.ai, .transcription, .destinations].contains(step) {
                    Button("Später") { go(1) }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .padding(.trailing, Theme.Space.s)
                }
                Button(primaryTitle) {
                    if step == .done { finish() } else { go(1) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(step == .categories && selectedTemplates.isEmpty && subjects.isEmpty)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
        }
        .frame(width: 780, height: 680)
        .background(Backdrop(tint: Theme.brand))
        .onAppear(perform: preselect)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Los geht’s"
        case .done: return "Earmark öffnen"
        case .categories:
            let count = selectedTemplates.count + subjects.count - (selectedTemplates.contains("lecture") && !subjects.isEmpty ? 1 : 0)
            return count > 0 ? "Weiter mit \(count) \(count == 1 ? "Bereich" : "Bereichen")" : "Weiter"
        default: return "Weiter"
        }
    }

    private func go(_ delta: Int) {
        if step == .categories && delta > 0 { applyCategories() }
        direction = delta > 0 ? .trailing : .leading
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            step = Step(rawValue: step.rawValue + delta) ?? step
        }
    }

    /// Erste Einrichtung: sinnvolle Vorauswahl. Erneuter Durchlauf: das, was schon da ist.
    private func preselect() {
        let existing = Set(app.categories.map(\.name))
        if app.settings.onboardingCompleted {
            selectedTemplates = Set(CategoryTemplate.all.filter { existing.contains($0.name) }.map(\.id))
        } else {
            selectedTemplates = CategoryTemplate.suggested
        }
    }

    /// Übernimmt die Auswahl: Nicht gewählte, unbenutzte Standardbereiche verschwinden, neue kommen dazu.
    private func applyCategories() {
        let chosenNames = Set(CategoryTemplate.all.filter { selectedTemplates.contains($0.id) }.map(\.name)).union(subjects)
        let used = Set(app.recordings.compactMap(\.categoryID))
        app.categories.removeAll { !chosenNames.contains($0.name) && !used.contains($0.id) }
        app.addCategories(templates: selectedTemplates, subjects: subjects)
        if app.category(app.settings.defaultCategoryID) == nil {
            app.settings.defaultCategoryID = app.categories.first?.id
        }
        if app.categories.isEmpty { app.categories = RecordingCategory.defaults }
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
        case .categories: CategoryTemplatePicker(selected: $selectedTemplates, subjects: $subjects)
        case .permissions: PermissionsPanel()
        case .ai: AIPanel()
        case .transcription: TranscriptionPanel()
        case .destinations: DestinationsPanel()
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(spacing: Theme.Space.l) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nie wieder mitschreiben.").font(.system(size: 22, weight: .bold))
                    Text("Earmark hört zu, schreibt mit und macht daraus Notizen mit Aufgaben – während du dich aufs Gespräch konzentrierst.")
                        .font(Theme.Font.body).foregroundStyle(.secondary).fittingHeight()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())], spacing: Theme.Space.m) {
                feature("🎙️", "Nimmt alles auf", "Mikrofon und Ton aus Zoom, Teams, Meet – ohne Zusatzsoftware.", color: Theme.accent)
                feature("🔒", "Bleibt privat", "Transkription und KI laufen auf deinem Mac. Nichts geht in die Cloud.", color: .green)
                feature("✍️", "Schreibt echte Notizen", "Kurzfassung, Themen, Entscheidungen und Aufgaben zum Abhaken.", color: Theme.brandSecondary)
                feature("📤", "Legt sie ab", "Notion, Obsidian, Apple Notizen, Markdown, Bear oder Craft.", color: .blue)
            }
        }
    }

    private func feature(_ emoji: String, _ title: String, _ detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            EmojiBadge(emoji: emoji, color: color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body.weight(.semibold))
                Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary).fittingHeight()
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.06)))
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                startOption(isOn: $launchAtLogin, emoji: "🚀", title: "Earmark beim Start des Macs automatisch öffnen",
                            detail: "Empfohlen – so verpasst du keinen Call, den Earmark erkennen soll.")
                startOption(isOn: $app.settings.openWindowAtLaunch, emoji: "🪟", title: "Fenster beim Start zeigen",
                            detail: "Aus: Earmark startet unauffällig nur in der Menüleiste.")
            }

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Gut zu wissen").font(Theme.Font.body.weight(.semibold))
                tip("☝️", "Oben in der Menüleiste startest du eine Aufnahme mit einem Klick.")
                tip("📞", "Sobald ein Call beginnt, fragt Earmark automatisch nach.")
                tip("⌨️", "⇧⌘R startet oder stoppt eine Aufnahme, ⇧⌘P pausiert.")
                tip("🤝", "Bitte hole vor jeder Aufnahme das Einverständnis aller Beteiligten ein.")
            }
            .padding(Theme.Space.l)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.035)))
        }
    }

    private func startOption(isOn: Binding<Bool>, emoji: String, title: String, detail: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: Theme.Space.m) {
                Text(emoji).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn.wrappedValue ? Theme.accent : Color.secondary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Theme.Space.l)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn.wrappedValue ? Theme.accent.opacity(0.07) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn.wrappedValue ? Theme.accent.opacity(0.4) : Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tip(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Text(emoji)
            Text(text).font(Theme.Font.small).fittingHeight()
        }
    }
}
