import EarnoteCore
import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var meter: LiveMeter

    var body: some View {
        if app.isRecording {
            HStack(spacing: 4) {
                Image(systemName: app.isPaused ? "pause.circle.fill" : "record.circle.fill")
                Text(TimeFormat.duration(meter.elapsed)).monospacedDigit()
            }
        } else if app.recordings.contains(where: { $0.status.isBusy }) {
            Image(systemName: "waveform.badge.magnifyingglass")
        } else {
            Image(systemName: "waveform")
        }
    }
}

/// Das Fenster aus der Menüleiste: aufnehmen, sehen was läuft, ins Hauptfenster wechseln.
/// Bewusst schmal (300 pt) – lange Bereichs- und Mikrofonnamen werden gekürzt, nie umgebrochen.
struct MenuBarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Environment(\.openWindow) private var openWindow

    private static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            RecordControl(categoryID: library.settings.defaultCategoryID, maxNameLength: 26)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            if recorder.isRecording {
                LiveSummary(meter: recorder.meter, isPaused: recorder.isPaused,
                            categoryName: activeCategoryName)
            } else {
                MicrophoneChoiceMenu(maxNameLength: 26)
                    .labelsHidden()
            }
            Divider()
            Button("Hauptfenster öffnen") { MainWindowOpener.showOrOpen(openWindow) }
                .buttonStyle(.link)
            HStack {
                SettingsLink { Text("Einstellungen …") }
                    .buttonStyle(.link)
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
            }
        }
        .lineLimit(1)
        .padding(14)
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack {
            Label(AppInfo.name, systemImage: "waveform")
                .font(.headline)
            Spacer()
            if let call = recorder.detector.activeCallApp, !recorder.isRecording {
                Text(call)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeCategoryName: String? {
        guard let id = recorder.activeRecordingID, let recording = library.recording(id) else { return nil }
        return library.category(recording.categoryID)?.name
    }
}

/// Während der Aufnahme: Laufzeit, Pegel und Bereich – kompakt.
private struct LiveSummary: View {
    @ObservedObject var meter: LiveMeter
    let isPaused: Bool
    let categoryName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isPaused ? "Pausiert" : "Aufnahme läuft")
                    .font(.subheadline)
                    .foregroundStyle(isPaused ? .secondary : .primary)
                Spacer()
                Text(TimeFormat.duration(meter.elapsed))
                    .font(.title3.monospacedDigit())
            }
            Gauge(value: MainWindowFormat.level(max(meter.mic, meter.system))) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .opacity(isPaused ? 0.4 : 1)
                .accessibilityLabel("Pegel")
            if let categoryName {
                Text(categoryName)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
