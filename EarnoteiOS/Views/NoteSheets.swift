import EarnoteCore
import SwiftUI

// Blätter aus dem Menü „Mehr“ einer Notiz. Bewusst wenige: „Neu schreiben …“ fasst Vereinfachen, Neu zusammenfassen und
// die KI-Fassung zusammen, „Namen korrigieren …“ Begriffe und Sprecher (ROADMAP Regel 4: höchstens 8 Einträge).

/// Notiz von Hand bearbeiten (Markdown). Die KI-Fassung bleibt erhalten und lässt sich wiederherstellen.
struct NoteEditor: View {
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

/// „Neu schreiben …“: einfacher, mit eigener Anweisung oder noch einmal – dazu die KI-Fassung zurückholen
struct RewriteSheet: View {
    let id: UUID
    var onRestore: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.simpler
    @State private var instruction = ""
    @State private var retranscribe = false

    enum Kind: Hashable { case simpler, custom, again }

    private var isEdited: Bool { library.recording(id)?.isNoteEdited == true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Wie?", selection: $kind) {
                        Text("Einfacher und kürzer").tag(Kind.simpler)
                        Text("Mit eigener Anweisung").tag(Kind.custom)
                        Text("Noch einmal wie vorher").tag(Kind.again)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if kind == .custom {
                        TextField("z. B. „Mehr Beispiele“ oder „Nur die Formeln“", text: $instruction, axis: .vertical)
                            .lineLimit(2...5)
                    }
                } footer: {
                    Text("Die KI schreibt die Notiz neu. Die bisherige wird ersetzt.")
                }
                if library.hasAudio(id) {
                    Section {
                        Toggle("Auch neu transkribieren", isOn: $retranscribe)
                    } footer: {
                        Text("Hilft, wenn im Transkript viel falsch verstanden wurde. Dauert länger.")
                    }
                }
                if isEdited {
                    Section {
                        Button("Auf KI-Fassung zurücksetzen", systemImage: "arrow.uturn.backward") {
                            library.restoreGeneratedNote(id)
                            dismiss()
                            onRestore()
                        }
                    } footer: {
                        Text("Holt die Notiz zurück, wie die KI sie geschrieben hat. Deine Änderungen gehen dabei verloren.")
                    }
                }
            }
            .navigationTitle("Neu schreiben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starten", action: start)
                        .disabled(kind == .custom && instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func start() {
        switch kind {
        case .simpler:
            // Aus der Notiz statt aus dem Transkript – schneller, und nichts Neues kommt hinzu
            library.reprocess(id, retranscribe: retranscribe, instruction: String(localized: "Erkläre die Inhalte einfacher und kürzer."),
                              fromNote: !retranscribe)
        case .custom:
            library.reprocess(id, retranscribe: retranscribe, instruction: instruction)
        case .again:
            library.reprocess(id, retranscribe: retranscribe)
        }
        dismiss()
    }
}

/// „Namen korrigieren …“: falsch verstandene Begriffe ersetzen und – mit Sprechererkennung – Stimmen benennen
struct NamesSheet: View {
    let id: UUID
    let transcript: Transcript?
    let note: Summary?
    /// Sprecher erkennen lassen (Earnote Pro) – läuft nach dem Schließen in der Notiz weiter
    var detectSpeakers: (() -> Void)?
    var onDone: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pro.key) private var isPro = false
    @State private var wrong = ""
    @State private var right = ""
    @State private var remember = true
    @State private var names: [String: String] = [:]

    private var speakers: [String] { transcript.map(Speakers.names) ?? [] }
    private var hasTerm: Bool { !wrong.trimmed.isEmpty && !right.trimmed.isEmpty }
    private var hasNames: Bool { names.values.contains { !$0.trimmed.isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Falsch, z. B. „Eigen Werte“", text: $wrong)
                    TextField("Richtig, z. B. „Eigenwerte“", text: $right)
                    Toggle("Ins Wörterbuch aufnehmen", isOn: $remember)
                } header: {
                    Text("Begriff ersetzen")
                } footer: {
                    Text("Gilt in Titel, Notiz und Transkript. Im Wörterbuch schreibt Earnote den Begriff auch künftig richtig.")
                }
                speakerSection
            }
            .autocorrectionDisabled()
            .navigationTitle("Namen korrigieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }.disabled(!hasTerm && !hasNames)
                }
            }
        }
    }

    @ViewBuilder private var speakerSection: some View {
        if !speakers.isEmpty {
            Section {
                ForEach(speakers, id: \.self) { speaker in
                    LabeledContent(speaker) {
                        TextField("Name", text: Binding(get: { names[speaker] ?? "" }, set: { names[speaker] = $0 }))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                }
            } header: {
                Text("Sprecher")
            } footer: {
                Text("Wer „Sprecher 1“ ist, hörst du im Transkript: einfach auf eine Zeile tippen.")
            }
        } else if let detectSpeakers {
            Section {
                Button("Sprecher erkennen", systemImage: "person.2.wave.2") {
                    dismiss()
                    detectSpeakers()
                }
            } header: {
                Text("Sprecher")
            } footer: {
                Text(isPro ? "Earnote unterscheidet die Stimmen, danach kannst du ihnen hier Namen geben."
                           : "Earnote Pro · noch \(Pro.triesLeft(.speakers)) Aufnahmen kostenlos")
            }
        }
    }

    private func save() async {
        // Erst die Sprecher (schreibt das Transkript), dann der Begriff – sonst überschreiben sie sich gegenseitig
        if hasNames, let transcript {
            var result = transcript
            var markdown = note?.markdown ?? ""
            for (old, new) in names where !new.trimmed.isEmpty {
                (result, markdown) = Speakers.rename(old, to: new.trimmed, transcript: result, note: markdown)
            }
            await library.saveTranscript(id, result)
            if note != nil, markdown != note?.markdown { library.updateSummaryText(id, markdown: markdown) }
        }
        if hasTerm { library.correctTerm(id, wrong: wrong, right: right, remember: remember) }
        dismiss()
        onDone()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
