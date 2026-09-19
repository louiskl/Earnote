import EarnoteCore
import SwiftUI

/// Abspielleiste unter Notiz und Transkript: Pause, 15 Sekunden vor und zurück, Position.
/// Sichtbar nur, wenn es zur gewählten Aufnahme noch eine Audiodatei gibt.
struct PlayerBar: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        @Bindable var player = player
        if player.hasAudio {
            HStack(spacing: 12) {
                Button { player.skip(-AudioPlayer.skipSeconds) } label: {
                    Image(systemName: "gobackward.15")
                }
                .help("15 Sekunden zurück (⌥←)")

                Button(action: player.playPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .help(player.isPlaying ? "Pause (⌥Leertaste)" : "Abspielen (⌥Leertaste)")

                Button { player.skip(AudioPlayer.skipSeconds) } label: {
                    Image(systemName: "goforward.15")
                }
                .help("15 Sekunden vor (⌥→)")

                Text(TimeFormat.duration(player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 38, alignment: .trailing)

                Slider(value: $player.currentTime, in: 0...max(player.duration, 1)) { editing in
                    if !editing { player.seek(to: player.currentTime) }
                }
                .controlSize(.small)
                .accessibilityLabel("Position in der Aufnahme")
                .accessibilityValue(TimeFormat.spoken(player.currentTime))

                Text("−" + TimeFormat.duration(max(0, player.duration - player.currentTime)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

/// Zeitmarke, die eine Stelle anspringt – in Transkript und Notiz dieselbe.
struct TimestampButton: View {
    @Environment(AudioPlayer.self) private var player
    let seconds: TimeInterval
    /// Nur Anzeige, wenn es keine Audiodatei mehr gibt
    var label: String?

    var body: some View {
        // Dieselbe knappe Schreibweise wie in der Abspielleiste: „5:12“, bei langen Aufnahmen „1:05:30“
        let text = label ?? TimeFormat.duration(seconds)
        if player.hasAudio {
            Button { player.play(from: seconds) } label: {
                Label(text, systemImage: "play.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.monospacedDigit())
            }
            .buttonStyle(.borderless)
            .help("Ab dieser Stelle anhören")
            .accessibilityLabel("Ab \(text) anhören")
        } else {
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
