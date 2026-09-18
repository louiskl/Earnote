import EarnoteCore
import SwiftData
import SwiftUI

/// Fenster-Toolbar: Aufnehmen (bzw. Pause/Stopp), Notiz/Transkript, Teilen, weitere Aktionen, Inspector.
struct MainToolbar: ToolbarContent {
    let selectedRecordingID: UUID?
    let selectedCategoryID: UUID?
    @Binding var detailMode: DetailMode
    @Binding var inspectorShown: Bool
    let onDelete: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            RecordControl(categoryID: selectedCategoryID)
        }
        ToolbarItem(placement: .principal) {
            Picker("Ansicht", selection: $detailMode) {
                Text("Notiz").tag(DetailMode.note)
                Text("Transkript").tag(DetailMode.transcript)
            }
            .pickerStyle(.segmented)
            .disabled(selectedRecordingID == nil)
            .help("Notiz (⌘1) oder Transkript (⌘2)")
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

/// Aufnehmen mit Bereichs- und Mikrofonwahl; während der Aufnahme Pause und Stopp mit Laufzeit.
private struct RecordControl: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Query(sort: [SortDescriptor(\LibraryCategory.sortIndex), SortDescriptor(\LibraryCategory.createdAt)])
    private var categories: [LibraryCategory]
    let categoryID: UUID?

    var body: some View {
        if recorder.isRecording {
            ControlGroup {
                Button {
                    recorder.togglePause()
                } label: {
                    Label(recorder.isPaused ? "Fortsetzen" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                }
                .help(recorder.isPaused ? "Aufnahme fortsetzen (⇧⌘P)" : "Aufnahme pausieren (⇧⌘P)")
                Button {
                    recorder.stopRecording()
                } label: {
                    StopLabel(meter: recorder.meter)
                }
                .help("Aufnahme stoppen (⇧⌘R)")
            }
        } else {
            Menu {
                Section("Aufnehmen in") {
                    ForEach(categories) { category in
                        Button("\(category.displayEmoji) \(category.name)") {
                            recorder.startRecording(category: library.category(category.id))
                        }
                    }
                }
                Divider()
                MicrophoneChoiceMenu()
            } label: {
                // Mit Text: verständlicher als ein Symbol allein, und VoiceOver liest nicht
                // den Symbolnamen („Bildschirmaufnahme“) vor.
                Label("Aufnehmen", systemImage: "record.circle")
                    .labelStyle(.titleAndIcon)
            } primaryAction: {
                recorder.startRecording(category: categoryID.flatMap(library.category))
            }
            .menuIndicator(.visible)
            .help("Aufnahme starten (⇧⌘R)")
            .accessibilityLabel("Aufnehmen")
        }
    }
}

private struct StopLabel: View {
    @ObservedObject var meter: LiveMeter

    var body: some View {
        Label("Stopp \(TimeFormat.duration(meter.elapsed))", systemImage: "stop.fill")
            .labelStyle(.titleAndIcon)
            .monospacedDigit()
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

/// Mikrofonwahl als Menü (Toolbar und Menü „Aufnahme“), Häkchen am gewählten Eintrag
struct MicrophoneChoiceMenu: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioInputDevices.self) private var inputs
    @Environment(RecordingController.self) private var recorder

    var body: some View {
        Picker("Mikrofon", selection: Binding(get: { library.settings.microphoneDeviceUID }, set: { uid in
            library.settings.microphoneDeviceUID = uid
            library.settings.microphoneDeviceName = uid.flatMap { inputs.device($0)?.name }
        })) {
            Text("Systemstandard (\(inputs.defaultDevice?.name ?? "keins"))").tag(String?.none)
            ForEach(inputs.sorted) { device in
                Text(device.name).tag(Optional(device.uid))
            }
            if let uid = library.settings.microphoneDeviceUID, inputs.device(uid) == nil {
                Text("\(library.settings.microphoneDeviceName ?? "Gewähltes Mikrofon") (nicht verbunden)").tag(Optional(uid))
            }
        }
        .pickerStyle(.menu)
        .disabled(recorder.isRecording)
    }
}
