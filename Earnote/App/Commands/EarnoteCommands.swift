import EarnoteCore
import SwiftUI

/// Menübefehle und Tastenkürzel. Befehle zur Auswahl wirken auf das Hauptfenster im Vordergrund
/// und sind ohne passende Auswahl deaktiviert.
struct EarnoteCommands: Commands {
    let library: LibraryStore
    let recorder: RecordingController
    let audioInputs: AudioInputDevices

    @FocusedValue(\.mainWindow) private var window

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Audiodatei importieren …") {
                let urls = AudioImportPanel.pick()
                library.importAudio(urls, category: window?.selectedCategoryID.flatMap(library.category))
            }
            .keyboardShortcut("o")
            Button("Neuer Bereich") { window?.newCategory() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(window == nil)
        }

        CommandMenu("Aufnahme") {
            // Der Zustand kommt aus dem vordersten Fenster (siehe `MainWindowContext`);
            // ohne offenes Fenster steht er auf „nimmt nicht auf“.
            let isRecording = window?.isRecording ?? false
            Button(isRecording ? "Aufnahme stoppen" : "Aufnahme starten") {
                if recorder.isRecording {
                    recorder.stopRecording()
                } else {
                    recorder.startRecording(category: window?.selectedCategoryID.flatMap(library.category))
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(window?.isPaused == true ? "Fortsetzen" : "Pause") { recorder.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!isRecording)
            Button("Aufnahme verwerfen …") { window?.requestDiscardRecording() }
                .disabled(!isRecording || window == nil)
            Divider()
            Button(window?.playback?.isPlaying == true ? "Pause" : "Aufnahme anhören") {
                window?.playback?.playPause()
            }
            .keyboardShortcut(.space, modifiers: .option)
            .disabled(window?.playback == nil)
            Button("15 Sekunden zurück") { window?.playback?.skip(-AudioPlayer.skipSeconds) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(window?.playback == nil)
            Button("15 Sekunden vor") { window?.playback?.skip(AudioPlayer.skipSeconds) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(window?.playback == nil)
            Divider()
            MicrophoneCommandPicker(library: library, audioInputs: audioInputs, isRecording: isRecording)
        }

        CommandMenu("Notiz") {
            let id = window?.selectedRecordingID
            let recording = id.flatMap(library.recording)
            let busy = recording?.status.isBusy == true || recording?.status == .recording
            Button("Notiz bearbeiten") { if let id { window?.noteActions.edit(id) } }
                .keyboardShortcut("e")
                .disabled(recording?.summaryTitle == nil || busy)
            Button("Auf KI-Fassung zurücksetzen") { window?.noteActions.restoreGenerated() }
                .disabled(recording?.isNoteEdited != true)
            Button("Namen & Begriffe korrigieren …") { window?.noteActions.correctTerms() }
                .disabled(recording?.summaryTitle == nil || busy)
            Divider()
            Button("Neu zusammenfassen …") { window?.noteActions.summarizeAgain() }
                .disabled(recording == nil || busy)
            Button("Neu transkribieren") { if let id { library.reprocess(id, retranscribe: true) } }
                .disabled(recording == nil || busy || !(id.map(library.hasAudio) ?? false))
            Button("Erneut exportieren") { if let id { library.reexport(id) } }
                .disabled(recording == nil || busy)
            Divider()
            Button(id.map { library.makingFlashcards.contains($0) } == true
                   ? "Karteikarten entstehen …" : "Karteikarten erzeugen") {
                if let id { Task { await library.makeFlashcards(id) } }
            }
            .disabled(recording?.summaryTitle == nil || busy
                      || id.map { library.makingFlashcards.contains($0) } == true)
            Button("Karteikarten sichern (Anki) …") { if let id { FlashcardExport.save(id, library: library) } }
                .disabled(recording?.summaryTitle == nil)
            Button("Als Mail weiterschicken …") { if let id { FollowUpMail.compose(id, library: library) } }
                .disabled(recording?.summaryTitle == nil)
            Divider()
            Button("Als PDF sichern …") { if let id { NoteDocument.savePDF(id, library: library) } }
                .disabled(recording?.summaryTitle == nil)
            Button("Drucken …") { if let id { NoteDocument.printNote(id, library: library) } }
                .keyboardShortcut("p")
                .disabled(recording?.summaryTitle == nil)
            Divider()
            Button("Teilen …") {
                guard let id, let recording else { return }
                Task {
                    if let note = await library.summary(id) {
                        SharePicker.show(NoteMarkdown.shareText(title: recording.displayTitle, markdown: note.markdown))
                    }
                }
            }
            .disabled(recording?.summaryTitle == nil)
            Button("Im Finder zeigen") { if let id { library.revealInFinder(id) } }
                .disabled(recording == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            // „Aufnahme löschen …“, damit es nicht mit dem „Löschen“ für Text verwechselt wird
            Button("Aufnahme löschen …") { window?.requestDelete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(window?.selectedRecordingID == nil || window?.isEditingText == true
                          || window?.selectedRecordingID == window?.activeRecordingID)
        }

        CommandGroup(after: .textEditing) {
            Button("Suchen") { window?.focusSearch() }
                .keyboardShortcut("f")
                .disabled(window == nil)
            Button("Weitersuchen") { window?.search?.next() }
                .keyboardShortcut("g")
                .disabled(window?.search == nil)
            Button("Rückwärts suchen") { window?.search?.previous() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(window?.search == nil)
        }

        CommandGroup(before: .sidebar) {
            Button("Notiz") { window?.detailMode.wrappedValue = .note }
                .keyboardShortcut("1")
                .disabled(window?.selectedRecordingID == nil)
            Button("Transkript") { window?.detailMode.wrappedValue = .transcript }
                .keyboardShortcut("2")
                .disabled(window?.selectedRecordingID == nil)
            Button("Notiz und Transkript") { window?.detailMode.wrappedValue = .both }
                .keyboardShortcut("3")
                .disabled(window?.selectedRecordingID == nil)
            Button((window?.inspectorShown.wrappedValue ?? false) ? "Inspector ausblenden" : "Inspector einblenden") {
                window?.inspectorShown.wrappedValue.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(window == nil)
            Divider()
        }
    }
}

/// Mikrofon ▸ im Menü „Aufnahme“ (mit Häkchen)
private struct MicrophoneCommandPicker: View {
    let library: LibraryStore
    let audioInputs: AudioInputDevices
    let isRecording: Bool

    var body: some View {
        Picker("Mikrofon", selection: Binding(get: { library.settings.microphoneDeviceUID }, set: { uid in
            library.settings.microphoneDeviceUID = uid
            library.settings.microphoneDeviceName = uid.flatMap { audioInputs.device($0)?.name }
        })) {
            Text("Systemstandard (\(audioInputs.defaultDevice?.name ?? "keins"))").tag(String?.none)
            ForEach(audioInputs.sorted) { Text($0.name).tag(Optional($0.uid)) }
            if let uid = library.settings.microphoneDeviceUID, audioInputs.device(uid) == nil {
                Text("\(library.settings.microphoneDeviceName ?? "Gewähltes Mikrofon") (nicht verbunden)").tag(Optional(uid))
            }
        }
        .disabled(isRecording)
    }
}
