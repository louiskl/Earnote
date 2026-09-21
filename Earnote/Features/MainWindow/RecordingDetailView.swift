import EarnoteCore
import SwiftData
import SwiftUI

/// Detailbereich: Notiz oder Transkript der gewählten Aufnahme, bei laufender Aufnahme die Aufnahmeansicht.
struct RecordingDetailView: View {
    let recordingID: UUID?
    let mode: DetailMode
    /// Aufnahme, deren Notiz bearbeitet werden soll – als Wert, damit die Änderung sicher unten ankommt
    let editRequest: UUID?
    let onEditStarted: () -> Void
    /// Laufende Suche – Fundstellen werden hervorgehoben, das Transkript springt zur ersten
    let searchText: String
    /// Blättern durch die Fundstellen (⌘G) – das Transkript meldet und bedient sie
    let searchCursor: SearchCursor

    var body: some View {
        if let recordingID {
            RecordingDetailContent(recordingID: recordingID, mode: mode,
                                   editRequest: editRequest, onEditStarted: onEditStarted,
                                   searchText: searchText, searchCursor: searchCursor)
                .id(recordingID)
        } else {
            ContentUnavailableView("Keine Aufnahme ausgewählt", systemImage: "waveform",
                                   description: Text("Wähle in der Liste eine Aufnahme aus."))
        }
    }
}

private struct RecordingDetailContent: View {
    @Environment(RecordingController.self) private var recorder
    @Query private var matches: [LibraryRecording]
    let mode: DetailMode
    let editRequest: UUID?
    let onEditStarted: () -> Void
    let searchText: String
    let searchCursor: SearchCursor

    init(recordingID: UUID, mode: DetailMode, editRequest: UUID?, onEditStarted: @escaping () -> Void,
         searchText: String, searchCursor: SearchCursor) {
        _matches = Query(filter: #Predicate<LibraryRecording> { $0.id == recordingID })
        self.mode = mode
        self.editRequest = editRequest
        self.onEditStarted = onEditStarted
        self.searchText = searchText
        self.searchCursor = searchCursor
    }

    var body: some View {
        if let recording = matches.first {
            if recorder.activeRecordingID == recording.id {
                RecordingStageView()
            } else {
                switch mode {
                case .note:
                    note(recording)
                case .transcript:
                    transcript(recording)
                case .both:
                    // Nebeneinander: die Breite teilt der Nutzer selbst auf (natives NSSplitView)
                    HSplitView {
                        note(recording)
                            .frame(minWidth: 260)
                        transcript(recording)
                            .frame(minWidth: 260)
                    }
                }
            }
        } else {
            ContentUnavailableView("Aufnahme nicht gefunden", systemImage: "questionmark.folder")
        }
    }

    private func note(_ recording: LibraryRecording) -> some View {
        NoteView(recording: recording, editRequest: editRequest, onEditStarted: onEditStarted,
                 searchText: searchText)
    }

    private func transcript(_ recording: LibraryRecording) -> some View {
        // Nebeneinander folgt das Transkript dem Ton: ein Klick auf eine Zeitmarke in der Notiz
        // spielt die Stelle – und das Transkript scrollt mit.
        // Nebeneinander steht der Titel schon über der Notiz – einmal reicht.
        TranscriptView(recording: recording, searchText: searchText, cursor: searchCursor,
                       followsPlayback: mode == .both, showsHeader: mode != .both)
    }
}

/// Kopf über Notiz und Transkript: Titel und eine sekundäre Zeile
struct DetailHeader: View {
    let recording: LibraryRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.displayTitle)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 5) {
                // Während der Aufnahme steht die Laufzeit direkt darunter; hier wäre sie nur doppelt.
                Text(([MainWindowFormat.dateAndTime(recording.startedAt)]
                      + (recording.status == .recording ? [] : [MainWindowFormat.duration(recording.duration)]))
                    .joined(separator: " · "))
                if let category = recording.category {
                    CategoryDot(tint: category.tint)
                    Text(category.name)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Verarbeitung läuft oder ist fehlgeschlagen – als Hinweis im Detail
struct ProcessingStateView: View {
    @Environment(ProcessingQueue.self) private var queue
    @Environment(LibraryStore.self) private var library
    let recording: LibraryRecording

    var body: some View {
        if recording.isBusy {
            ContentUnavailableView {
                Label(recording.status.label, systemImage: "gearshape.2")
            } description: {
                ProgressView(value: queue.progress[recording.id] ?? 0)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Fortschritt")
            }
        } else if recording.status == .failed {
            ContentUnavailableView {
                Label("Verarbeitung fehlgeschlagen", systemImage: "exclamationmark.triangle")
            } description: {
                Text(recording.errorMessage ?? "Unbekannter Fehler")
            } actions: {
                Button("Erneut versuchen") { library.enqueue(recording.id) }
            }
        }
    }
}
