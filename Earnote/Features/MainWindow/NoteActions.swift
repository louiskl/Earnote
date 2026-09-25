import EarnoteCore
import SwiftUI

/// Aktionen rund um die Notiz der gewählten Aufnahme. Das Fenster stellt sie bereit, damit Kontextmenü,
/// „⋯“-Menü und das Menü „Notiz“ dieselben Blätter öffnen.
struct NoteActions {
    /// Bearbeitet genau diese Aufnahme – auch wenn sie gerade nicht ausgewählt ist (Rechtsklick in der Liste)
    var edit: (UUID) -> Void = { _ in }
    var summarizeAgain: () -> Void = {}
    var correctTerms: () -> Void = {}
    var restoreGenerated: () -> Void = {}
    var ask: () -> Void = {}
    var translate: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var noteActions = NoteActions()
}

/// Blätter, die das Hauptfenster über der Notiz zeigt
enum NoteSheet: String, Identifiable {
    case summarizeAgain, correctTerms, ask, translate
    var id: String { rawValue }
}

/// Neu zusammenfassen – auf Wunsch mit anderem Bereich und einer zusätzlichen Anweisung.
struct SummarizeAgainSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let recordingID: UUID
    var initialInstruction = ""
    /// Vereinfachen: aus der bisherigen Notiz statt aus dem Transkript
    var fromNote = false

    @State private var categoryID: UUID?
    @State private var instruction = ""
    @State private var retranscribe = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Bereich", selection: $categoryID) {
                        Text("Ohne Bereich").tag(UUID?.none)
                        ForEach(library.categories) { Text("\($0.displayEmoji)  \($0.name)").tag(Optional($0.id)) }
                    }
                } footer: {
                    Text("Der Bereich bestimmt, worauf die KI achtet.")
                }
                Section {
                    TextField("Zusätzliche Anweisung", text: $instruction, prompt: Text("z. B. Kürzer fassen, Formeln hervorheben"),
                              axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Gilt nur für diesen Durchgang. Dauerhafte Hinweise gehören in den Bereich.")
                }
                if !fromNote { Section {
                    Toggle("Auch neu transkribieren", isOn: $retranscribe)
                        .disabled(!library.hasAudio(recordingID))
                } footer: {
                    Text(library.hasAudio(recordingID)
                         ? "Dauert länger, hilft aber, wenn das Transkript viele Fehler hat."
                         : "Die Audiodatei wurde bereits gelöscht.")
                } }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fromNote ? "Vereinfachen" : "Neu schreiben") {
                    library.setCategory(recordingID, categoryID)
                    library.reprocess(recordingID, retranscribe: retranscribe, instruction: instruction, fromNote: fromNote)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 380)
        .onAppear {
            categoryID = library.recording(recordingID)?.categoryID
            instruction = initialInstruction
        }
    }
}

/// „Namen korrigieren …“: einen falsch erkannten Begriff in Titel, Notiz und Transkript ersetzen – und, sobald die
/// Stimmen erkannt sind, „Sprecher 1, 2 …“ echte Namen geben (wie am iPhone).
struct CorrectTermSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.speakerDiarizer) private var diarizer
    let recordingID: UUID

    @State private var wrong = ""
    @State private var right = ""
    @State private var remember = true
    @State private var transcript: Transcript?
    @State private var names: [String: String] = [:]
    @State private var detecting = false
    @State private var detectionNote: String?

    /// Nur erkannte Stimmen – „Ich“/„Andere“ aus Calls benennt man nicht um
    private var speakers: [String] {
        (transcript.map(Speakers.names) ?? []).filter { $0 != "Ich" && $0 != "Andere" }
    }
    /// Stimmen lassen sich nur mit Ton und Transkript erkennen
    private var canDetect: Bool { diarizer != nil && transcript != nil && library.hasAudio(recordingID) }
    private var hasTerm: Bool { !wrong.trimmed.isEmpty && !right.trimmed.isEmpty }
    private var hasNames: Bool { names.values.contains { !$0.trimmed.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Falsch geschrieben", text: $wrong, prompt: Text("z. B. Professor Maier"))
                    TextField("Richtig", text: $right, prompt: Text("z. B. Professor Meyer"))
                    Toggle("Ins Wörterbuch aufnehmen", isOn: $remember)
                } header: {
                    Text("Begriff ersetzen")
                } footer: {
                    Text("Gilt in Titel, Notiz und Transkript. Im Wörterbuch schreibt Earnote den Begriff auch künftig richtig.")
                }
                speakerSection
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasTerm && !hasNames)
            }
            .padding(16)
        }
        .frame(width: 480, height: !speakers.isEmpty ? 480 : canDetect ? 430 : 330)
        .task { transcript = await library.transcript(recordingID) }
    }

    @ViewBuilder private var speakerSection: some View {
        if !speakers.isEmpty {
            Section {
                ForEach(speakers, id: \.self) { speaker in
                    TextField(speaker, text: Binding(get: { names[speaker] ?? "" }, set: { names[speaker] = $0 }),
                              prompt: Text("Name"))
                }
            } header: {
                Text("Sprecher")
            } footer: {
                Text("Wer „Sprecher 1“ ist, hörst du im Transkript: einfach auf eine Zeitmarke klicken.")
            }
        } else if canDetect {
            Section {
                HStack {
                    Button("Sprecher erkennen") { Task { await detect() } }
                        .disabled(detecting)
                    if detecting { ProgressView().controlSize(.small) }
                }
            } header: {
                Text("Sprecher")
            } footer: {
                Text(detectionNote ?? String(localized: "Earnote unterscheidet die Stimmen, danach kannst du ihnen hier Namen geben."))
            }
        }
    }

    /// Stimmen nachträglich erkennen, ins Transkript schreiben und die Notiz mit den Sprechern neu schreiben lassen
    private func detect() async {
        guard let diarizer, let transcript, let recording = library.recording(recordingID),
              let url = library.audio.playbackURL(for: recording) else { return }
        detecting = true
        defer { detecting = false }
        let result = await ProcessingPipeline.withSpeakers(transcript, audio: url, diarizer: diarizer)
        guard Speakers.names(in: result).count >= 2 else {
            detectionNote = String(localized: "Earnote hat in dieser Aufnahme nur eine Stimme erkannt.")
            return
        }
        await library.saveTranscript(recordingID, result)
        self.transcript = result
        library.reprocess(recordingID, retranscribe: false)
    }

    private func save() async {
        // Erst die Sprecher (schreibt das Transkript), dann der Begriff – sonst überschreiben sie sich gegenseitig
        if hasNames, let transcript {
            var result = transcript
            let note = await library.summary(recordingID)
            var markdown = note?.markdown ?? ""
            for (old, new) in names where !new.trimmed.isEmpty {
                (result, markdown) = Speakers.rename(old, to: new.trimmed, transcript: result, note: markdown)
            }
            await library.saveTranscript(recordingID, result)
            if note != nil, markdown != note?.markdown { library.updateSummaryText(recordingID, markdown: markdown) }
        }
        if hasTerm { library.correctTerm(recordingID, wrong: wrong, right: right, remember: remember) }
        dismiss()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
