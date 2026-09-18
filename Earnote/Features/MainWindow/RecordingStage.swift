import EarnoteCore
import SwiftUI

/// Die Aufnahme-Bühne: Man soll sehen, dass die App gerade zuhört – Status, Laufzeit, Wellenform,
/// Live-Mitschrift und die zwei Knöpfe. Hintergrund bleibt der des Fensters, keine Karte, kein Verlauf.
struct RecordingStageView: View {
    @Environment(RecordingController.self) private var recorder
    let recording: LibraryRecording

    var body: some View {
        StageContent(meter: recorder.meter, live: recorder.live,
                     isPaused: recorder.isPaused,
                     microphoneName: recorder.microphoneName,
                     systemAudio: recorder.isCapturingSystemAudio,
                     onTogglePause: recorder.togglePause,
                     onStop: recorder.stopRecording)
    }
}

private struct StageContent: View {
    @ObservedObject var meter: LiveMeter
    @ObservedObject var live: LiveTranscript
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPaused: Bool
    let microphoneName: String?
    let systemAudio: Bool
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Status, Laufzeit und Pegel sind für VoiceOver eine Einheit
            VStack(spacing: 20) {
                StatusLabel(isPaused: isPaused, reduceMotion: reduceMotion)
                ElapsedTime(meter: meter)
                StageWaveform(meter: meter, isPaused: isPaused, reduceMotion: reduceMotion)
                    .frame(height: 64)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenState)
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            controls
            source
        }
        .frame(maxWidth: 720)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private var spokenState: String {
        [isPaused ? "Pausiert" : "Aufnahme läuft",
         TimeFormat.spoken(meter.elapsed),
         "Pegel \(LevelBuffer.loudness(Float(MainWindowFormat.level(meter.mic))))"].joined(separator: ", ")
    }

    @ViewBuilder private var transcript: some View {
        if let unavailable = live.unavailable {
            Text(unavailable)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if live.isEmpty {
            Text("Sobald jemand spricht, erscheint hier die Mitschrift.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            LiveText(settled: live.settled, volatile: live.volatile, reduceMotion: reduceMotion)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(isPaused ? "Fortsetzen" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill",
                   action: onTogglePause)
            Button("Stopp", systemImage: "stop.fill", action: onStop)
                .tint(.red)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
    }

    private var source: some View {
        Text([microphoneName ?? "Mikrofon", systemAudio ? "mit Systemton" : nil].compactMap { $0 }
            .joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// „Aufnahme läuft“ mit ruhigem Pulsieren; pausiert ohne Bewegung.
private struct StatusLabel: View {
    let isPaused: Bool
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPaused ? Color.secondary : Color.red)
                .frame(width: 10, height: 10)
                .opacity(pulse && !isPaused && !reduceMotion ? 0.35 : 1)
                .animation(isPaused || reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                           value: pulse)
                .onAppear { pulse = true }
            Text(isPaused ? "Pausiert" : "Aufnahme läuft")
                .font(.headline)
                .foregroundStyle(isPaused ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Laufzeit groß – eigene kleine Ansicht, damit nur sie neu gezeichnet wird.
private struct ElapsedTime: View {
    @ObservedObject var meter: LiveMeter

    var body: some View {
        Text(TimeFormat.duration(meter.elapsed))
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .accessibilityLabel("Laufzeit \(TimeFormat.duration(meter.elapsed))")
    }
}

/// Wellenform: neue Pegel kommen rechts an, alte wandern nach links. Zeichnet nur sich selbst neu.
private struct StageWaveform: View {
    @ObservedObject var meter: LiveMeter
    let isPaused: Bool
    let reduceMotion: Bool
    @Environment(\.categoryTint) private var tint

    @State private var mic = LevelBuffer(capacity: 52)
    @State private var system = LevelBuffer(capacity: 52)
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if reduceMotion {
                // Ohne Bewegung: ruhige Pegelanzeige statt wandernder Balken
                VStack(spacing: 10) {
                    Gauge(value: MainWindowFormat.level(meter.mic)) { EmptyView() }
                    Gauge(value: MainWindowFormat.level(meter.system)) { EmptyView() }
                }
                .gaugeStyle(.linearCapacity)
            } else {
                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    draw(in: context, size: size)
                }
                .onReceive(tick) { _ in
                    guard !isPaused else { return }
                    mic.append(Float(MainWindowFormat.level(meter.mic)))
                    system.append(Float(MainWindowFormat.level(meter.system)))
                }
            }
        }
        .opacity(isPaused ? 0.4 : 1)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let count = mic.values.count
        let step = size.width / CGFloat(count)
        let barWidth = max(2, step * 0.55)
        let middle = size.height / 2
        for index in 0..<count {
            let x = CGFloat(index) * step + (step - barWidth) / 2
            bar(context, x: x, width: barWidth, middle: middle, maxHeight: size.height,
                level: system.values[index], color: .secondary.opacity(0.35))
            bar(context, x: x, width: barWidth, middle: middle, maxHeight: size.height,
                level: mic.values[index], color: tint)
        }
    }

    private func bar(_ context: GraphicsContext, x: CGFloat, width: CGFloat, middle: CGFloat,
                     maxHeight: CGFloat, level: Float, color: Color) {
        let height = max(width, CGFloat(level) * maxHeight)
        let rect = CGRect(x: x, y: middle - height / 2, width: width, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
    }
}

/// Live-Mitschrift: der feststehende Teil in normaler Farbe, der vorläufige in Grau.
/// Neuer Text blendet weich ein (außer bei „Bewegung reduzieren“).
private struct LiveText: View {
    let settled: String
    let volatile: String
    let reduceMotion: Bool

    /// Nur die letzten Zeilen zeigen; nach oben wird es ruhig ausgeblendet.
    private var tail: String {
        let text = settled.isEmpty ? "" : settled
        return String(text.suffix(600))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                (Text(tail) + Text(tail.isEmpty || volatile.isEmpty ? "" : " ")
                    + Text(volatile).foregroundColor(.secondary))
                    .font(.title3)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: settled)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: volatile)
                    .textSelection(.enabled)
                Color.clear.frame(height: 1).id("ende")
            }
        }
        .defaultScrollAnchor(.bottom)
        .accessibilityLabel("Mitschrift")
        .accessibilityValue(settled + " " + volatile)
    }
}
