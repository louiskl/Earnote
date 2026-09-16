import SwiftUI

struct RecordingDetailView: View {
    @EnvironmentObject var app: AppState
    let recordingID: UUID
    /// Schmales Fenster: Zurück-Knopf zur Liste anzeigen
    var showsBack = false

    enum Tab: Hashable { case summary, transcript, export }
    @State private var tab: Tab = .summary
    @State private var title = ""
    @State private var summary: Summary?
    @State private var transcript: Transcript?
    @State private var copied = false

    private var recording: Recording? { app.recording(recordingID) }

    var body: some View {
        if let rec = recording {
            let category = app.category(rec.categoryID)
            let color = category?.color ?? Theme.brand
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(rec, category: category, color: color)
                    Group {
                        switch tab {
                        case .summary: summaryTab(rec, color: color)
                        case .transcript: transcriptTab(color: color)
                        case .export: exportTab(rec)
                        }
                    }
                    .padding(.horizontal, Theme.Space.xl + 4)
                    .padding(.top, Theme.Space.xl)
                    .padding(.bottom, Theme.Space.xxl)
                    .transition(.opacity)
                }
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .animation(.easeOut(duration: 0.2), value: tab)
            .onAppear { reload(rec) }
            .onChange(of: rec.status) { _, _ in reload(rec) }
        }
    }

    private func reload(_ rec: Recording) {
        title = rec.displayTitle
        summary = app.summary(recordingID)
        transcript = app.transcript(recordingID)
    }

    private func copy() {
        var text = ""
        if let s = summary { text += "# \(s.title)\n\n\(s.markdown)\n\n" }
        if tab == .transcript || summary == nil, let t = transcript { text += t.formatted(includeSpeakers: app.settings.speakerLabels) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
    }

    // MARK: Kopfbereich

    private func header(_ rec: Recording, category: RecordingCategory?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                if showsBack {
                    Button { app.selection = nil } label: {
                        Label("Alle", systemImage: "chevron.left").font(Theme.Font.small.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(app.categories) { c in
                        Button("\(c.displayEmoji)  \(c.name)") { app.setCategory(recordingID, c.id) }
                    }
                } label: {
                    Text(category.map { "\($0.displayEmoji)  \($0.name)" } ?? "Bereich wählen")
                        .font(Theme.Font.small.weight(.semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, Theme.Space.s + 2)
                .padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.12)))
                .help("Bereich ändern")

                Button { copy() } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(RoundIconButtonStyle(size: 30))
                    .disabled(summary == nil && transcript == nil)
                    .help("Notizen kopieren")
                Menu { RecordingActions(recordingID: recordingID) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Weitere Aktionen")
            }

            HStack(alignment: .top, spacing: Theme.Space.l) {
                EmojiBadge(emoji: category?.displayEmoji ?? "🎙️", color: color, size: 54)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    TextField("Titel", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(.title, design: .default, weight: .bold))
                        .lineLimit(1...3)
                        .onSubmit { app.rename(recordingID, to: title) }
                    HStack(spacing: Theme.Space.xs + 2) {
                        MetaChip(icon: "calendar", text: rec.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        MetaChip(icon: "clock", text: TimeFormat.duration(rec.duration))
                        if let s = rec.sourceApp { MetaChip(icon: "video", text: s) }
                        if rec.hasSystemAudio { MetaChip(icon: "person.2", text: "Mit Gesprächspartnern") }
                    }
                }
            }

            if rec.status != .done { statusBanner(rec, color: color) }

            PillTabs(items: [(Tab.summary, "Notizen"), (.transcript, "Transkript"), (.export, "Export")], selection: $tab)
        }
        .padding(.horizontal, Theme.Space.xl + 4)
        .padding(.top, Theme.Space.l)
    }

    @ViewBuilder
    private func statusBanner(_ rec: Recording, color: Color) -> some View {
        if rec.status == .failed {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Text("😕").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Da hat etwas nicht geklappt").font(Theme.Font.small.weight(.semibold))
                    Text(rec.errorMessage ?? "Unbekannter Fehler")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fittingHeight()
                }
                Spacer(minLength: Theme.Space.m)
                Button("Erneut versuchen") { app.enqueue(recordingID) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.09)))
        } else if rec.status.isBusy {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    StatusPill(text: busyText(rec.status), color: color, animated: true)
                    Spacer()
                    Text("\(Int(rec.progress * 100)) %")
                        .font(Theme.Font.number(12, weight: .medium))
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                }
                ProgressLine(progress: rec.progress, color: color)
            }
            .padding(Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.08)))
        }
    }

    private func busyText(_ status: RecordingStatus) -> String {
        switch status {
        case .queued: return "Wartet auf die Verarbeitung"
        case .transcribing: return "\(AppInfo.name) hört sich die Aufnahme an …"
        case .summarizing: return "Notizen werden geschrieben …"
        case .exporting: return "Wird abgelegt …"
        default: return status.label
        }
    }

    // MARK: Notizen

    @ViewBuilder
    private func summaryTab(_ rec: Recording, color: Color) -> some View {
        if let s = summary {
            let doc = NoteDocument(markdown: s.markdown)
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if !doc.intro.isEmpty {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text("KURZFASSUNG").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(color)
                            MarkdownView(markdown: doc.intro)
                                .font(.system(.body).leading(.loose))
                        }
                    }
                    .padding(Theme.Space.l)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [color.opacity(0.12), color.opacity(0.05)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.15), lineWidth: 0.5))
                }

                ForEach(doc.sections) { section in
                    sectionView(section, in: doc, color: color)
                }

                Text("Erstellt mit \(s.provider)")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary)
            }
        } else if rec.status.isBusy {
            placeholder("✍️", "Die Notizen entstehen gerade", "Du bekommst eine Mitteilung, sobald sie fertig sind.")
        } else if app.settings.ai.provider == AIProviderKind.none {
            placeholder("💤", "Zusammenfassungen sind aus", "Wähle in den Einstellungen unter „KI“, wer deine Notizen schreiben soll.")
        } else {
            placeholder("📝", "Noch keine Notizen", "Über „…“ oben rechts kannst du sie neu erstellen lassen.")
        }
    }

    @ViewBuilder
    private func sectionView(_ section: NoteDocument.Section, in doc: NoteDocument, color: Color) -> some View {
        let kind = section.title.lowercased()
        let update: (String) -> Void = { body in
            app.updateSummaryText(recordingID, markdown: doc.replacing(section.id, with: body))
            summary = app.summary(recordingID)
        }
        if kind.hasPrefix("aufgaben") {
            let open = section.body.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") }.count
            highlightCard(icon: "checkmark.circle.fill", title: section.title, badge: open > 0 ? "\(open) offen" : "Erledigt 🎉",
                          color: color) {
                MarkdownView(markdown: section.body, onToggleTask: update)
            }
        } else if kind.hasPrefix("entscheidungen") {
            highlightCard(icon: "seal.fill", title: section.title, badge: nil, color: .green) {
                MarkdownView(markdown: section.body)
            }
        } else if kind.hasPrefix("offene fragen") {
            highlightCard(icon: "questionmark.circle.fill", title: section.title, badge: nil, color: .orange) {
                MarkdownView(markdown: section.body)
            }
        } else {
            let (heading, time) = Self.splitTimestamp(section.title)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(heading).font(Theme.Font.heading)
                    if let time {
                        Text(time)
                            .font(Theme.Font.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                            .help("Zeitpunkt in der Aufnahme")
                    }
                }
                MarkdownView(markdown: section.body, onToggleTask: update)
                    .font(.system(.body).leading(.loose))
            }
        }
    }

    /// „Budget [00:14:05]“ → („Budget“, „14:05“)
    static func splitTimestamp(_ title: String) -> (String, String?) {
        guard let range = title.range(of: #"\s*\[(\d{2}):(\d{2}):(\d{2})\]\s*$"#, options: .regularExpression) else {
            return (title, nil)
        }
        let digits = title[range].filter(\.isNumber)
        let parts = [String(digits.prefix(2)), String(digits.dropFirst(2).prefix(2)), String(digits.suffix(2))]
        let time = parts[0] == "00" ? "\(parts[1]):\(parts[2])" : parts.joined(separator: ":")
        return (String(title[..<range.lowerBound]), time)
    }

    private func highlightCard<Content: View>(icon: String, title: String, badge: String?, color: Color,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(Theme.Font.body.weight(.semibold))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(Theme.Font.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.12)))
                }
            }
            content()
        }
        .padding(Theme.Space.l)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    // MARK: Transkript

    @ViewBuilder
    private func transcriptTab(color: Color) -> some View {
        if let t = transcript {
            let turns = TranscriptTurn.group(t.segments, speakers: app.settings.speakerLabels)
            LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(turns) { turn in
                    transcriptTurn(turn, color: color)
                }
                Text("Transkribiert mit \(t.engine)")
                    .font(Theme.Font.caption).foregroundStyle(.tertiary).padding(.top, Theme.Space.m)
            }
        } else {
            placeholder("👂", "Das Transkript ist noch nicht fertig", "\(AppInfo.name) hört sich die Aufnahme gerade an.")
        }
    }

    @ViewBuilder
    private func transcriptTurn(_ turn: TranscriptTurn, color: Color) -> some View {
        let mine = turn.speaker == "Ich"
        let bubble = VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack(spacing: Theme.Space.xs) {
                if let speaker = turn.speaker { Text(speaker).font(Theme.Font.caption.weight(.semibold)) }
                Text(TimeFormat.clock(turn.start)).font(Theme.Font.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            .foregroundStyle(mine ? color : .secondary)
            Text(turn.text)
                .font(.system(.body).leading(.loose))
                .textSelection(.enabled)
                .padding(.horizontal, turn.speaker == nil ? 0 : Theme.Space.m)
                .padding(.vertical, turn.speaker == nil ? 0 : Theme.Space.s + 2)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(turn.speaker == nil ? .clear : (mine ? color.opacity(0.12) : Color.primary.opacity(0.05)))
                )
        }
        if turn.speaker == nil {
            bubble
        } else {
            HStack {
                if mine { Spacer(minLength: 60) }
                bubble
                if !mine { Spacer(minLength: 60) }
            }
        }
    }

    // MARK: Export

    @ViewBuilder
    private func exportTab(_ rec: Recording) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            if rec.exports.isEmpty {
                placeholder("📤", "Noch nicht abgelegt", "Sobald die Notizen fertig sind, landen sie in deinen Zielen.")
            }
            ForEach(rec.exports, id: \.destinationID) { e in
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: Destinations.info(e.destinationID)?.symbol ?? "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.destinationName).font(Theme.Font.body.weight(.semibold))
                        Text(e.message).font(Theme.Font.caption)
                            .foregroundStyle(e.success || e.skipped == true ? Color.secondary : Color.orange)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if let link = e.url, let url = URL(string: link) {
                        Button("Öffnen") { NSWorkspace.shared.open(url) }.buttonStyle(SecondaryButtonStyle())
                    }
                    Image(systemName: e.success ? "checkmark.circle.fill" : (e.skipped == true ? "minus.circle" : "xmark.circle.fill"))
                        .font(.system(size: 16))
                        .foregroundStyle(e.success ? Color.green : (e.skipped == true ? Color.secondary : Color.orange))
                }
                .padding(Theme.Space.m)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.035)))
            }
            HStack {
                Button("Erneut ablegen") { app.reexport(recordingID) }.buttonStyle(SecondaryButtonStyle())
                SettingsLink { Text("Ziele einrichten …") }.buttonStyle(.link)
            }
            .padding(.top, Theme.Space.s)
        }
    }

    private func placeholder(_ emoji: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: Theme.Space.s) {
            Text(emoji).font(.system(size: 34))
            Text(title).font(Theme.Font.body.weight(.semibold))
            Text(detail).font(Theme.Font.small).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxl + Theme.Space.l)
    }
}

