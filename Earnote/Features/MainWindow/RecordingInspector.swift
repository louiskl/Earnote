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
    @Environment(RecordingController.self) private var recorder
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
                ForEach(categories) { category in
                    Label {
                        Text(category.name)
                    } icon: {
                        CategoryBadge(emoji: category.emoji, symbol: category.symbol,
                                     tint: category.tint, size: 16)
                    }
                    .tag(Optional(category.id))
                }
            }
            .disabled(recording.status == .recording)
            LabeledContent("Datum", value: MainWindowFormat.dateAndTime(recording.startedAt))
            if recording.status == .recording {
                LabeledContent("Dauer") { LiveDurationText(meter: recorder.meter) }
            } else {
                LabeledContent("Dauer", value: MainWindowFormat.duration(recording.duration))
            }
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
        let targets = exportTargets(recording)
        let busy = recording.isBusy || recording.status == .recording
        return Section("Export") {
            if targets.isEmpty {
                Text("Kein Ziel eingeschaltet – die Notizen bleiben in \(AppInfo.name).")
                    .foregroundStyle(.secondary)
                SettingsLink { Text("Ziele einrichten …") }
            }
            ForEach(targets, id: \.id) { target in
                ExportRow(target: target, busy: busy,
                          onOpen: { if let url = target.url.flatMap(URL.init(string:)) { openURL(url) } },
                          onRetry: { library.reexport(recording.id, destinationID: target.id) })
            }
            if targets.count > 1 {
                Button("Alle Ziele erneut exportieren") { library.reexport(recording.id) }
                    .disabled(busy)
            }
        }
    }

    /// Alle Ziele dieser Aufnahme: die eingeschalteten (bzw. die des Bereichs) und dazu ältere Exporte,
    /// deren Ziel inzwischen ausgeschaltet ist.
    private func exportTargets(_ recording: LibraryRecording) -> [ExportTarget] {
        let settings = library.settings.destinations
        let category = recording.category?.snapshot()
        let activeIDs = (category?.destinationIDs.isEmpty == false ? category!.destinationIDs : settings.enabled)
        let exports = Dictionary((recording.exports ?? []).map { ($0.destinationID, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = activeIDs.union(exports.keys)
        return Destinations.all.filter { ids.contains($0.id) }.map { info in
            ExportTarget(id: info.id, name: info.name, export: exports[info.id],
                         isActive: activeIDs.contains(info.id),
                         setupProblem: Destinations.setupProblem(info.id, settings))
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
        if recording.origin == .importedFile { return String(localized: "Importierte Audiodatei") }
        return recording.sourceApp ?? String(localized: "Mikrofon")
    }

    private func noteAuthor(_ recording: LibraryRecording) -> String {
        guard let note = recording.note else { return "–" }
        return [note.provider, note.modelName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Laufzeit der laufenden Aufnahme; aktualisiert sich selbst, ohne den ganzen Inspector neu zu zeichnen.
private struct LiveDurationText: View {
    @ObservedObject var meter: LiveMeter

    var body: some View {
        Text(TimeFormat.duration(meter.elapsed)).monospacedDigit()
    }
}

/// Ein Ziel mit seinem Stand für diese Aufnahme
private struct ExportTarget: Identifiable {
    let id: String
    let name: String
    let export: LibraryExport?
    /// Ziel ist eingeschaltet (sonst bleibt nur der alte Stand stehen)
    let isActive: Bool
    /// Ziel ist eingeschaltet, aber noch nicht fertig eingerichtet
    let setupProblem: String?

    var url: String? { export?.externalURL }

    var state: ExportState? { export?.state }

    var detail: String? {
        if !isActive { return String(localized: "Ziel ist ausgeschaltet") }
        if let setupProblem { return setupProblem }
        guard let export else { return String(localized: "Noch nicht exportiert") }
        return export.state == .success ? nil : export.message
    }

    var stateText: String {
        guard isActive else { return "ausgeschaltet" }
        switch state {
        case .success: return "exportiert"
        case .skipped: return "übersprungen"
        case .failed: return "fehlgeschlagen"
        case nil: return setupProblem == nil ? "noch nicht exportiert" : "nicht eingerichtet"
        }
    }
}

private struct ExportRow: View {
    let target: ExportTarget
    let busy: Bool
    let onOpen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if target.url != nil {
                    Button("Öffnen", action: onOpen).controlSize(.small)
                }
                if target.isActive {
                    if target.setupProblem != nil {
                        SettingsLink { Text("Einrichten …") }
                            .controlSize(.small)
                    } else {
                        Button(target.state == .success ? "Erneut" : "Exportieren", action: onRetry)
                            .controlSize(.small)
                            .disabled(busy)
                    }
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                    if let detail = target.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(target.setupProblem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                            .lineLimit(2)
                    }
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(target.name): \(target.stateText)")
    }

    private var symbol: String {
        guard target.isActive else { return "circle.dashed" }
        if target.setupProblem != nil { return "exclamationmark.circle" }
        switch target.state {
        case .success: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case nil: return "circle"
        }
    }

    private var color: Color {
        guard target.isActive else { return .secondary }
        if target.setupProblem != nil { return .orange }
        switch target.state {
        case .success: return .green
        case .failed: return .orange
        case .skipped, nil: return .secondary
        }
    }
}
