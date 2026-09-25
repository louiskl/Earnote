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
}

extension EnvironmentValues {
    @Entry var noteActions = NoteActions()
}

/// Blätter, die das Hauptfenster über der Notiz zeigt
enum NoteSheet: String, Identifiable {
    case summarizeAgain, correctTerms
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

/// Einen falsch erkannten Namen oder Begriff in Titel, Notiz und Transkript ersetzen.
struct CorrectTermSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let recordingID: UUID

    @State private var wrong = ""
    @State private var right = ""
    @State private var remember = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Falsch geschrieben", text: $wrong, prompt: Text("z. B. Professor Maier"))
                    TextField("Richtig", text: $right, prompt: Text("z. B. Professor Meyer"))
                } footer: {
                    Text("Die Ersetzung gilt für Titel, Notiz und Transkript dieser Aufnahme. Groß- und Kleinschreibung ist egal.")
                }
                Section {
                    Toggle("Ins Wörterbuch aufnehmen", isOn: $remember)
                } footer: {
                    Text("Dann kennt \(AppInfo.name) den Begriff bei künftigen Aufnahmen und schreibt ihn gleich richtig.")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ersetzen") {
                    library.correctTerm(recordingID, wrong: wrong, right: right, remember: remember)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(wrong.trimmingCharacters(in: .whitespaces).isEmpty
                          || right.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 340)
    }
}