// MARK: - Notizen in Abschnitte zerlegen

/// Teilt die Notizen in Kurzfassung und Abschnitte, damit Aufgaben, Entscheidungen usw. eigene Karten bekommen.
struct NoteDocument {
    struct Section: Identifiable {
        let id: Int
        let title: String
        let body: String
    }

    let intro: String
    let sections: [Section]

    init(markdown: String) {
        var intro: [String] = []
        var sections: [Section] = []
        var title: String?
        var body: [String] = []

        func flush() {
            if let title {
                sections.append(Section(id: sections.count, title: title,
                                        body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            body = []
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if title == nil {
                intro.append(line)
            } else {
                body.append(line)
            }
        }
        flush()
        self.intro = intro.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        self.sections = sections
    }

    /// Setzt die Notizen mit einem geänderten Abschnitt (z. B. abgehakte Aufgabe) wieder zusammen.
    func replacing(_ sectionID: Int, with newBody: String) -> String {
        var parts: [String] = intro.isEmpty ? [] : [intro]
        for s in sections {
            parts.append("## \(s.title)\n" + (s.id == sectionID ? newBody : s.body))
        }
        return parts.joined(separator: "\n\n")
    }
}

/// Aufeinanderfolgende Segmente desselben Sprechers als ein Redebeitrag
struct TranscriptTurn: Identifiable {
    let id: Int
    let speaker: String?
    let start: Double
    let text: String

    static func group(_ segments: [TranscriptSegment], speakers: Bool) -> [TranscriptTurn] {
        var turns: [TranscriptTurn] = []
        var speaker: String?
        var start = 0.0
        var texts: [String] = []

        func flush() {
            guard !texts.isEmpty else { return }
            turns.append(TranscriptTurn(id: turns.count, speaker: speaker, start: start, text: texts.joined(separator: " ")))
            texts = []
        }

        for seg in segments {
            let who = speakers ? seg.speaker : nil
            // Neuer Beitrag bei Sprecherwechsel – ohne Sprecher alle 90 Sekunden ein neuer Absatz
            if texts.isEmpty || who != speaker || (who == nil && seg.start - start > 90) {
                flush()
                speaker = who
                start = seg.start
            }
            texts.append(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        flush()
        return turns
    }
}

// MARK: - Laufende Aufnahme

/// Dunkle Bühne während der Aufnahme: große Uhr, leuchtende Wellenform und die Live-Mitschrift im Mittelpunkt.
struct LiveRecordingView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var meter = AppState.shared.meter
    var compact = false
    @State private var glow = false

    var body: some View {
        let rec = app.activeRecording
        let paused = app.isPaused
        let category = app.category(rec?.categoryID)
        ZStack {
            LinearGradient(colors: [Theme.stageRaised, Theme.stage], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill((category?.color ?? Theme.accent).opacity(paused ? 0.08 : 0.35))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(y: -220)
                .scaleEffect(glow ? 1.1 : 0.9)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: glow)

            VStack(spacing: Theme.Space.xl) {
                HStack {
                    if compact {
                        Button { app.selection = nil } label: { Label("Alle", systemImage: "chevron.left") }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                    }
                    HStack(spacing: Theme.Space.s) {
                        if paused {
                            Image(systemName: "pause.fill").foregroundStyle(.orange)
                        } else {
                            PulsingDot(size: 6)
                        }
                        Text(paused ? "Pausiert" : "Aufnahme läuft")
                    }
                    .font(Theme.Font.small.weight(.semibold))
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    Spacer()
                    if let category {
                        Text("\(category.displayEmoji)  \(category.name)")
                            .font(Theme.Font.small.weight(.medium))
                            .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.08)))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))

                VStack(spacing: Theme.Space.s) {
                    Text(TimeFormat.duration(meter.elapsed))
                        .font(Theme.Font.number(compact ? 48 : 64, weight: .semibold))
                        .foregroundStyle(.white.opacity(paused ? 0.5 : 1))
                        .contentTransition(.numericText())
                    HStack(spacing: Theme.Space.xl) {
                        Waveform(level: meter.mic, color: Theme.accent, bars: 26, height: 30, muted: paused)
                        if rec?.hasSystemAudio == true {
                            Waveform(level: meter.system, color: Color(hex: "#7C9CFF")!, bars: 26, height: 30, muted: paused)
                        }
                    }
                    HStack(spacing: Theme.Space.xl) {
                        Label("Du", systemImage: "mic.fill")
                        if rec?.hasSystemAudio == true { Label("Gesprächspartner", systemImage: "speaker.wave.2.fill") }
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(.white.opacity(0.4))
                }

                LiveTranscriptView(style: .stage)
                    .frame(maxWidth: 620)
                    .frame(maxHeight: .infinity)

                if app.settings.showConsentReminder {
                    Label("Bitte hole das Einverständnis aller Beteiligten ein.", systemImage: "hand.raised.fill")
                        .font(Theme.Font.caption).foregroundStyle(.white.opacity(0.35))
                }

                HStack(spacing: Theme.Space.m) {
                    Button("Verwerfen") { app.cancelRecording() }
                        .buttonStyle(.plain)
                        .font(Theme.Font.small.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    PauseButton(compact: true)
                        .buttonStyle(RoundIconButtonStyle(size: 46, fill: .white.opacity(0.12), foreground: .white))
                    Button { app.stopRecording() } label: {
                        Label("Stoppen & Notizen erstellen", systemImage: "stop.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(compact ? Theme.Space.l : Theme.Space.xxl)
        }
        .onAppear { glow = true }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: paused)
    }
}

/// Zeigt während der Aufnahme mit, was gesprochen wird.
struct LiveTranscriptView: View {
    enum Style { case stage, compact, menu }

    @ObservedObject var live = AppState.shared.live
    var style: Style = .compact

    var body: some View {
        let onDark = style != .compact
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    (Text(live.settled)
                        .foregroundColor(onDark ? .white.opacity(0.92) : .primary)
                     + Text(live.settled.isEmpty ? "" : " ")
                     + Text(live.volatile)
                        .foregroundColor(onDark ? .white.opacity(0.45) : .secondary))
                        .font(font)
                        .lineSpacing(style == .stage ? 6 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("ende")
                }
            }
            .onChange(of: live.text) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("ende", anchor: .bottom) }
            }
        }
        .frame(maxHeight: style == .stage ? .infinity : (style == .menu ? 52 : 110))
        // Oben weich ausblenden, damit älterer Text nicht hart abgeschnitten wirkt
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                     .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: style == .stage ? .center : .leading) {
            if live.isEmpty {
                Text(live.unavailable ?? (style == .stage ? "Sobald jemand spricht, erscheint hier die Live-Mitschrift." : "Live-Mitschrift erscheint hier …"))
                    .font(style == .stage ? Theme.Font.body : Theme.Font.caption)
                    .foregroundStyle(onDark ? AnyShapeStyle(Color.white.opacity(0.35)) : AnyShapeStyle(.tertiary))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var font: Font {
        switch style {
        case .stage: return .system(size: 20, weight: .medium)
        case .compact: return Theme.Font.small
        case .menu: return Theme.Font.caption
        }
    }
}

/// Pausieren / Fortsetzen der laufenden Aufnahme.
struct PauseButton: View {
    @EnvironmentObject var app: AppState
    var compact = false

    var body: some View {
        Button { app.togglePause() } label: {
            if compact {
                Image(systemName: app.isPaused ? "play.fill" : "pause.fill")
            } else {
                Label(app.isPaused ? "Fortsetzen" : "Pause", systemImage: app.isPaused ? "play.fill" : "pause.fill")
            }
        }
        .help(app.isPaused ? "Aufnahme fortsetzen (⇧⌘P)" : "Aufnahme pausieren (⇧⌘P)")
    }
}
