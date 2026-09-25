import EarnoteCore
import SwiftUI

/// Fragen zur Notiz (Earnote Pro): ein Gespräch mit der KI über diese eine Aufnahme – wie in Nachrichten,
/// unten das Eingabefeld. Das Gespräch lebt nur, solange das Blatt offen ist; Wichtiges übernimmt man in die Notiz.
struct NoteChatView: View {
    let id: UUID
    let note: Summary
    let transcript: Transcript?
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [NoteChat.Message] = []
    @State private var question = ""
    @State private var answering = false
    @State private var error: String?
    @State private var showsPro = false
    @State private var saved: Set<UUID> = []
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        [String(localized: "Erklär mir den schwierigsten Teil einfacher."),
         String(localized: "Was davon kommt wahrscheinlich in der Prüfung?"),
         String(localized: "Gib mir ein Beispiel dazu.")]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty { intro }
                        ForEach(messages) { message in
                            MessageRow(message: message, saved: saved.contains(message.id)) {
                                takeOver(message)
                            }
                            .id(message.id)
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.text) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Fragen zur Notiz")
            .navigationSubtitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .sheet(isPresented: $showsPro) { ProSheet(highlight: .chat) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frag nach, was du nicht verstanden hast. Die KI kennt die Notiz und sucht die passenden Stellen der Aufnahme heraus.")
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    Text(suggestion).multilineTextAlignment(.leading)
                }
                .buttonStyle(.bordered)
            }
            ProTriesNote(feature: .chat)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Deine Frage", text: $question, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                .onSubmit { send(question) }
            Button {
                send(question)
            } label: {
                if answering {
                    ProgressView().frame(width: 22, height: 22)
                } else {
                    Image(systemName: "arrow.up").fontWeight(.semibold).frame(width: 22, height: 22)
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(answering || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Senden")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !answering else { return }
        // Ein Gespräch zählt als ein Versuch – nicht jede einzelne Frage
        if messages.isEmpty, !Pro.use(.chat) {
            showsPro = true
            return
        }
        let client: any LLMClient
        do {
            guard let made = try library.llm.make(library.settings.ai) else {
                error = String(localized: "Für Fragen braucht es eine KI auf diesem Gerät. Wähle sie in den Einstellungen unter „So entsteht die Notiz“.")
                return
            }
            client = made
        } catch {
            self.error = error.localizedDescription
            return
        }
        error = nil
        question = ""
        let history = messages
        messages.append(NoteChat.Message(fromUser: true, text: text))
        messages.append(NoteChat.Message(fromUser: false, text: ""))
        let index = messages.count - 1
        answering = true
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
            await library.waitForPendingWrites()
            guard let latest = await library.summary(id) else { return }
            library.updateSummaryText(id, markdown: latest.markdown + NoteChat.markdown(question: messages[i - 1].text, answer: answer.text))
            saved.insert(answer.id)
        }
    }
}

/// Eine Nachricht: eigene Fragen rechts im Akzent, Antworten links als Text mit Markdown
private struct MessageRow: View {
    let message: NoteChat.Message
    let saved: Bool
    let takeOver: () -> Void

    var body: some View {
        if message.fromUser {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(.tint, in: .rect(cornerRadius: 18))
                    .textSelection(.enabled)
            }
        } else if message.text.isEmpty {
            ProgressView().padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                NoteContentView(markdown: message.text) { _ in }
                    .textSelection(.enabled)
                Button(saved ? "In der Notiz" : "In Notiz übernehmen",
                       systemImage: saved ? "checkmark" : "text.append", action: takeOver)
                    .font(.footnote)
                    .disabled(saved)
            }
        }
    }
}
