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
    var activeRecordingID: UUID?
    var requestDelete: () -> Void
    var requestDiscardRecording: () -> Void
    var newCategory: () -> Void
    var focusSearch: () -> Void
    /// Notiz bearbeiten, neu zusammenfassen, korrigieren, zurücksetzen
    var noteActions = NoteActions()
}

extension FocusedValues {
    @Entry var mainWindow: MainWindowContext?
}
