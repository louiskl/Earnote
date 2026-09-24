import EarnoteCore
import SwiftUI

/// Die laufende Aufnahme groß: Laufzeit, Pegel, Pause und Stopp. Schließen lässt die Aufnahme weiterlaufen.
struct RecordSheet: View {
    @Environment(PhoneRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BrandGlow(intensity: recorder.isPaused ? 0.25 : 1, level: { [recorder] in recorder.isPaused ? 0 : recorder.level })
                VStack(spacing: 24) {
                    Spacer()
                    status
                    ElapsedText()
                        .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                        .accessibilityLabel("Laufzeit")
                    LevelMeter()
                        .frame(height: 64)
                        .padding(.horizontal, 24)
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .contentTransition(.opacity)
                    Spacer()
                    controls
                        .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "chevron.down") { dismiss() }
                }
            }
            .onChange(of: recorder.isRecording) { _, recording in if !recording { dismiss() } }
        }
        .presentationDragIndicator(.visible)
        .animation(.smooth, value: recorder.isPaused)
    }

    private var status: some View {
        HStack(spacing: 8) {
            Image(systemName: recorder.isPaused ? "pause.circle.fill" : "record.circle")
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: !recorder.isPaused)
            Text(recorder.isPaused ? "Pausiert" : "Nimmt auf")
            if let name = recorder.categoryName {
                Text("·").foregroundStyle(.secondary)
                Text(name).foregroundStyle(.secondary)
            }
        }
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
    }

    private var hint: LocalizedStringKey {
        if recorder.isInterrupted { return "Pausiert wegen eines Anrufs – danach geht es von selbst weiter." }
        if recorder.isPaused { return "Tippe auf Fortsetzen, um weiter aufzunehmen." }
        return "Du kannst das iPhone sperren – Earnote nimmt weiter auf."
    }

    /// Pause und Stopp als runde Glasknöpfe; Stopp ist der Hauptknopf
    private var controls: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 28) {
                RoundControl(title: recorder.isPaused ? "Fortsetzen" : "Pause",
                             symbol: recorder.isPaused ? "play.fill" : "pause.fill", size: 76, prominent: false) {
                    recorder.togglePause()
                }
                RoundControl(title: "Stopp", symbol: "stop.fill", size: 92, prominent: true) {
                    recorder.stop()
                    dismiss()
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isPaused)
    }
}

private struct RoundControl: View {
    let title: LocalizedStringKey
    let symbol: String
    let size: CGFloat
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if prominent {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.glass)
            }
            Text(title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .frame(width: size, height: size)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(title))
    }
}

/// Pegel als gespiegelte Balken, zehnmal pro Sekunde abgefragt; ruht, wenn pausiert
private struct LevelMeter: View {
    @Environment(PhoneRecorder.self) private var recorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var history = Array(repeating: Float(0), count: 36)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            HStack(alignment: .center, spacing: 4) {
                ForEach(history.indices, id: \.self) { i in
                    Capsule()
                        .fill(.tint.opacity(opacity(i)))
                        .frame(height: height(i))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: history)
            .onChange(of: context.date) {
                guard !recorder.isPaused else { return }
                history = Array(history.dropFirst()) + [min(1, recorder.level * 1.4)]
            }
        }
        .accessibilityHidden(true)
    }

    // Eigene Funktionen: als ein Ausdruck braucht der Compiler zu lange (Xcode 26.6)
    private func opacity(_ i: Int) -> Double {
        0.35 + 0.65 * Double(i) / Double(history.count)
    }

    private func height(_ i: Int) -> CGFloat {
        max(5, CGFloat(history[i]) * 64)
    }
}
