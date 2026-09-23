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
    /// Blättern durch die Fundstellen (⌘G) – nil, wenn das Transkript daneben steht und blättert
    var cursor: SearchCursor?

    /// Gerade abgehakter Stand, bis die Bibliothek ihn gespeichert zurückmeldet (verhindert Flackern)
    @State private var pendingMarkdown: String?
    /// Zu jeder Fundstelle der Block, in dem sie steht – in der Reihenfolge der Notiz
    @State private var hits: [Int] = []
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

    /// Neue Suche oder geänderte Notiz: Fundstellen zählen und zur ersten springen.
    /// Je Fundstelle ein Eintrag, damit ⌘G und die Zählung dasselbe meinen – wie im Transkript.
    private func updateHits(in markdown: String, _ proxy: ScrollViewProxy) {
        guard cursor != nil else { return }
        guard !SearchText.normalized(searchText).isEmpty else {
            hits = []
            cursor?.reset(count: 0)
            return
        }
        hits = NoteMarkdown.blocks(markdown).flatMap { block in
            Array(repeating: block.id, count: SearchText.ranges(in: block.plainText, query: searchText).count)
        }
        cursor?.reset(count: hits.count)
        scrollToHit(proxy)
    }

    private func scrollToHit(_ proxy: ScrollViewProxy) {
        let index = cursor?.index ?? 0
        guard hits.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(hits[index], anchor: .top) }
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        DetailHeader(recording: recording)
                            .padding(.bottom, 6)
                        if recording.isBusy || recording.status == .failed {
                            StatusLine(recording: recording)
                        }
                        ForEach(NoteSection.sections(markdown)) { section in
                            NoteSectionView(section: section, searchText: searchText) { line in
                                guard let updated = NoteMarkdown.togglingTask(in: markdown, line: line) else { return }
                                pendingMarkdown = updated
                                library.updateSummaryText(recording.id, markdown: updated)
                            }
                        }
                        NoteFooterActions(recording: recording) { editing = true }
                            .padding(.top, 18)
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: searchText, initial: true) { _, _ in updateHits(in: markdown, proxy) }
                .onChange(of: markdown) { _, text in updateHits(in: text, proxy) }
                // Weitersuchen (⌘G) zählt im Menü hoch, hier wird gescrollt
                .onChange(of: cursor?.index) { _, _ in scrollToHit(proxy) }
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
            if recording.status == .summarizing { LowPowerHint() }
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
        case .flashcard(_, let question, let answer):
            FlashcardTile(question: inline(question), answer: inline(answer), searching: !searchText.isEmpty)
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


/// Abschnitte gliedern die Notiz durch Abstand, ohne den Fließtext einzurahmen.
private struct NoteSection: Identifiable {
    let id: Int
    var blocks: [NoteBlock]
    static func sections(_ markdown: String) -> [Self] {
        var sections: [Self] = []
        for block in NoteMarkdown.blocks(markdown) {
            if case .heading(_, let level, _, _) = block, level <= 2 {
                sections.append(Self(id: block.id, blocks: [block]))
            } else if sections.isEmpty {
                sections.append(Self(id: block.id, blocks: [block]))
            } else {
                sections[sections.count - 1].blocks.append(block)
            }
        }
        return sections
    }
}

private struct FlashcardTile: View {
    let question: AttributedString
    let answer: AttributedString
    let searching: Bool
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question).font(.headline).textSelection(.enabled)
            if revealed || searching {
                Divider()
                Text(answer).textSelection(.enabled)
            }
            Button(revealed ? "Antwort ausblenden" : "Antwort anzeigen") { revealed.toggle() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(revealed ? "Antwort ausblenden" : "Antwort anzeigen")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.secondary.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct NoteSectionView: View {
    let section: NoteSection
    let searchText: String
    let onToggleTask: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(section.blocks) { block in
                NoteBlockView(block: block, searchText: searchText,
                              onToggleTask: onToggleTask)
                    .id(block.id)
            }
        }
        .padding(.top, section.id == 0 ? 0 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Ruhige Werkzeugleiste am Ende der Notiz; bei schmalen Fenstern umbrechend.
private struct NoteFooterActions: View {
    @Environment(LibraryStore.self) private var library
    let recording: LibraryRecording
    let edit: () -> Void
    @State private var simplifying = false

    private var makingCards: Bool { library.makingFlashcards.contains(recording.id) }
    private var busy: Bool { recording.isBusy || makingCards || recording.status == .recording }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                Button("Bearbeiten", systemImage: "pencil", action: edit)
                    .disabled(busy)
                Button("Karteikarten erzeugen", systemImage: "rectangle.on.rectangle") {
                    Task { await library.makeFlashcards(recording.id) }
                }
                .disabled(busy || library.settings.ai.provider == .none)
                Button("Vereinfachen", systemImage: "text.badge.minus") { simplifying = true }
                    .disabled(busy || library.settings.ai.provider == .none)
                Button("PDF sichern …", systemImage: "arrow.down.document") {
                    NoteDocument.savePDF(recording.id, library: library)
                }
                .disabled(busy)
                Button("Anki sichern …", systemImage: "square.and.arrow.down") {
                    FlashcardExport.save(recording.id, library: library)
                }
                .disabled(busy || (Flashcards.parse(recording.note?.markdown ?? "").isEmpty
                                  && library.settings.ai.provider == .none))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if makingCards {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Karteikarten entstehen …").font(.callout).foregroundStyle(.secondary)
                }
                LowPowerHint()
            }
        }
        .sheet(isPresented: $simplifying) {
            SummarizeAgainSheet(recordingID: recording.id,
                                initialInstruction: String(localized: "Erkläre den Inhalt in einfacher Sprache und kurzen Sätzen. Erkläre Fachbegriffe verständlich, bewahre wichtige Fakten und die Gliederung. Erfinde nichts hinzu."))
        }
    }
}

/// Der Stromsparmodus drosselt die Grafikeinheit, auf der die lokale KI rechnet – Notizen und
/// Karteikarten dauern dann ein Mehrfaches (gemessen: 83 s statt 352 s für dieselben Karteikarten).
/// Wer das nicht weiß, hält Earnote für langsam. Nur zeigen, während die lokale KI wirklich arbeitet.
private struct LowPowerHint: View {
    @Environment(PowerSource.self) private var power
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if power.isLowPowerMode, library.settings.ai.provider.isLocal {
            HStack(spacing: 8) {
                Label("Der Stromsparmodus ist an. Die KI braucht dadurch bis zu viermal so lang.",
                      systemImage: "tortoise")
                Button("Einstellungen öffnen …") { SystemSettingsLink.battery() }
                    .buttonStyle(.link)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
