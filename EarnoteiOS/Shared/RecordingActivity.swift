import ActivityKit
import AppIntents
import Foundation

/// Live-Aktivität einer laufenden Aufnahme. Geteilt: Die App startet und aktualisiert sie, die Widget-Erweiterung zeigt sie
/// auf dem Sperrbildschirm und in der Dynamic Island.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Anker für die mitlaufende Uhr (`Text(timerInterval:)`): jetzt minus bisherige Laufzeit
        var countingSince: Date
        /// Gesetzt, solange pausiert – dann steht die Uhr auf diesem Wert
        var pausedElapsed: TimeInterval?

        var isPaused: Bool { pausedElapsed != nil }
    }

    var categoryName: String?
}

/// Was die Intents in der App auslösen. Die App trägt die Befehle beim Start ein. In der Widget-Erweiterung bleiben sie
/// leer – dort laufen die Intents nie, sie werden nur als Knöpfe angezeigt.
@MainActor
enum RecordingCommands {
    static var start: () async -> Void = {}
    static var togglePause: () -> Void = {}
    static var stop: () -> Void = {}
}

/// Kontrollzentrum, Action-Taste, Siri, Kurzbefehle. Als `AudioRecordingIntent` darf er aufnehmen, ohne die App zu öffnen –
/// die Live-Aktivität zeigt dann, dass aufgenommen wird.
struct StartRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Aufnahme starten"
    static let description = IntentDescription("Startet in Earnote eine Aufnahme.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingCommands.start()
        return .result()
    }
}

struct TogglePauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aufnahme pausieren oder fortsetzen"

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommands.togglePause()
        return .result()
    }
}

struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aufnahme beenden"
    static let description = IntentDescription("Beendet die laufende Aufnahme; Earnote schreibt danach die Notiz.")

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommands.stop()
        return .result()
    }
}
