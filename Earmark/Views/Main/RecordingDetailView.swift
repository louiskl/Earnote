import SwiftUI

struct RecordingDetailView: View {
    @EnvironmentObject var app: AppState
    let recordingID: UUID

    enum Tab: String, CaseIterable { case summary = "Zusammenfassung", transcript = "Transkript", export = "Export" }
    @State private var tab: Tab = .summary
    @State private var title = ""
    @State private var summary: Summary?
    @State private var transcript: Transcript?
    @State private var copied = false

    private var recording: Recording? { app.recording(recordingID) }

    var body: some View {
        if let rec = recording {
            VStack(spacing: 0) {
                header(rec)
                Divider()
                ScrollView {
                    Group {
                        switch tab {
                        case .summary: summaryTab(rec)
                        case .transcript: transcriptTab
                        case .export: exportTab(rec)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .onAppear { reload(rec) }
            .onChange(of: rec.status) { _, _ in reload(rec) }
            .toolbar {
                ToolbarItemGroup {
                    Button { copy() } label: {
                        Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(summary == nil && transcript == nil)
                    Menu {
                        RecordingActions(recordingID: recordingID)
                    } label: {
                        Label("Aktionen", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func reload(_ rec: Recording) {
        title = rec.title
        summary = app.summary(recordingID)
        transcript = app.transcript(recordingID)
    }

    private func copy() {
        var text = ""
        if let s = summary { text += "# \(s.title)\n\n\(s.markdown)\n\n" }
        if tab == .transcript || summary == nil, let t = transcript { text += t.formatted(includeSpeakers: app.settings.speakerLabels) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    // MARK: Kopfbereich

    private func header(_ rec: Recording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CategoryIcon(category: app.category(rec.categoryID), size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Titel", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .bold))
                        .onSubmit { app.rename(recordingID, to: title) }
                    if let st = summary?.title, st != rec.title {
                        Text(st).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Label(rec.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        Label(TimeFormat.duration(rec.duration), systemImage: "clock")
                        if let s = rec.sourceApp { Label(s, systemImage: "video") }
                        if rec.hasSystemAudio { Label("Mikro + Systemton", systemImage: "speaker.wave.2") }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(app.categories) { c in
                        Button { app.setCategory(recordingID, c.id) } label: { Label(c.name, systemImage: c.symbol) }
                    }
                } label: {
                    if let c = app.category(rec.categoryID) { CategoryChip(category: c, selected: true) }
                    else { Text("Kategorie wählen") }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if rec.status != .done {
                statusBanner(rec)
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
    }

    @ViewBuilder
    private func statusBanner(_ rec: Recording) -> some View {
        if rec.status == .failed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(rec.errorMessage ?? "Unbekannter Fehler").font(.system(size: 12)).textSelection(.enabled)
                Spacer()
                Button("Erneut versuchen") { app.enqueue(recordingID) }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
        } else if rec.status.isBusy {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rec.status.label).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(rec.progress * 100)) %").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: rec.progress).tint(Theme.accent)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSoft))
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private func summaryTab(_ rec: Recording) -> some View {
        if let s = summary {
            VStack(alignment: .leading, spacing: 10) {
                MarkdownView(markdown: s.markdown)
                Text("Erstellt mit \(s.provider)").font(.caption).foregroundStyle(.tertiary).padding(.top, 16)
            }
        } else if rec.status.isBusy {
            placeholder("Die Zusammenfassung wird erstellt …", icon: "sparkles")
        } else if app.settings.ai.provider == AIProviderKind.none {
            placeholder("Zusammenfassungen sind ausgeschaltet. Wähle in den Einstellungen unter „KI“ einen Anbieter.", icon: "sparkles")
        } else {
            placeholder("Noch keine Zusammenfassung vorhanden.", icon: "sparkles")
        }
    }

    @ViewBuilder
    private var transcriptTab: some View {
        if let t = transcript {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(t.segments) { seg in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(TimeFormat.clock(seg.start))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 60, alignment: .leading)
                        if let sp = seg.speaker, app.settings.speakerLabels {
                            Text(sp)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(sp == "Ich" ? Theme.accent : .blue)
                                .frame(width: 50, alignment: .leading)
                        }
                        Text(seg.text).textSelection(.enabled)
                    }
                }
                Text("Transkribiert mit \(t.engine)").font(.caption).foregroundStyle(.tertiary).padding(.top, 12)
            }
        } else {
            placeholder("Das Transkript ist noch nicht fertig.", icon: "text.quote")
        }
    }

    @ViewBuilder
    private func exportTab(_ rec: Recording) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if rec.exports.isEmpty {
                placeholder("Noch nicht exportiert.", icon: "square.and.arrow.up")
            }
            ForEach(rec.exports, id: \.destinationID) { e in
                HStack(spacing: 12) {
                    Image(systemName: Destinations.info(e.destinationID)?.symbol ?? "square.and.arrow.up")
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.destinationName).font(.system(size: 13, weight: .semibold))
                        Text(e.message).font(.system(size: 12)).foregroundStyle(e.success ? Color.secondary : Color.orange)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if let link = e.url, let url = URL(string: link) {
                        Button("Öffnen") { NSWorkspace.shared.open(url) }.buttonStyle(SecondaryButtonStyle())
                    }
                    Image(systemName: e.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(e.success ? Color.green : Color.orange)
                }
                .card(padding: 12)
            }
            HStack {
                Button("Erneut exportieren") { app.reexport(recordingID) }.buttonStyle(SecondaryButtonStyle())
                SettingsLink { Text("Ziele einrichten …") }
            }
            .padding(.top, 6)
        }
    }

    private func placeholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

// MARK: - Laufende Aufnahme

struct LiveRecordingView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var meter = AppState.shared.meter
    @State private var pulse = false

    var body: some View {
        let rec = app.activeRecording
        VStack(spacing: 26) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 170, height: 170)
                    .scaleEffect(pulse ? 1.08 : 0.94)
                Circle().fill(Theme.accent.opacity(0.22)).frame(width: 120, height: 120)
                Image(systemName: "waveform").font(.system(size: 44, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }

            VStack(spacing: 6) {
                Text(TimeFormat.duration(meter.elapsed))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                Text(rec?.title ?? "Aufnahme").font(.title3).foregroundStyle(.secondary)
                if let c = app.category(rec?.categoryID) { CategoryChip(category: c, selected: false) }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack { Label("Mikrofon", systemImage: "mic.fill").frame(width: 120, alignment: .leading); LevelMeter(level: meter.mic, bars: 30) }
                HStack {
                    Label("Systemton", systemImage: "speaker.wave.2.fill").frame(width: 120, alignment: .leading)
                    if rec?.hasSystemAudio == true {
                        LevelMeter(level: meter.system, color: .blue, bars: 30)
                    } else {
                        Text("nicht aktiv").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 12))
            .card()
            .frame(maxWidth: 440)

            if app.settings.showConsentReminder {
                Label("Bitte hole das Einverständnis aller Beteiligten zur Aufnahme ein.", systemImage: "hand.raised.fill")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) { app.cancelRecording() } label: { Text("Verwerfen") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { app.stopRecording() } label: {
                    Label("Stoppen & auswerten", systemImage: "stop.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
