import EarnoteCore
import SwiftData
import SwiftUI

/// Fenster-Toolbar: Aufnehmen (bzw. Pause/Stopp), Notiz/Transkript, Teilen, weitere Aktionen, Inspector.
struct MainToolbar: ToolbarContent {
    let selectedRecordingID: UUID?
    let selectedCategoryID: UUID?
    /// Übersicht über den gewählten Bereich (nil = ausgegraut)
    let onSummarize: (() -> Void)?
    /// Klausur-Radar des gewählten Bereichs
    let onExamRadar: (() -> Void)?
    @Binding var detailMode: DetailMode
    @Binding var inspectorShown: Bool
    let onDelete: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            RecordControl(categoryID: selectedCategoryID)
        }
        ToolbarItem(placement: .principal) {
            Picker("Ansicht", selection: $detailMode) {
                ForEach(DetailMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(selectedRecordingID == nil)
            .help("Notiz (⌘1), Transkript (⌘2) oder beides nebeneinander (⌘3)")
        }
        // Nur, wenn ein Bereich gewählt ist: Lernübersicht über seine Aufnahmen (sonst nur per Rechtsklick zu finden)
        if selectedCategoryID != nil {
            ToolbarItem(placement: .primaryAction) {
                Button { onSummarize?() } label: {
                    Label("Übersicht", systemImage: "list.bullet.rectangle")
                }
                .disabled(onSummarize == nil)
                .help(onSummarize == nil
                      ? "Für eine Übersicht braucht es mindestens zwei fertige Aufnahmen in diesem Bereich."
                      : "Übersicht über die Aufnahmen dieses Bereichs erstellen (⇧⌘U)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { onExamRadar?() } label: {
                    Label("Klausur-Radar", systemImage: "scope")
                }
                .help("Alles Prüfungsrelevante dieses Bereichs auf einer Seite (⌥⇧⌘U)")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            SelectionActions(recordingID: selectedRecordingID, onDelete: onDelete)
            Button {
                inspectorShown.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Inspector ein- oder ausblenden (⌥⌘I)")
        }
    }
}

/// Teilen und „⋯“ für die gewählte Aufnahme
private struct SelectionActions: View {
    let recordingID: UUID?
    let onDelete: () -> Void

    var body: some View {
        if let recordingID {
            SelectedRecordingActions(recordingID: recordingID, onDelete: onDelete)
        } else {
            Button {} label: { Label("Teilen", systemImage: "square.and.arrow.up") }
                .disabled(true)
            Menu {} label: { Label("Weitere Aktionen", systemImage: "ellipsis.circle") }
                .disabled(true)
        }
    }
}

private struct SelectedRecordingActions: View {
    @Query private var matches: [LibraryRecording]
    let onDelete: () -> Void

    init(recordingID: UUID, onDelete: @escaping () -> Void) {
        _matches = Query(filter: #Predicate<LibraryRecording> { $0.id == recordingID })
        self.onDelete = onDelete
    }

    var body: some View {
        let recording = matches.first
        if let note = recording?.note, let recording {
            ShareLink(item: NoteMarkdown.shareText(title: recording.displayTitle, markdown: note.markdown),
                      subject: Text(recording.displayTitle)) {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
            .help("Notiz teilen")
        } else {
            Button {} label: { Label("Teilen", systemImage: "square.and.arrow.up") }
                .disabled(true)
                .help("Teilen ist möglich, sobald es eine Notiz gibt")
        }
        Menu {
            if let recording {
                RecordingActionItems(recordingID: recording.id)
                Divider()
                Button("Löschen …", role: .destructive, action: onDelete)
                    .disabled(recording.status == .recording)
            }
        } label: {
            Label("Weitere Aktionen", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .help("Weitere Aktionen")
    }
}
