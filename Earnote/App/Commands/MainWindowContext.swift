import EarnoteCore
import SwiftUI

/// Was die Menübefehle über das aktive Hauptfenster wissen müssen. Jedes Fenster stellt seinen eigenen
/// Zustand bereit (`focusedSceneValue`), so beziehen sich Befehle immer auf das Fenster im Vordergrund.
struct MainWindowContext {
    var selectedRecordingID: UUID?
    /// Bereich der Seitenleiste, falls einer gewählt ist (neue Aufnahmen und Importe landen dort)
    var selectedCategoryID: UUID?
    var detailMode: Binding<DetailMode>
    var inspectorShown: Binding<Bool>
    /// Ein Textfeld (Suche, Umbenennen) hat den Fokus – dann nicht mit ⌘⌫ löschen
    var isEditingText: Bool
    /// Zustand der Aufnahme. Er kommt über das Fenster, weil `Commands` Änderungen an den
    /// Stores selbst nicht mitbekommt und die Menütitel sonst veraltet wären.
    var isRecording: Bool
    var isPaused: Bool
    /// Systemton bei der nächsten Aufnahme mitnehmen (über das Fenster, damit das Häkchen im Menü aktuell bleibt)
    var recordSystemAudio: Bool
    var activeRecordingID: UUID?
    var requestDelete: () -> Void
    var requestDiscardRecording: () -> Void
    var newCategory: () -> Void
    /// Übersicht über den gewählten Bereich (nil = kein Bereich gewählt oder zu wenige Aufnahmen)
    var summarizeCategory: (() -> Void)?
    /// Klausur-Radar des gewählten Bereichs (nil = kein Bereich gewählt)
    var examRadar: (() -> Void)?
    var focusSearch: () -> Void
    /// Notiz bearbeiten, neu zusammenfassen, korrigieren, zurücksetzen
    var noteActions = NoteActions()
    /// Anhören der gewählten Aufnahme (nil = keine Audiodatei)
    var playback: PlaybackCommands?
    /// Durch die Fundstellen der Suche blättern (nil = gerade keine Fundstellen)
    var search: SearchNavigation?
}

/// Weitersuchen und zurück (⌘G, ⇧⌘G)
struct SearchNavigation {
    var next: () -> Void = {}
    var previous: () -> Void = {}
}

/// Abspielen aus der Menüleiste heraus
struct PlaybackCommands {
    var isPlaying = false
    var playPause: () -> Void = {}
    var skip: (TimeInterval) -> Void = { _ in }
}

extension FocusedValues {
    @Entry var mainWindow: MainWindowContext?
}
