import EarnoteCore
import SwiftUI

// Pro-Funktionen am iPhone, am Mac frei (ROADMAP, entschieden 25.09.2026). Die Logik steckt im Kern
// (`NoteChat`, `Translation`), hier nur die Mac-Blätter – gleiche Wörter wie am iPhone (Regel 9).

/// KI für Fragen und Übersetzen – dieselbe, die die Notizen schreibt
@MainActor
private func noteClient(_ library: LibraryStore) throws -> any LLMClient {
    guard let client = try library.llm.make(library.settings.ai) else {
        throw ProSheetError.noAI
    }
    return client
}

private enum ProSheetError: LocalizedError {
    case noAI
    var errorDescription: String? {
        String(localized: "Dafür braucht es eine KI. Wähle in den Einstellungen unter „KI“, wer die Notizen schreibt.")
    }
}

/// Fragen zur Notiz: ein Gespräch mit der KI über diese Aufnahme, unten das Eingabefeld (wie Nachrichten)
struct NoteChatSheet: View {
    let recordingID: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var note: Summary?
    @State private var transcript: Transcript?
    @State private var messages: [NoteChat.Message] = []
    @State private var question = ""
    @State private var answering = false
    @State private var error: String?
    @State private var saved: Set<UUID> = []
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        [String(localized: "Erklär mir den schwierigsten Teil einfacher."),
         String(localized: "Was davon kommt wahrscheinlich in der Prüfung?"),
         String(localized: "Gib mir ein Beispiel dazu.")]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty { intro }
                        ForEach(messages) { message in
                            ChatMessageRow(message: message, saved: saved.contains(message.id)) { takeOver(message) }
                                .id(message.id)
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: messages.last?.text) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Deine Frage", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit { send(question) }
                Button("Senden") { send(question) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(answering || note == nil || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            Divider()
            HStack {
                Text(note?.title ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 560)
        .navigationTitle("Fragen zur Notiz")
        .task {
            note = await library.summary(recordingID)
            transcript = await library.transcript(recordingID)
            focused = true
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fragen zur Notiz").font(.title3.bold())
            Text("Frag nach, was du nicht verstanden hast. Die KI kennt die Notiz und sucht die passenden Stellen der Aufnahme heraus.")
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) { send(suggestion) }
                    .disabled(note == nil)
            }
        }
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !answering, let note else { return }
        let client: any LLMClient
        do { client = try noteClient(library) } catch { self.error = error.localizedDescription; return }
        error = nil
        question = ""
        let history = messages
        messages.append(NoteChat.Message(fromUser: true, text: text))
        messages.append(NoteChat.Message(fromUser: false, text: ""))
        let index = messages.count - 1
        answering = true
        let transcript = transcript
        Task {
            defer { answering = false }
            do {
                let answer = try await NoteChat.ask(client: client, title: note.title, note: note.markdown,
                                                    transcript: transcript, history: history, question: text) { partial in
                    Task { @MainActor in
                        if messages.indices.contains(index) { messages[index].text = partial }
                    }
                }
                messages[index].text = answer
            } catch {
                messages.remove(at: index)
                self.error = error.localizedDescription
            }
        }
    }

    /// Frage und Antwort unten an die Notiz hängen
    private func takeOver(_ answer: NoteChat.Message) {
        guard let i = messages.firstIndex(of: answer), i > 0, messages[i - 1].fromUser else { return }
        Task {
            guard let latest = await library.summary(recordingID) else { return }
            library.updateSummaryText(recordingID, markdown: latest.markdown
                                      + NoteChat.markdown(question: messages[i - 1].text, answer: answer.text))
            saved.insert(answer.id)
        }
    }
}

/// Eigene Fragen rechts im Akzent, Antworten links als Text
private struct ChatMessageRow: View {
    let message: NoteChat.Message
    let saved: Bool
    let takeOver: () -> Void

    var body: some View {
        if message.fromUser {
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(.tint, in: .rect(cornerRadius: 12))
                    .textSelection(.enabled)
            }
        } else if message.text.isEmpty {
            ProgressView().controlSize(.small)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ReadOnlyNoteText(markdown: message.text)
                    .textSelection(.enabled)
                Button(saved ? "In der Notiz" : "In Notiz übernehmen", systemImage: saved ? "checkmark" : "text.append",
                       action: takeOver)
                    .buttonStyle(.link)
                    .font(.callout)
                    .disabled(saved)
            }
        }
    }
}

