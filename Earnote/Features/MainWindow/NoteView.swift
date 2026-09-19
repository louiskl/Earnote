import EarnoteCore
import SwiftUI

/// Die Notiz als gegliederter Text: Kurzfassung, Themen als Überschriften, Aufgaben als Checkboxen.
struct NoteView: View {
    @Environment(LibraryStore.self) private var library
    let recording: LibraryRecording
    /// Anfrage aus dem Menü: Ist sie diese Aufnahme, geht der Editor auf.
    let editRequest: UUID?
    /// Die Anfrage ist angekommen und darf zurückgesetzt werden
    let onEditStarted: () -> Void
    /// Laufende Suche: Fundstellen in der Notiz hervorheben
    var searchText = ""

    /// Gerade abgehakter Stand, bis die Bibliothek ihn gespeichert zurückmeldet (verhindert Flackern)
    @State private var pendingMarkdown: String?
    /// Der Editor gehört dieser Ansicht – Abbrechen und Sichern wirken damit sofort, egal was außen passiert.
    @State private var editing = false

    var body: some View {
        content
            // Anfrage aus dem Menü entgegennehmen – auch wenn sie gestellt wurde, bevor diese Ansicht da war
            .onChange(of: editRequest, initial: true) { _, request in
                guard request == recording.id else { return }
                editing = true
                onEditStarted()
            }
    }

    @ViewBuilder private var content: some View {
        if let note = recording.note {
            let markdown = pendingMarkdown ?? note.markdown
            if editing {
                NoteEditor(markdown: markdown) { edited in
                    editing = false
                    guard let edited, edited != markdown else { return }
                    pendingMarkdown = edited
                    library.updateSummaryText(recording.id, markdown: edited)
                }
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    DetailHeader(recording: recording)
                        .padding(.bottom, 6)
                    if recording.isBusy || recording.status == .failed {
                        StatusLine(recording: recording)
                    }
                    ForEach(NoteMarkdown.blocks(markdown)) { block in
                        NoteBlockView(block: block, searchText: searchText) { line in
                            guard let updated = NoteMarkdown.togglingTask(in: markdown, line: line) else { return }
                            pendingMarkdown = updated
                            library.updateSummaryText(recording.id, markdown: updated)
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: note.markdown) { _, stored in
                if stored == pendingMarkdown { pendingMarkdown = nil }
            }
            }
        } else if recording.isBusy || recording.status == .failed {
            ProcessingStateView(recording: recording)
        } else if library.settings.ai.provider == .none {
            ContentUnavailableView {
                Label("Keine Notiz", systemImage: "doc.text")
            } description: {
                Text("Zusammenfassungen sind ausgeschaltet. Wähle in den Einstellungen unter „KI“, wer die Notizen schreibt.")
            } actions: {
                SettingsLink { Text("Einstellungen öffnen") }
            }
        } else {
            ContentUnavailableView {
                Label("Keine Notiz", systemImage: "doc.text")
            } description: {
                Text("Für diese Aufnahme gibt es noch keine Notiz.")
            } actions: {
                Button("Neu zusammenfassen") { library.reprocess(recording.id, retranscribe: false) }
                    .disabled(recording.status == .recording)
            }
        }
    }
}

/// Kurzer Hinweis über der Notiz, wenn sie gerade neu entsteht oder etwas schiefging
private struct StatusLine: View {
    @Environment(ProcessingQueue.self) private var queue
    let recording: LibraryRecording

    var body: some View {
        if recording.isBusy {
            HStack(spacing: 8) {
                Text(recording.status.label)
                ProgressView(value: queue.progress[recording.id] ?? 0)
                    .frame(maxWidth: 160)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            Label(recording.errorMessage ?? "Verarbeitung fehlgeschlagen", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}

/// Ein Block der Notiz in Systemtypografie
private struct NoteBlockView: View {
    let block: NoteBlock
    let searchText: String
    let onToggleTask: (Int) -> Void

    var body: some View {
        switch block {
        case .paragraph(_, let text):
            Text(inline(text))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(_, let level, let text, let timestamp):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(inline(text))
                    .font(level == 3 ? .headline : .title3.weight(.semibold))
                if let timestamp {
                    TimestampButton(seconds: TimeFormat.seconds(timestamp), label: timestamp)
                }
            }
            .textSelection(.enabled)
            .padding(.top, level == 3 ? 4 : 10)
            .accessibilityAddTraits(.isHeader)
        case .bullet(_, let text, let indent):
            listItem(marker: "•", text: text, indent: indent)
        case .numbered(_, let number, let text, let indent):
            listItem(marker: "\(number).", text: text, indent: indent)
        case .task(_, let text, let isDone, let line):
            Toggle(isOn: Binding(get: { isDone }, set: { _ in onToggleTask(line) })) {
                Text(inline(text))
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(text)
            .accessibilityValue(isDone ? "erledigt" : "offen")
        case .quote(_, let text):
            Text(inline(text))
                .italic()
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .textSelection(.enabled)
        }
    }

    private func listItem(marker: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(inline(text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(indent) * 18)
        .textSelection(.enabled)
    }

    /// Fett, kursiv und Code innerhalb einer Zeile – und die Fundstellen der Suche
    private func inline(_ text: String) -> AttributedString {
        SearchHighlight.attributed(text, query: searchText, inlineMarkdown: true)
    }
}


/// Notiz bearbeiten: der Text, wie er gespeichert ist. Überschriften beginnen mit „## “,
/// Aufgaben mit „- [ ] “ – alles andere ist gewöhnlicher Text.
private struct NoteEditor: View {
    let markdown: String
    /// nil = abgebrochen
    let onDone: (String?) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $draft)
                .font(.body)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            HStack {
                Text("Überschrift: ## · Aufgabe: - [ ]")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen") { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") { onDone(draft) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onAppear { draft = markdown; focused = true }
    }
}
