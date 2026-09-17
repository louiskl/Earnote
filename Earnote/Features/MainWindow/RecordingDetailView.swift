import EarnoteCore
import SwiftData
import SwiftUI

/// Detailbereich: Notiz oder Transkript der gewählten Aufnahme, bei laufender Aufnahme die Aufnahmeansicht.
struct RecordingDetailView: View {
    let recordingID: UUID?
    let mode: DetailMode

    var body: some View {
        if let recordingID {
            RecordingDetailContent(recordingID: recordingID, mode: mode)
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

    init(recordingID: UUID, mode: DetailMode) {
        _matches = Query(filter: #Predicate<LibraryRecording> { $0.id == recordingID })
        self.mode = mode
    }

    var body: some View {
        if let recording = matches.first {
            if recorder.activeRecordingID == recording.id {
                LiveRecordingView(recording: recording)
            } else {
                switch mode {
                case .note: NoteView(recording: recording)
                case .transcript: TranscriptView(recording: recording)
                }
            }
        } else {
            ContentUnavailableView("Aufnahme nicht gefunden", systemImage: "questionmark.folder")
        }
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
            Text(([MainWindowFormat.dateAndTime(recording.startedAt), TimeFormat.duration(recording.duration)]
                  + [recording.category?.name].compactMap { $0 }).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
