import SwiftUI

/// Was die Menüleiste im vordersten Fenster auslösen darf (iPadOS 26 zeigt die Menüleiste; am iPhone unsichtbar)
struct PhoneActions {
    var showSettings: () -> Void
    var importAudio: () -> Void
    var search: () -> Void
}

extension FocusedValues {
    @Entry var phoneActions: PhoneActions?
}

/// Menüs und Tastenkürzel wie am Mac (Earnote/App/Commands/EarnoteCommands.swift) – dieselben Kürzel,
/// damit man zwischen Mac und iPad mit Tastatur nicht umlernen muss.
struct PhoneCommands: Commands {
    let recorder: PhoneRecorder
    @FocusedValue(\.phoneActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen …") { actions?.showSettings() }
                .keyboardShortcut(",")
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .newItem) {
            Button("Audiodatei importieren …") { actions?.importAudio() }
                .keyboardShortcut("o")
                .disabled(actions == nil)
        }
        CommandMenu("Aufnahme") {
            Button(recorder.isRecording ? "Aufnahme stoppen" : "Aufnahme starten") {
                if recorder.isRecording { recorder.stop() } else { Task { await recorder.start(category: nil) } }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(recorder.isPaused ? "Fortsetzen" : "Pause") { recorder.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!recorder.isRecording)
        }
        CommandGroup(after: .textEditing) {
            Button("Suchen") { actions?.search() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
        }
    }
}
