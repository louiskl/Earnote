import EarnoteCore
import SwiftUI

/// Die laufende Aufnahme groß: Laufzeit, Pegel, Pause und Stopp. Schließen lässt die Aufnahme weiterlaufen.
struct RecordSheet: View {
    @Environment(PhoneRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                if let name = recorder.categoryName {
                    Text(name).font(.headline).foregroundStyle(.secondary)
                }
                ElapsedText()
                    .font(.system(size: 64, weight: .light).monospacedDigit())
                    .accessibilityLabel("Laufzeit")
                LevelMeter()
                    .frame(height: 44)
                    .padding(.horizontal, 32)
                if recorder.isInterrupted {
                    Label("Pausiert wegen eines Anrufs", systemImage: "phone.fill")
                        .foregroundStyle(.secondary)
                } else if recorder.isPaused {
                    Label("Pausiert", systemImage: "pause.fill").foregroundStyle(.secondary)
                } else {
                    Text("Du kannst das iPhone sperren – Earnote nimmt weiter auf.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
                HStack(spacing: 20) {
                    Button { recorder.togglePause() } label: {
                        Label(recorder.isPaused ? "Fortsetzen" : "Pause",
                              systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        recorder.stop()
                        dismiss()
                    } label: {
                        Label("Stopp", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .padding(.horizontal)
                .sensoryFeedback(.impact, trigger: recorder.isPaused)
            }
            .padding(.bottom)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "chevron.down") { dismiss() }
                }
            }
            .onChange(of: recorder.isRecording) { _, recording in if !recording { dismiss() } }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Pegel als ruhige Balken, zehnmal pro Sekunde abgefragt; ruht, wenn pausiert
private struct LevelMeter: View {
    @Environment(PhoneRecorder.self) private var recorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var history = Array(repeating: Float(0), count: 32)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            HStack(alignment: .center, spacing: 3) {
                ForEach(history.indices, id: \.self) { i in
                    Capsule()
                        .fill(.tint)
                        .frame(height: max(4, CGFloat(history[i]) * 44))
                }
            }
            .frame(maxWidth: .infinity)
            .onChange(of: context.date) {
                guard !recorder.isPaused, !reduceMotion else { return }
                history = Array(history.dropFirst()) + [recorder.level]
            }
        }
        .accessibilityHidden(true)
    }
}
