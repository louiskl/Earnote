import AppKit
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
            Button("Übersicht über den Bereich …") { window?.summarizeCategory?() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(window?.summarizeCategory == nil)
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
            Toggle("Systemton mitaufnehmen", isOn: Binding(
                get: { window?.recordSystemAudio ?? library.settings.recordSystemAudio },
                set: { library.settings.recordSystemAudio = $0 }))
                .disabled(isRecording)
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
            Button("Namen korrigieren …") { window?.noteActions.correctTerms() }
                .disabled(recording?.summaryTitle == nil || busy)
            Divider()
            Button("Fragen zur Notiz …") { window?.noteActions.ask() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(recording?.summaryTitle == nil || busy)
            Button("Übersetzen …") { window?.noteActions.translate() }
                .disabled(recording?.summaryTitle == nil || busy)
            Divider()
            Button("Neu schreiben …") { window?.noteActions.summarizeAgain() }
                .disabled(recording == nil || busy)
            Button("Neu transkribieren") { if let id { library.reprocess(id, retranscribe: true) } }
                .disabled(recording == nil || busy || !(id.map(library.hasAudio) ?? false))
            Button("Erneut exportieren") { if let id { library.reexport(id) } }
                .disabled(recording == nil || busy)
            Divider()
            // Untermenüs halten das Menü kurz – wie „Notiz“ in Mail oder „Format“ in Pages
            Menu("Karteikarten") {
                Button(id.map { library.makingFlashcards.contains($0) } == true ? "Karteikarten entstehen …" : "Erzeugen") {
                    if let id { Task { await library.makeFlashcards(id) } }
                }
                .disabled(recording?.summaryTitle == nil || busy
                          || id.map { library.makingFlashcards.contains($0) } == true)
                Button("Als Anki-Datei sichern …") { if let id { FlashcardExport.save(id, library: library) } }
                    .disabled(recording?.summaryTitle == nil)
            }
            .disabled(recording?.summaryTitle == nil)
            Menu("Weitergeben") {
                Button("Kurzprotokoll kopieren") { if let id { ShortMinutes.copy(id, library: library) } }
                Button("Als Mail weiterschicken …") { if let id { FollowUpMail.compose(id, library: library) } }
                Button("Kurzprotokoll als Mail …") { if let id { FollowUpMail.compose(id, library: library, short: true) } }
                Button("Teilen …") {
                    guard let id, let recording else { return }
                    Task {
                        if let note = await library.summary(id) {
                            SharePicker.show(NoteMarkdown.shareText(title: recording.displayTitle, markdown: note.markdown))
                        }
                    }
                }
            }
            .disabled(recording?.summaryTitle == nil)
            Divider()
            Button("Als PDF sichern …") { if let id { NoteDocument.savePDF(id, library: library) } }
                .disabled(recording?.summaryTitle == nil)
            Button("Drucken …") { if let id { NoteDocument.printNote(id, library: library) } }
                .keyboardShortcut("p")
                .disabled(recording?.summaryTitle == nil)
            Divider()
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

        // Apples Platzhalter „Earnote-Hilfe“ führt ins Leere – hier stehen die Wege, die es wirklich gibt.
        CommandGroup(replacing: .help) {
            Button("Earnote-Hilfe") { NSWorkspace.shared.open(AppInfo.website) }
            Button("Anleitung für Beta-Tester") { NSWorkspace.shared.open(AppInfo.betaGuide) }
            Divider()
            Button("Fehler melden …") { NSWorkspace.shared.open(Diagnostics.issueURL()) }
            Button("Datenschutz") { NSWorkspace.shared.open(AppInfo.privacyPage) }
            Divider()
            Button("Quelltext auf GitHub") { NSWorkspace.shared.open(AppInfo.repository) }
            Divider()
            // Weitersagen ist, wie Earnote zu Kommilitonen kommt – ohne Werbung, ohne Nachfragen in der App
            Button("Earnote empfehlen …") { Recommendation.share() }
            Button("Earnote unterstützen …") { NSWorkspace.shared.open(AppInfo.sponsor) }
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
                Text("\(library.settings.microphoneDeviceName ?? String(localized: "Gewähltes Mikrofon")) (nicht verbunden)").tag(Optional(uid))
            }
        }
        .disabled(isRecording)
    }
}
