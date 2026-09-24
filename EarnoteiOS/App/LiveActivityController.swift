import ActivityKit
import AppIntents
import EarnoteCore
import Foundation

/// Hält die Live-Aktivität im Takt mit der Aufnahme: an beim Start, aktualisiert bei Pause, weg beim Stopp.
@MainActor
final class LiveActivityController {
    private var activity: Activity<RecordingActivityAttributes>?

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
                                                             pausedElapsed: recorder.isPaused ? elapsed : nil)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                activity = try Activity.request(attributes: RecordingActivityAttributes(categoryName: recorder.categoryName),
                                                content: content)
            } catch {
                Log.info("Live-Aktivität nicht möglich: \(error.localizedDescription)")
            }
        }
    }

    private func end() {
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
