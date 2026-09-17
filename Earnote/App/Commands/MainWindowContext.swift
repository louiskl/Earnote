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
    var requestDelete: () -> Void
    var requestDiscardRecording: () -> Void
    var newCategory: () -> Void
    var focusSearch: () -> Void
}

extension FocusedValues {
    @Entry var mainWindow: MainWindowContext?
}