/// Übersetzen: Notiz oder ganzes Transkript; die übersetzte Notiz kann die bisherige ersetzen
struct TranslationSheet: View {
    let recordingID: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var note: Summary?
    @State private var transcript: Transcript?
    @State private var what = What.note
    @State private var language = ""
    @State private var result: String?
    @State private var progress: Double?
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    enum What: Hashable { case note, transcript }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if transcript != nil {
                        Picker("Was", selection: $what) {
                            Text("Notiz").tag(What.note)
                            Text("Transkript").tag(What.transcript)
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Sprache", selection: $language) {
                        ForEach(Translation.languages, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                    }
                } footer: {
                    if what == .transcript {
                        Text("Ein langes Transkript übersetzt die KI Stück für Stück – mit lokaler KI kann das einige Minuten dauern.")
                    }
                }
                if let progress {
                    Section { ProgressView(value: progress) { Text("Wird übersetzt …") } }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                if let result {
                    Section("Übersetzung") {
                        ReadOnlyNoteText(markdown: result).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let result {
                    ShareLink(item: result) { Label("Teilen", systemImage: "square.and.arrow.up") }
                    if what == .note {
                        Button("Als Notiz übernehmen") {
                            library.updateSummaryText(recordingID, markdown: result)
                            dismiss()
                        }
                        .help("Ersetzt die Notiz. „Auf KI-Fassung zurücksetzen“ holt die bisherige zurück.")
                    }
                }
                Spacer()
                Button("Schließen") { task?.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Übersetzen", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(progress != nil || note == nil)
            }
            .padding(16)
        }
        .frame(width: 560, height: result == nil ? 300 : 600)
        .onChange(of: what) { result = nil }
        .onChange(of: language) { result = nil }
        .task {
            note = await library.summary(recordingID)
            transcript = await library.transcript(recordingID)
            // Meist will man in die andere Sprache: deutsche Notizen nach Englisch, alles andere nach Deutsch
            if language.isEmpty { language = library.settings.ai.summaryLanguage == "Deutsch" ? "Englisch" : "Deutsch" }
        }
    }

    private func start() {
        guard let note else { return }
        let client: any LLMClient
        do { client = try noteClient(library) } catch { self.error = error.localizedDescription; return }
        error = nil
        result = nil
        progress = 0
        let what = what, language = language, transcript = transcript
        task = Task {
            defer { progress = nil }
            let report: @Sendable (Double) -> Void = { value in Task { @MainActor in progress = value } }
            do {
                switch what {
                case .note:
                    result = try await Translation.note(note.markdown, to: language, client: client, progress: report)
                case .transcript:
                    guard let transcript else { return }
                    result = try await Translation.transcript(transcript, to: language, client: client, progress: report)
                        .joined(separator: "\n\n")
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Klausur-Radar: alles Prüfungsrelevante eines Bereichs auf einer Seite – die Abschnitte „Wichtig für die Klausur“
/// bzw. „Prüfungshinweise“ aller Notizen, neueste Vorlesung zuerst. Ohne KI-Anfrage.
struct ExamRadarSheet: View {
    let categoryID: UUID
    /// Notiz im Hauptfenster zeigen
    let onOpen: (UUID) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [(id: UUID, title: String, date: Date, items: [String])] = []
    @State private var loaded = false

    private var categoryName: String { library.category(categoryID)?.name ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Klausur-Radar · \(categoryName)").font(.title3.bold())
                Text("Alles, was in deinen Notizen als prüfungsrelevant gilt – dazu, was du mit „Wichtig“ markiert hast. Neueste Vorlesung zuerst.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Divider()
            Group {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if notes.isEmpty {
                    ContentUnavailableView {
                        Label("Noch nichts für die Klausur", systemImage: "scope")
                    } description: {
                        Text("Markiere während der Vorlesung Stellen als wichtig (⇧⌘I oder in der Menüleiste). Earnote sammelt hier alles, was als prüfungsrelevant gilt.")
                    }
                } else {
                    List {
                        ForEach(notes, id: \.id) { note in
                            Section {
                                ForEach(note.items, id: \.self) { ReadOnlyNoteText(markdown: $0) }
                            } header: {
                                HStack(alignment: .firstTextBaseline) {
                                    Button(note.title) { onOpen(note.id); dismiss() }
                                        .buttonStyle(.link)
                                        .help("Notiz öffnen")
                                    Spacer()
                                    Text(note.date, format: .dateTime.day().month()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            Divider()
            HStack {
                if !notes.isEmpty {
                    ShareLink(item: ExamRadar.markdown(title: String(localized: "Klausur-Radar: \(categoryName)"),
                                                       notes: notes.map { ($0.title, $0.items) })) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 600, height: 560)
        .navigationTitle("Klausur-Radar")
        .task { await load() }
    }

    private func load() async {
        var found: [(id: UUID, title: String, date: Date, items: [String])] = []
        let recordings = library.recordings
            // Übersichten (ohne Ton) wiederholen nur, was in den Vorlesungen steht
            .filter { $0.categoryID == categoryID && $0.status == .done && $0.duration >= 1 }
            .sorted { $0.startedAt > $1.startedAt }
        for recording in recordings {
            guard let note = await library.summary(recording.id) else { continue }
            let items = ExamRadar.items(in: note.markdown)
            if !items.isEmpty { found.append((recording.id, note.title, recording.startedAt, items)) }
        }
        notes = found
        loaded = true
    }
}

extension View {
    /// Klausur-Radar als Blatt über dem Hauptfenster (eigener Baustein, damit der Fensteraufbau übersichtlich bleibt)
    func examRadarSheet(categoryID: Binding<UUID?>, onOpen: @escaping (UUID) -> Void) -> some View {
        sheet(item: Binding(get: { categoryID.wrappedValue.map(IdentifiableID.init) },
                            set: { categoryID.wrappedValue = $0?.id })) { wrapped in
            ExamRadarSheet(categoryID: wrapped.id, onOpen: onOpen)
        }
    }
}
