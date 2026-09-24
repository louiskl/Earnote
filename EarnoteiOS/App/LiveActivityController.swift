import ActivityKit
import AppIntents
import EarnoteCore
import Foundation

/// Hält die Live-Aktivität im Takt mit der Aufnahme: an beim Start, aktualisiert bei Pause, weg beim Stopp.
@MainActor
final class LiveActivityController {
    private var activity: Activity<RecordingActivityAttributes>?
    private var levels: [Double] = Array(repeating: 0, count: 12)
    private var ticker: Task<Void, Never>?

    init() {
        // Überbleibsel einer abgestürzten Sitzung räumen
        for stale in Activity<RecordingActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func update(_ recorder: PhoneRecorder) {
        guard recorder.isRecording else { return end() }
        let elapsed = recorder.elapsed()
        let state = RecordingActivityAttributes.ContentState(countingSince: Date().addingTimeInterval(-elapsed),
                                                             pausedElapsed: recorder.isPaused ? elapsed : nil,
                                                             levels: recorder.isPaused ? levels.map { _ in 0 } : levels)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                activity = try Activity.request(attributes: RecordingActivityAttributes(categoryName: recorder.categoryName),
                                                content: content)
                tick(recorder)
            } catch {
                Log.info("Live-Aktivität nicht möglich: \(error.localizedDescription)")
            }
        }
    }

    /// Pegel nachreichen, solange aufgenommen wird
    private func tick(_ recorder: PhoneRecorder) {
        ticker?.cancel()
        ticker = Task { [weak self, weak recorder] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, let recorder, recorder.isRecording else { return }
                guard !recorder.isPaused else { continue }
                self.levels = Array(self.levels.dropFirst()) + [Double(min(1, recorder.level * 1.4))]
                self.update(recorder)
            }
        }
    }

    private func end() {
        ticker?.cancel()
        ticker = nil
        levels = levels.map { _ in 0 }
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

/// Siri und Kurzbefehle: „Starte eine Aufnahme mit Earnote“
struct EarnoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRecordingIntent(),
                    phrases: ["Starte eine Aufnahme mit \(.applicationName)", "Nimm mit \(.applicationName) auf"],
                    shortTitle: "Aufnehmen", systemImageName: "record.circle")
        AppShortcut(intent: StopRecordingIntent(),
                    phrases: ["Beende die Aufnahme in \(.applicationName)"],
                    shortTitle: "Aufnahme beenden", systemImageName: "stop.circle")
    }
}
