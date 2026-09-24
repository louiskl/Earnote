import EarnoteCore
import SwiftUI

/// Earnote für iPhone. Plan und Funktionsumfang: docs/IPHONE.md; Oberfläche nach DESIGN_GUIDELINES.md Abschnitt 30.
@main
struct EarnoteiOSApp: App {
    @State private var environment = PhoneEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.library)
                .environment(environment.recorder)
                .environment(environment.queue)
                .environment(environment.power)
                .environment(environment.handoffs)
                #if DEBUG
                .environment(\.loadDemoLibrary) { await environment.loadDemoLibrary() }
                #endif
        }
    }
}

extension EnvironmentValues {
    /// Nur Debug: Beispieldaten laden (Einstellungen › Test)
    @Entry var loadDemoLibrary: (@MainActor () async -> Void)?
}
