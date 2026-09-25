import AVFoundation
import EarnoteCore
import SwiftUI

/// Eine Aufnahme: Notiz oder Transkript, darunter die Abspielleiste, oben Teilen und weitere Aktionen.
struct RecordingDetailView: View {
    let id: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(ProcessingQueue.self) private var queue
    @Environment(HandoffSender.self) private var handoffs
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
    @State private var rewriting = false
    @State private var correctingNames = false
    @State private var deck: LearnDeck?
    @State private var chatting = false
    @State private var translating = false
    @State private var detectingSpeakers = false
    @State private var showsPro: Pro.Feature?
    @Environment(\.speakerDiarizer) private var diarizer
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// „Beides“ nur mit Platz (iPad): Transkript als eigene Spalte neben der Notiz, wie ⌘3 am Mac – nicht `inspector`,
    /// der in der Split-Ansicht die Kopfzeile der Notiz verschluckte
    enum Mode: String { case note, transcript, both }

    private var showsBoth: Bool { mode == .both && sizeClass == .regular && transcript != nil }

    private var recording: Recording? { library.recording(id) }

    var body: some View {
        Group {
            if let recording {
                content(recording)
            } else {
                ContentUnavailableView("Aufnahme nicht gefunden", systemImage: "questionmark.folder")
            }
        }
        .paper()
        // Mit Notiz steht der Titel groß im Inhalt (`NoteHeader`, wie in Sprachmemos) – die Leiste bleibt frei für
        // Fragen, Teilen und Mehr. Ein langer Titel oder ein Titelmenü klappte dort sonst alle Knöpfe in „…“ (iOS 26).
        .navigationTitle(recording?.displayTitle ?? "")
        .navigationSubtitle(showsHeader ? "" : subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsHeader { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
            toolbar
        }

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
        .sheet(isPresented: $correctingNames) {
            NamesSheet(id: id, transcript: transcript, note: note,
                       detectSpeakers: canDetectSpeakers ? { Task { await detectSpeakers() } } : nil) {
                Task { await reload() }
            }
        }
        .sheet(item: $showsPro) { ProSheet(highlight: $0) }
        .overlay(alignment: .top) {
            if detectingSpeakers {
                Label("Sprecher werden erkannt …", systemImage: "person.2.wave.2")
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(in: .capsule)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $translating, onDismiss: { Task { await reload() } }) {
            if let note { TranslationSheet(id: id, note: note, transcript: transcript) }
        }
        .sheet(isPresented: $chatting, onDismiss: { Task { await reload() } }) {
            if let note { NoteChatView(id: id, note: note, transcript: transcript) }
        }
        .sheet(isPresented: $editingNote) {
            if let note { NoteEditor(id: id, markdown: note.markdown) { Task { await reload() } } }
        }
        .sheet(isPresented: $rewriting) { RewriteSheet(id: id) { Task { await reload() } } }
        .navigationDestination(item: $deck) { FlashcardSession(deck: $0) }
        .alert("Umbenennen", isPresented: $renaming) {
            TextField("Titel", text: $newTitle)
            Button("Sichern") {
                if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty { library.rename(id, to: newTitle) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    /// Kopf im Inhalt, sobald es eine Notiz oder ein Transkript zu lesen gibt
    private var showsHeader: Bool {
        guard let recording else { return false }
        return !(recording.status == .recording || (note == nil && (recording.status.isBusy
            || recording.status == .failed || recording.status == .waitingForMac)))
    }

    private var header: some View {
        NoteHeader(title: recording?.displayTitle ?? "", meta: meta, id: id) {
            newTitle = recording?.displayTitle ?? ""
            renaming = true
        }
    }

    /// „24. Sept., 09:03 · 1 Std. 25 Min.“ – der Bereich steht als eigenes Menü daneben
    private var meta: String {
        guard let r = recording else { return "" }
        var parts = [r.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())]
        if r.duration >= 1 {
            parts.append(Duration.seconds(r.duration).formatted(.units(allowed: r.duration < 60 ? Set([.seconds]) : Set([.hours, .minutes]), width: .abbreviated)))
        }
        return parts.joined(separator: " · ")
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
        case .waitingForMac where note == nil:
            ContentUnavailableView {
                Label("Wartet auf deinen Mac", systemImage: "laptopcomputer")
            } description: {
                Text(handoffs.pending[id]?.errorMessage
                     ?? String(localized: "Sobald Earnote auf deinem Mac läuft, schreibt er die Notiz. Sie erscheint dann hier."))
            } actions: {
                Button("Auf dem iPhone verarbeiten") { handoffs.processHere(id) }.buttonStyle(.bordered)
            }
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
            if showsBoth, let transcript {
                VStack(alignment: .leading, spacing: 12) {
                    header.padding([.horizontal, .top])
                    modePicker.padding(.horizontal)
                    HStack(spacing: 0) {
                        ScrollView {
                            noteContent
                                .padding()
                                .frame(maxWidth: 700)
                                .frame(maxWidth: .infinity)
                        }
                        Divider()
                        ScrollView {
                            TranscriptContentView(transcript: transcript) { player.play(from: $0) }.padding()
                        }
                        .frame(width: 340)
                        .background(.background.secondary)
                    }
                }
            } else {
                singleColumn
            }
        }
    }

    private var modePicker: some View {
        Picker("Ansicht", selection: $mode) {
            Text("Notiz").tag(Mode.note)
            Text("Transkript").tag(Mode.transcript)
            if sizeClass == .regular && transcript != nil { Text("Beides").tag(Mode.both) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 700)
    }

    /// Notiz (oder Karteikarten-Fortschritt) ohne Umschalter – für die Spalte neben dem Transkript
    @ViewBuilder private var noteContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress = library.flashcardProgress[id] {
                ProgressView(value: Double(progress.done), total: Double(max(1, progress.of))) {
                    Label("Karteikarten entstehen …", systemImage: "rectangle.on.rectangle.angled").font(.subheadline)
                }
            }
            if let note {
                NoteContentView(markdown: note.markdown) { line in
                    library.toggleTask(id, in: note.markdown, line: line)
                    Task { await reload() }
                }
            } else {
                Text("Keine Notiz – nur das Transkript.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var singleColumn: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    modePicker
                    // „Beides“ ohne Platz (Fenster schmaler gezogen): dann die Notiz
                    if mode != .transcript {
                        noteContent
                    } else if let transcript {
                        TranscriptContentView(transcript: transcript) { player.play(from: $0) }
                    } else {
                        Text("Kein Transkript vorhanden.").foregroundStyle(.secondary)
                    }
                }
                .padding()
                // Lesbare Zeilenlänge am iPad statt quer über den Bildschirm (DESIGN_GUIDELINES 31)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
    }

    /// Sprecher nachträglich erkennen (Earnote Pro): Stimmen ins Transkript eintragen, dann die Notiz neu schreiben
    private func detectSpeakers() async {
        guard Pro.isUnlocked || Pro.triesLeft(.speakers) > 0 else { showsPro = .speakers; return }
        guard let diarizer, let transcript, let recording, let url = library.audio.playbackURL(for: recording) else { return }
        detectingSpeakers = true
        defer { detectingSpeakers = false }
        let result = await ProcessingPipeline.withSpeakers(transcript, audio: url, diarizer: diarizer)
        guard Speakers.names(in: result).count >= 2 else {
            library.lastError = String(localized: "Earnote hat in dieser Aufnahme nur eine Stimme erkannt.")
            return
        }
        await library.saveTranscript(id, result)
        await reload()
        library.reprocess(id, retranscribe: false)
    }

    /// Höchstens drei Knöpfe (Regel 4): Fragen, Teilen, Mehr. „Mehr“ hat drei Gruppen mit zusammen höchstens 8 Einträgen.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if note != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fragen zur Notiz", systemImage: "bubble.left.and.text.bubble.right") { chatting = true }
            }
        }
        if let note {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "# \(note.title)\n\n\(note.markdown)", subject: Text(note.title)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Mehr", systemImage: "ellipsis") {
                if let note {
                    Section("Lernen") {
                        Button("Lernzettel als PDF", systemImage: "doc.richtext") { sharePDF(note) }
                        flashcardItems(note)
                        Button("Übersetzen …", systemImage: "character.bubble") { translating = true }
                    }
                    Section("Bearbeiten") {
                        Button("Notiz bearbeiten", systemImage: "pencil") { editingNote = true }
                        Button("Namen korrigieren …", systemImage: "character.cursor.ibeam") { correctingNames = true }
                        Button("Neu schreiben …", systemImage: "arrow.clockwise") { rewriting = true }
                    }
                }
                Section {
                    // Bereich und Umbenennen stehen im Kopf der Notiz, das eigene Fenster im Kontextmenü der Liste
                    RecordingMenu(id: id, showsCategory: !showsHeader, showsWindow: false, onDelete: { confirmsDeletion = true })
                }
            }
        }
    }

    /// Ein Eintrag: erzeugen, solange es keine Karten gibt – danach ein Untermenü mit Lernen und Anki
    @ViewBuilder private func flashcardItems(_ note: Summary) -> some View {
        let cards = cards(note)
        if cards.isEmpty {
            Button("Karteikarten erzeugen", systemImage: "rectangle.on.rectangle.angled") {
                Task { _ = await library.makeFlashcards(id) }
            }
            .disabled(library.makingFlashcards.contains(id))
        } else {
            Menu("Karteikarten", systemImage: "rectangle.on.rectangle.angled") {
                Button("Lernen", systemImage: "play.rectangle") { deck = LearnDeck(title: note.title, cards: cards) }
                Button("Als Anki-Datei teilen", systemImage: "square.and.arrow.up.on.square") {
                    if let url = try? AnkiExport.file(title: note.title, cards: cards) { shareFile = ShareFile(url: url) }
                }
            }
        }
    }

    private var canDetectSpeakers: Bool {
        diarizer != nil && recording.flatMap { library.audio.playbackURL(for: $0) } != nil && !detectingSpeakers
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
        if mode != .note || transcript == nil { transcript = await library.transcript(id) }
        if let recording, recording.status != .recording, let url = library.audio.playbackURL(for: recording) {
            player.load(url)
        }
    }
}

/// Titel (antippen benennt um, wie in Sprachmemos), darunter Datum, Dauer und der Bereich als Menü
private struct NoteHeader: View {
    let title: String
    let meta: String
    let id: UUID
    var rename: () -> Void
    @Environment(LibraryStore.self) private var library

    private var category: RecordingCategory? { library.category(library.recording(id)?.categoryID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: rename) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Umbenennen")
            HStack(spacing: 6) {
                Text(meta).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                Menu {
                    CategoryPicker(id: id)
                } label: {
                    HStack(spacing: 3) {
                        Text(category?.name ?? String(localized: "Ohne Bereich")).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                    }
                }
                .accessibilityLabel("Bereich: \(category?.name ?? String(localized: "Ohne Bereich"))")
            }
            .font(.subheadline)
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
            ForEach(transcript.segments.indices, id: \.self) { index in
                let segment = transcript.segments[index]
                // Name, sobald ein anderer Sprecher dran ist (Sprechererkennung, Earnote Pro)
                if let speaker = segment.speaker, index == 0 || transcript.segments[index - 1].speaker != speaker {
                    Text(speaker).font(.subheadline.weight(.semibold)).padding(.top, 4)
                }
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
