import AppKit
import EarnoteCore
import SwiftData
import SwiftUI

/// Eigenschaften der gewählten Aufnahme: Info, Verarbeitung, Export, Audio.
struct RecordingInspector: View {
    let recordingID: UUID?

    var body: some View {
        if let recordingID {
            InspectorContent(recordingID: recordingID)
                .id(recordingID)
        } else {
            ContentUnavailableView("Keine Auswahl", systemImage: "info.circle")
        }
    }
}

private struct InspectorContent: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ProcessingQueue.self) private var queue
    @Environment(\.openURL) private var openURL
    @Query private var matches: [LibraryRecording]
    @Query(sort: [SortDescriptor(\LibraryCategory.sortIndex), SortDescriptor(\LibraryCategory.createdAt)])
    private var categories: [LibraryCategory]
    @State private var confirmAudioDeletion = false

    init(recordingID: UUID) {
        _matches = Query(filter: #Predicate<LibraryRecording> { $0.id == recordingID })
    }

    var body: some View {
        if let recording = matches.first {
            Form {
                infoSection(recording)
                processingSection(recording)
                exportSection(recording)
                audioSection(recording)
            }
            .formStyle(.grouped)
            .confirmationDialog("Audio dieser Aufnahme löschen?", isPresented: $confirmAudioDeletion) {
                Button("Audio löschen", role: .destructive) { library.deleteAudio(recording.id) }
            } message: {
                Text("Transkript und Notiz bleiben erhalten. Neu transkribieren ist danach nicht mehr möglich.")
            }
        } else {
            ContentUnavailableView("Keine Auswahl", systemImage: "info.circle")
        }
    }

    private func infoSection(_ recording: LibraryRecording) -> some View {
        Section("Info") {
            Picker("Bereich", selection: Binding(get: { recording.category?.id },
                                                 set: { library.setCategory(recording.id, $0) })) {
                Text("Ohne Bereich").tag(UUID?.none)
                ForEach(categories) { Text("\($0.displayEmoji) \($0.name)").tag(Optional($0.id)) }
            }
            .disabled(recording.status == .recording)
            LabeledContent("Datum", value: MainWindowFormat.dateAndTime(recording.startedAt))
            LabeledContent("Dauer", value: MainWindowFormat.duration(recording.duration))
            LabeledContent("Quelle", value: source(recording))
            LabeledContent("Sprache", value: MainWindowFormat.language(recording.languageCode))
        }
    }

    private func processingSection(_ recording: LibraryRecording) -> some View {
        Section("Verarbeitung") {
            LabeledContent("Transkription", value: recording.transcript?.engine ?? "–")
            LabeledContent("Notiz erstellt mit", value: noteAuthor(recording))
            LabeledContent("Status") {
                if recording.isBusy {
                    HStack(spacing: 6) {
                        Text(recording.status.label)
                        ProgressView(value: queue.progress[recording.id] ?? 0)
                            .controlSize(.small)
                            .frame(width: 60)
                    }
                } else {
                    Text(recording.status.label)
                        .foregroundStyle(recording.status == .failed ? .orange : .secondary)
                        .help(recording.errorMessage ?? "")
                }
            }
        }
    }

    private func exportSection(_ recording: LibraryRecording) -> some View {
        Section("Export") {
            let exports = (recording.exports ?? []).sorted { $0.destinationName < $1.destinationName }
            if exports.isEmpty {
                Text("Noch nicht exportiert").foregroundStyle(.secondary)
            }
            ForEach(exports, id: \.persistentModelID) { export in
                ExportRow(export: export) { if let url = export.externalURL.flatMap(URL.init(string:)) { openURL(url) } }
            }
            Button("Erneut exportieren") { library.reexport(recording.id) }
                .disabled(recording.isBusy || recording.status == .recording)
        }
    }

    private func audioSection(_ recording: LibraryRecording) -> some View {
        Section("Audio") {
            Button("Im Finder zeigen") { library.revealInFinder(recording.id) }
            Button("Audio löschen …", role: .destructive) { confirmAudioDeletion = true }
                .disabled(!library.hasAudio(recording.id) || recording.isBusy || recording.status == .recording)
        }
    }

    private func source(_ recording: LibraryRecording) -> String {
        if recording.origin == .importedFile { return "Importierte Audiodatei" }
        return recording.sourceApp ?? "Mikrofon"
    }

    private func noteAuthor(_ recording: LibraryRecording) -> String {
        guard let note = recording.note else { return "–" }
        return [note.provider, note.modelName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct ExportRow: View {
    let export: LibraryExport
    let onOpen: () -> Void

    var body: some View {
        LabeledContent {
            if export.externalURL != nil {
                Button("Öffnen", action: onOpen)
                    .controlSize(.small)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(export.destinationName)
                    if export.state != .success {
                        Text(export.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
        }
        .help(export.message)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(export.destinationName): \(stateText)")
    }

    private var symbol: String {
        switch export.state {
        case .success: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch export.state {
        case .success: return .green
        case .skipped: return .secondary
        case .failed: return .orange
        }
    }

    private var stateText: String {
        switch export.state {
        case .success: return "exportiert"
        case .skipped: return "übersprungen"
        case .failed: return "fehlgeschlagen"
        }
    }
}
