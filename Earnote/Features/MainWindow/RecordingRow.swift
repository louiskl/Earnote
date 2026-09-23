import EarnoteCore
import SwiftUI

/// Eine Zeile der Aufnahmeliste: Titel, darunter Uhrzeit · Dauer · Bereich (oder Verarbeitungsschritt), optional Vorschau.
struct RecordingRow: View {
    let recording: LibraryRecording
    /// Nur in „Alle Aufnahmen“: Name und Farbe des Bereichs
    let categoryName: String?
    let categoryTint: Color?
    let progress: Double?
    let isLive: Bool
    let isRenaming: Bool
    let onRename: (String) -> Void
    let onCancelRename: () -> Void

    @Environment(RecordingController.self) private var recorder
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isLive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
                if isRenaming {
                    TextField("Titel", text: $draft)
                        .focused($focused)
                        .onSubmit { onRename(draft) }
                        .onExitCommand(perform: onCancelRename)
                        .onAppear { draft = recording.title; focused = true }
                } else {
                    Text(recording.displayTitle)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if recording.status == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(recording.errorMessage ?? "Fehler bei der Verarbeitung")
                        .accessibilityLabel("Problem")
                }
            }
            secondaryLine
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // Immer drei Zeilen, wie in Mail: Kommt die Vorschau erst später dazu (Notiz fertig), misst die Liste
            // die Zeile nicht neu – sie blieb dann abgeschnitten, bis man die Spalte verbreiterte.
            let preview = isLive ? nil : recording.note?.preview.flatMap { $0.isEmpty ? nil : $0 }
            Text(preview ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(preview == nil)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var secondaryLine: some View {
        if isLive {
            LiveElapsedText(meter: recorder.meter, isPaused: recorder.isPaused)
        } else if recording.isBusy {
            HStack(spacing: 6) {
                Text(recording.status.label)
                ProgressView(value: progress ?? 0)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .frame(maxWidth: 80)
                    .accessibilityLabel("Fortschritt")
                    .accessibilityValue("\(Int((progress ?? 0) * 100)) Prozent")
            }
        } else {
            HStack(spacing: 5) {
                // Übersichten haben keine Laufzeit – statt „0 Sek.“ steht dort, was sie sind
                Text([MainWindowFormat.time(recording.startedAt),
                      recording.duration < 1 ? String(localized: "Übersicht") : MainWindowFormat.duration(recording.duration)]
                    .joined(separator: " · "))
                if let categoryName {
                    if let categoryTint { CategoryDot(tint: categoryTint) }
                    Text(categoryName)
                }
            }
            .lineLimit(1)
        }
    }
}

/// Laufzeit der laufenden Aufnahme (aktualisiert sich selbst, ohne die ganze Liste neu zu zeichnen)
struct LiveElapsedText: View {
    @ObservedObject var meter: LiveMeter
    let isPaused: Bool

    var body: some View {
        Text("\(isPaused ? "Pausiert" : "Aufnahme läuft") · \(TimeFormat.duration(meter.elapsed))")
            .monospacedDigit()
    }
}
