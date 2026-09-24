import AVFoundation
import EarnoteCore
import SwiftUI

/// Eine Aufnahme: Notiz oder Transkript, darunter die Abspielleiste, oben Teilen und weitere Aktionen.
struct RecordingDetailView: View {
    let id: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(ProcessingQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss
    @SceneStorage("detail.mode") private var mode = Mode.note
    @State private var note: Summary?
    @State private var transcript: Transcript?
    @State private var player = AudioPlayer()
    @State private var confirmsDeletion = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var shareFile: ShareFile?
    @State private var editingNote = false
    @State private var resummarizing = false
    @State private var correcting = false
    @State private var deck: LearnDeck?

    enum Mode: String { case note, transcript }

    private var recording: Recording? { library.recording(id) }

    var body: some View {
        Group {
            if let recording {
                content(recording)
            } else {
                ContentUnavailableView("Aufnahme nicht gefunden", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(recording?.displayTitle ?? "")
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            if player.isLoaded { PlayerBar(player: player) }
        }
        // Neu laden, sobald die Verarbeitung weiterkommt oder die Notiz sich ändert
        .task(id: reloadKey) { await reload() }
        .onDisappear { player.stop() }
        .confirmationDialog("Aufnahme löschen?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                library.delete(id)
                dismiss()
            }
        }
        .sheet(item: $shareFile) { ActivitySheet(url: $0.url).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $editingNote) {
            if let note { NoteEditor(id: id, markdown: note.markdown) { Task { await reload() } } }
        }
        .sheet(isPresented: $resummarizing) { ResummarizeSheet(id: id) }
        .sheet(isPresented: $correcting) { CorrectTermSheet(id: id) { Task { await reload() } } }
        .navigationDestination(item: $deck) { FlashcardSession(deck: $0) }
        .alert("Umbenennen", isPresented: $renaming) {
            TextField("Titel", text: $newTitle)
            Button("Sichern") { library.rename(id, to: newTitle) }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    /// „24. Sept. · 1 Std. 25 Min. · Vorlesung“
    private var subtitle: String {
        guard let r = recording else { return "" }
        var parts = [r.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())]
        if r.status != .recording {
            parts.append(Duration.seconds(r.duration).formatted(.units(allowed: r.duration < 60 ? Set([.seconds]) : Set([.hours, .minutes]), width: .abbreviated)))
        }
        if let name = library.category(r.categoryID)?.name { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    private var reloadKey: String {
        guard let r = recording else { return "" }
        return "\(r.status.rawValue)|\(r.summaryTitle ?? "")|\(r.summaryPreview ?? "")|\(r.taskCount)"
    }

    @ViewBuilder private func content(_ recording: Recording) -> some View {
        switch recording.status {
        case .recording:
            ContentUnavailableView("Nimmt gerade auf", systemImage: "record.circle",
                                   description: Text("Nach dem Stopp entsteht hier die Notiz."))
        case .failed where note == nil:
            ContentUnavailableView {
                Label("Verarbeitung fehlgeschlagen", systemImage: "exclamationmark.triangle")
            } description: {
                Text(recording.errorMessage ?? String(localized: "Unbekannter Fehler"))
            } actions: {
                Button("Erneut versuchen") { library.enqueue(id) }.buttonStyle(.borderedProminent)
            }
        case let status where status.isBusy && note == nil:
            ProcessingView(recording: recording, draft: queue.drafts[id])
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Ansicht", selection: $mode) {
                        Text("Notiz").tag(Mode.note)
                        Text("Transkript").tag(Mode.transcript)
                    }
                    .pickerStyle(.segmented)
                    if let progress = library.flashcardProgress[id] {
                        ProgressView(value: Double(progress.done), total: Double(max(1, progress.of))) {
                            Label("Karteikarten entstehen …", systemImage: "rectangle.on.rectangle.angled")
                                .font(.subheadline)
                        }
                    }
                    if mode == .note {
                        if let note {
                            NoteContentView(markdown: note.markdown) { line in
                                library.toggleTask(id, in: note.markdown, line: line)
                                Task { await reload() }
                            }
                        } else {
                            Text("Keine Notiz – nur das Transkript.").foregroundStyle(.secondary)
                        }
                    } else if let transcript {
                        TranscriptContentView(transcript: transcript) { player.play(from: $0) }
                    } else {
                        Text("Kein Transkript vorhanden.").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let note {
                ShareLink(item: "# \(note.title)\n\n\(note.markdown)", subject: Text(note.title)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
            Menu("Mehr", systemImage: "ellipsis") {
                if let note {
                    Section {
                        Button("Lernzettel als PDF", systemImage: "doc.richtext") { sharePDF(note) }
                        if cards(note).isEmpty {
                            Button("Karteikarten erzeugen", systemImage: "rectangle.on.rectangle.angled") {
                                Task { _ = await library.makeFlashcards(id) }
                            }
                            .disabled(library.makingFlashcards.contains(id))
                        } else {
                            Button("Karteikarten lernen", systemImage: "rectangle.on.rectangle.angled") {
                                deck = LearnDeck(title: note.title, cards: cards(note))
                            }
                            Button("Als Anki-Datei teilen", systemImage: "square.and.arrow.up.on.square") {
                                if let url = try? AnkiExport.file(title: note.title, cards: cards(note)) { shareFile = ShareFile(url: url) }
                            }
                        }
                    }
                    Section {
                        Button("Notiz bearbeiten", systemImage: "pencil") { editingNote = true }
                        Button("Namen & Begriffe korrigieren …", systemImage: "character.cursor.ibeam") { correcting = true }
                        if recording?.isNoteEdited == true {
                            Button("Auf KI-Fassung zurücksetzen", systemImage: "arrow.uturn.backward") {
                                library.restoreGeneratedNote(id)
                                Task { await reload() }
                            }
                        }
                        Button("Vereinfachen", systemImage: "text.badge.minus") {
                            library.reprocess(id, retranscribe: false, instruction: String(localized: "Erkläre die Inhalte einfacher und kürzer."), fromNote: true)
                        }
                        Button("Neu zusammenfassen …", systemImage: "arrow.clockwise") { resummarizing = true }
                    }
                }
                Section {
                    Button("Umbenennen", systemImage: "pencil.line") {
                        newTitle = recording?.displayTitle ?? ""
                        renaming = true
                    }
                    RecordingMenu(id: id, onDelete: { confirmsDeletion = true })
                }
            }
        }
    }

    private func cards(_ note: Summary) -> [Flashcard] { Flashcards.entries(note.markdown).map(\.card) }

    private func sharePDF(_ note: Summary) {
        let kicker = recording.flatMap { library.category($0.categoryID)?.name }
        if let url = try? NotePDF.make(title: note.title, kicker: kicker, meta: subtitle, markdown: note.markdown) {
            shareFile = ShareFile(url: url)
        }
    }

    private func reload() async {
        note = await library.summary(id)
        if mode == .transcript || transcript == nil { transcript = await library.transcript(id) }
        if let recording, recording.status != .recording, let url = library.audio.playbackURL(for: recording) {
            player.load(url)
        }
    }
}

/// Während die Notiz entsteht: Fortschritt und – sobald die KI schreibt – der Entwurf
private struct ProcessingView: View {
    let recording: Recording
    let draft: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView(value: recording.progress) {
                    Text(recording.status.label)
                } currentValueLabel: {
                    Text(recording.progress, format: .percent.precision(.fractionLength(0)))
                }
                if let draft, !draft.isEmpty {
                    NoteContentView(markdown: draft, onToggle: nil)
                        .opacity(0.7)
                } else {
                    Text("Du kannst die App verlassen – Earnote schreibt weiter und sagt Bescheid, wenn die Notiz fertig ist.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

/// Die Notiz als Blöcke (aus dem Kern: `NoteMarkdown`) – Überschriften, Absätze, Aufzählungen, Aufgaben, Karteikarten
struct NoteContentView: View {
    let markdown: String
    var onToggle: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(NoteMarkdown.blocks(markdown)) { block in
                switch block {
                case .heading(_, let level, let text, _):
                    Text(inline(text))
                        .font(level <= 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                case .paragraph(_, let text):
                    Text(inline(text))
                case .bullet(_, let text, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.tint)
                        Text(inline(text))
                    }
                    .padding(.leading, CGFloat(indent) * 16)
                case .numbered(_, let number, let text, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
                        Text(inline(text))
                    }
                    .padding(.leading, CGFloat(indent) * 16)
                case .task(_, let text, let isDone, let line):
                    Button { onToggle?(line) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            Text(inline(text))
                                .strikethrough(isDone)
                                .foregroundStyle(isDone ? .secondary : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(onToggle == nil)
                    .accessibilityValue(isDone ? "erledigt" : "offen")
                case .flashcard(_, let question, let answer):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inline(question)).bold()
                        Text(inline(answer)).foregroundStyle(.secondary)
                    }
                case .quote(_, let text):
                    Text(inline(text))
                        .italic()
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().fill(.tint).frame(width: 3) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// Fett, kursiv und Code innerhalb einer Zeile
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Transkript mit Zeitmarken; Tippen spielt ab der Stelle ab
struct TranscriptContentView: View {
    let transcript: Transcript
    var onPlay: (TimeInterval) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(transcript.segments) { segment in
                Button { onPlay(segment.start) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Duration.seconds(segment.start).formatted(.time(pattern: .minuteSecond)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tint)
                        Text(segment.text)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ab hier anhören")
            }
        }
    }
}

/// Abspielen der Aufnahme – 15 s zurück, Tempo, Position
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    var rate: Float = 1 { didSet { player?.rate = rate } }
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var url: URL?

    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    func load(_ url: URL) {
        guard url != self.url else { return }
        self.url = url
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        isLoaded = player != nil
    }

    func toggle() { isPlaying ? pause() : play(from: nil) }

    func play(from time: TimeInterval?) {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        if let time { player.currentTime = max(0, time) }
        player.rate = rate
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    func skip(_ seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, player.currentTime + seconds), duration)
    }

    func seek(_ time: TimeInterval) { player?.currentTime = time }
}

private struct PlayerBar: View {
    let player: AudioPlayer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 16) {
                Button("15 Sekunden zurück", systemImage: "gobackward.15") { player.skip(-15) }
                    .labelStyle(.iconOnly)
                Button(player.isPlaying ? "Pause" : "Abspielen", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                    player.toggle()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek($0) }), in: 0...max(1, player.duration))
                    .accessibilityLabel("Position")
                Menu {
                    Picker("Tempo", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {
                        Text("1×").tag(Float(1))
                        Text("1,5×").tag(Float(1.5))
                        Text("2×").tag(Float(2))
                    }
                } label: {
                    Text(player.rate == 1 ? "1×" : player.rate == 1.5 ? "1,5×" : "2×").monospacedDigit()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(in: .capsule)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Blätter der Notiz

/// Notiz von Hand bearbeiten (Markdown). Die KI-Fassung bleibt erhalten und lässt sich wiederherstellen.
private struct NoteEditor: View {
    let id: UUID
    @State var markdown: String
    var onSave: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $markdown)
                .font(.body.monospaced())
                .padding(.horizontal)
                .navigationTitle("Notiz bearbeiten")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            library.updateSummaryText(id, markdown: markdown)
                            dismiss()
                            onSave()
                        }
                    }
                }
        }
    }
}

/// Neu zusammenfassen – optional mit eigener Anweisung und neuer Transkription (wie am Mac)
private struct ResummarizeSheet: View {
    let id: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var retranscribe = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. „Mehr Beispiele“ oder „Nur die Formeln“", text: $instruction, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Anweisung (freiwillig)")
                } footer: {
                    Text("Gilt nur für diesen Durchgang.")
                }
                if library.hasAudio(id) {
                    Toggle("Auch neu transkribieren", isOn: $retranscribe)
                }
            }
            .navigationTitle("Neu zusammenfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starten") {
                        library.reprocess(id, retranscribe: retranscribe, instruction: instruction)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Falsch verstandene Namen und Fachbegriffe ersetzen – in Titel, Notiz und Transkript; auf Wunsch fürs Wörterbuch merken
private struct CorrectTermSheet: View {
    let id: UUID
    var onDone: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var wrong = ""
    @State private var right = ""
    @State private var remember = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Falsch, z. B. „Eigen Werte“", text: $wrong)
                    TextField("Richtig, z. B. „Eigenwerte“", text: $right)
                }
                Section {
                    Toggle("Ins Wörterbuch aufnehmen", isOn: $remember)
                } footer: {
                    Text("Dann schreibt Earnote den Begriff auch in künftigen Aufnahmen richtig.")
                }
            }
            .autocorrectionDisabled()
            .navigationTitle("Korrigieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ersetzen") {
                        library.correctTerm(id, wrong: wrong, right: right, remember: remember)
                        dismiss()
                        onDone()
                    }
                    .disabled(wrong.trimmingCharacters(in: .whitespaces).isEmpty || right.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
