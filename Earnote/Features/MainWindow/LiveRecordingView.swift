import EarnoteCore
import SwiftUI

/// Laufende Aufnahme im Detail: Laufzeit, Pegel, Mikrofon, Live-Mitschrift, Pause und Stopp. Bewusst schlicht.
struct LiveRecordingView: View {
    @Environment(RecordingController.self) private var recorder
    let recording: LibraryRecording

    var body: some View {
        LiveRecordingContent(meter: recorder.meter, live: recorder.live, recording: recording,
                             isPaused: recorder.isPaused, microphoneName: recorder.microphoneName,
                             onTogglePause: recorder.togglePause, onStop: recorder.stopRecording)
    }
}

private struct LiveRecordingContent: View {
    @ObservedObject var meter: LiveMeter
    @ObservedObject var live: LiveTranscript
    let recording: LibraryRecording
    let isPaused: Bool
    let microphoneName: String?
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(recording: recording)
            HStack(alignment: .firstTextBaseline) {
                Label(isPaused ? "Pausiert" : "Aufnahme läuft", systemImage: isPaused ? "pause.circle.fill" : "record.circle")
                    .foregroundStyle(isPaused ? Color.secondary : Color.red)
                Spacer()
                Text(TimeFormat.duration(meter.elapsed))
                    .font(.title2.monospacedDigit())
                    .accessibilityLabel("Laufzeit \(TimeFormat.duration(meter.elapsed))")
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Mikrofon").foregroundStyle(.secondary)
                    LevelGauge(level: meter.mic, label: "Pegel Mikrofon")
                }
                GridRow {
                    Text("Systemton").foregroundStyle(.secondary)
                    LevelGauge(level: meter.system, label: "Pegel Systemton")
                }
                if let microphoneName {
                    GridRow {
                        Text("Gerät").foregroundStyle(.secondary)
                        Text(microphoneName).lineLimit(1)
                    }
                }
            }
            HStack {
                Button(isPaused ? "Fortsetzen" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill", action: onTogglePause)
                Button("Stopp", systemImage: "stop.fill", action: onStop)
            }
            Divider()
            Text("Live-Mitschrift")
                .font(.headline)
            if live.isEmpty {
                Text(live.unavailable ?? "Sobald jemand spricht, erscheint hier die Live-Mitschrift.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    liveText
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .defaultScrollAnchor(.bottom)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveText: Text {
        Text(live.settled) + Text(live.settled.isEmpty ? "" : " ") + Text(live.volatile).foregroundColor(.secondary)
    }
}

/// Pegel als native Anzeige (Dezibel-Skala)
private struct LevelGauge: View {
    let level: Float
    let label: String

    var body: some View {
        // Ohne eigenes Label: die Zeile davor sagt schon, welcher Pegel gemeint ist.
        Gauge(value: MainWindowFormat.level(level)) { EmptyView() }
            .gaugeStyle(.linearCapacity)
            .frame(maxWidth: 240)
            .accessibilityLabel(label)
            .accessibilityValue("\(Int(MainWindowFormat.level(level) * 100)) Prozent")
    }
}
