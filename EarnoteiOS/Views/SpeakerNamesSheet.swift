import EarnoteCore
import SwiftUI

/// Sprecher benennen (Earnote Pro): aus „Sprecher 1“ wird „Prof. Klein“ – im Transkript und in der Notiz
struct SpeakerNamesSheet: View {
    let id: UUID
    let transcript: Transcript
    let note: Summary?
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]

    private var speakers: [String] { Speakers.names(in: transcript) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(speakers, id: \.self) { speaker in
                        LabeledContent(speaker) {
                            TextField("Name", text: Binding(get: { names[speaker] ?? "" }, set: { names[speaker] = $0 }))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                    }
                } footer: {
                    Text("Tipp: Im Transkript hörst du dir an, wer „Sprecher 1“ ist – einfach auf eine Zeile tippen.")
                }
            }
            .navigationTitle("Sprecher benennen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(names.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }
        }
    }

    private func save() async {
        var result = transcript
        var markdown = note?.markdown ?? ""
        for (old, new) in names {
            (result, markdown) = Speakers.rename(old, to: new, transcript: result, note: markdown)
        }
        await library.saveTranscript(id, result)
        if note != nil, markdown != note?.markdown { library.updateSummaryText(id, markdown: markdown) }
        dismiss()
    }
}
