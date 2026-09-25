import EarnoteCore
import SwiftUI

/// Earnote für iPhone. Plan und Funktionsumfang: docs/IPHONE.md; Oberfläche nach DESIGN_GUIDELINES.md Abschnitt 30.
@main
struct EarnoteiOSApp: App {
    @State private var environment = PhoneEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .earnoteEnvironment(environment)
                #if DEBUG
                .environment(\.loadDemoLibrary) { await environment.loadDemoLibrary() }
                #endif
        }
        .commands { PhoneCommands(recorder: environment.recorder) }

        // iPad: eine Notiz im eigenen Fenster, z. B. neben den Folien der Vorlesung (DESIGN_GUIDELINES 31)
        WindowGroup("Notiz", id: NoteWindow.id, for: UUID.self) { $id in
            if let id {
                NavigationStack { RecordingDetailView(id: id) }
                    .earnoteEnvironment(environment)
            }
        }
    }
}

enum NoteWindow {
    static let id = "note"
}

extension View {
    /// Dieselben Stores in jedem Fenster
    func earnoteEnvironment(_ environment: PhoneEnvironment) -> some View {
        self.environment(environment.library)
            .environment(environment.recorder)
            .environment(environment.queue)
            .environment(environment.power)
            .environment(environment.handoffs)
            .environment(\.speakerDiarizer, environment.diarizer)
            .modifier(Skinned())
    }
}

extension EnvironmentValues {
    /// Sprechererkennung für „Sprecher erkennen“ in der Notiz
    @Entry var speakerDiarizer: (any SpeakerDiarizer)?

    /// Nur Debug: Beispieldaten laden (Einstellungen › Test)
    @Entry var loadDemoLibrary: (@MainActor () async -> Void)?
}
