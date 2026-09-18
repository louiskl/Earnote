import EarnoteCore
import SwiftData
import SwiftUI

/// Aufnahmeliste der gewählten Bibliothek bzw. des Bereichs, nach Tagen gruppiert.
struct RecordingListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Environment(ProcessingQueue.self) private var queue
    @Query(sort: \LibraryRecording.startedAt, order: .reverse) private var recordings: [LibraryRecording]
    @Query(sort: [SortDescriptor(\LibraryCategory.sortIndex), SortDescriptor(\LibraryCategory.createdAt)])
    private var categories: [LibraryCategory]

    let filter: LibraryFilter
    @Binding var selection: UUID?
    /// nil = keine Suche aktiv
    let searchResults: Set<UUID>?
    let searchText: String
    @Binding var renamingID: UUID?
    let onDelete: (UUID) -> Void

    var body: some View {
        let visible = recordings.filter { filter.matches($0) && (searchResults?.contains($0.id) ?? true) }
        Group {
            if visible.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(LibraryListing.groupedByDay(visible)) { section in
                        Section(section.title) {
                            ForEach(section.items) { recording in
                                row(recording)
                            }
                        }
                    }
                }
                .onKeyPress(.return) {
                    guard renamingID == nil, let selection else { return .ignored }
                    renamingID = selection
                    return .handled
                }
            }
        }
        .navigationTitle(title)
        // Gewählte Aufnahme ist nicht (mehr) in der Liste – anderer Bereich, Suche, gelöscht
        // oder ein gespeicherter Fensterzustand, der nicht zu dieser Bibliothek passt.
        .onChange(of: visible.map(\.id), initial: true) { _, ids in pruneSelection(ids) }
        .onChange(of: selection, initial: true) { _, _ in pruneSelection(visible.map(\.id)) }
        .dropDestination(for: URL.self) { urls, _ in
            library.importAudio(urls, category: categoryID.flatMap(library.category))
            return !urls.isEmpty
        }
    }

    private func pruneSelection(_ ids: [UUID]) {
        if let selection, !ids.contains(selection) { self.selection = nil }
    }

    private func row(_ recording: LibraryRecording) -> some View {
        RecordingRow(recording: recording,
                     categoryName: filter == .all ? recording.category?.name : nil,
                     categoryTint: filter == .all ? recording.category?.tint : nil,
                     progress: queue.progress[recording.id],
                     isLive: recorder.activeRecordingID == recording.id,
                     isRenaming: renamingID == recording.id,
                     onRename: { library.rename(recording.id, to: $0); renamingID = nil },
                     onCancelRename: { renamingID = nil })
            .tag(recording.id)
            .contextMenu {
                Button("Umbenennen") { renamingID = recording.id }
                Menu("Bereich") {
                    Picker("Bereich", selection: Binding(get: { recording.category?.id },
                                                         set: { library.setCategory(recording.id, $0) })) {
                        Text("Ohne Bereich").tag(UUID?.none)
                        ForEach(categories) { Text("\($0.displayEmoji) \($0.name)").tag(Optional($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Divider()
                RecordingActionItems(recordingID: recording.id)
                Divider()
                Button("Löschen …", role: .destructive) { onDelete(recording.id) }
            }
    }

    private var categoryID: UUID? {
        if case .category(let id) = filter { return id }
        return nil
    }

    private var title: String {
        switch filter {
        case .all: return "Alle Aufnahmen"
        case .openTasks: return "Offene Aufgaben"
        case .uncategorized: return "Ohne Bereich"
        case .problems: return "Probleme"
        case .category(let id): return categories.first { $0.id == id }?.name ?? "Bereich"
        }
    }

    @ViewBuilder private var emptyState: some View {
        if searchResults != nil {
            ContentUnavailableView.search(text: searchText)
        } else {
            switch filter {
            case .all:
                ContentUnavailableView("Noch keine Aufnahmen", systemImage: "waveform",
                                       description: Text("Starte eine mit ⇧⌘R oder ziehe eine Audiodatei hierher."))
            case .openTasks:
                ContentUnavailableView("Keine offenen Aufgaben", systemImage: "checklist",
                                       description: Text("Aufgaben aus deinen Notizen erscheinen hier, bis sie abgehakt sind."))
            case .uncategorized:
                ContentUnavailableView("Alles zugeordnet", systemImage: "tray",
                                       description: Text("Jede Aufnahme gehört zu einem Bereich."))
            case .problems:
                ContentUnavailableView("Keine Probleme", systemImage: "checkmark.circle")
            case .category:
                ContentUnavailableView("Noch keine Aufnahmen in diesem Bereich", systemImage: "waveform",
                                       description: Text("Starte eine mit ⇧⌘R oder ziehe eine Audiodatei hierher."))
            }
        }
    }
}

/// Aktionen für eine Aufnahme – gleich im Kontextmenü, im „⋯“-Menü der Toolbar und im Menü „Notiz“.
struct RecordingActionItems: View {
    @Environment(LibraryStore.self) private var library
    let recordingID: UUID

    var body: some View {
        let recording = library.recording(recordingID)
        let busy = recording?.status.isBusy == true || recording?.status == .recording
        Button("Neu zusammenfassen") { library.reprocess(recordingID, retranscribe: false) }
            .disabled(recording == nil || busy)
        Button("Neu transkribieren") { library.reprocess(recordingID, retranscribe: true) }
            .disabled(recording == nil || busy || !library.hasAudio(recordingID))
        Button("Erneut exportieren") { library.reexport(recordingID) }
            .disabled(recording == nil || busy)
        Button("Im Finder zeigen") { library.revealInFinder(recordingID) }
            .disabled(recording == nil)
    }
}
