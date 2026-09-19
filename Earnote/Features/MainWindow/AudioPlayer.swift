import AVFoundation
import EarnoteCore
import Observation

/// Abspielen der Aufnahme, während man Notiz oder Transkript liest.
/// Gehört dem Fenster: Jedes Fenster hat seinen eigenen Player, ein Auswahlwechsel stoppt ihn.
@MainActor
@Observable
final class AudioPlayer {
    /// Aufnahme, die gerade geladen ist
    private(set) var recordingID: UUID?
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    /// Aktuelle Stelle in Sekunden – beim Ziehen am Regler der gewünschte Wert
    var currentTime: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?

    /// Sprung um 15 Sekunden – wie in Podcasts
    static let skipSeconds: TimeInterval = 15

    deinit { ticker?.invalidate() }

    var hasAudio: Bool { player != nil }

    /// Lädt die Aufnahme, ohne abzuspielen. Eine bereits geladene Aufnahme wird nicht neu geladen –
    /// ein gescheiterter Versuch aber schon: Beim Start ist die Bibliothek manchmal noch nicht da.
    func load(_ id: UUID, url: URL?) {
        guard recordingID != id || player == nil else { return }
        stop()
        guard let url, let loaded = try? AVAudioPlayer(contentsOf: url) else { return }
        loaded.prepareToPlay()
        player = loaded
        recordingID = id
        duration = loaded.duration
        currentTime = 0
    }

    func playPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTicker()
        } else {
            player.play()
            isPlaying = true
            startTicker()
        }
    }

    /// Von einer Stelle an abspielen – das ist der Sprung aus Transkript und Notiz.
    func play(from seconds: TimeInterval) {
        guard let player else { return }
        seek(to: seconds)
        if !player.isPlaying { playPause() }
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let target = min(max(0, seconds), max(0, duration - 0.1))
        player.currentTime = target
        currentTime = target
    }

    func skip(_ seconds: TimeInterval) { seek(to: currentTime + seconds) }

    func stop() {
        player?.stop()
        player = nil
        stopTicker()
        isPlaying = false
        duration = 0
        currentTime = 0
        recordingID = nil
    }

    /// Läuft die Stelle gerade? Damit hebt das Transkript den laufenden Absatz hervor.
    func isPlaying(from start: TimeInterval, to end: TimeInterval) -> Bool {
        isPlaying && currentTime >= start && currentTime < end
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                // Am Ende von selbst anhalten, statt stumm weiterzulaufen
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopTicker()
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
