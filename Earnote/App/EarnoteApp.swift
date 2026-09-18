import EarnoteCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
struct EarnoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app: AppState
    private let environment: AppEnvironment

    init() {
        // Muss vor allem anderen laufen: Stores, Storage und Log würden sonst schon im neuen,
        // leeren Datenordner lesen oder ihn anlegen, bevor die alten Daten übernommen sind.
        LegacyMigration.runIfNeeded()
        var environment: AppEnvironment
        if Self.isTestHost {
            environment = AppEnvironment.forTestHost()
        } else {
            environment = AppEnvironment()
        }
        #if DEBUG
        if !Self.isTestHost, let sandbox = AppEnvironment.sandboxIfRequested() { environment = sandbox }
        #endif
        self.environment = environment
        _app = StateObject(wrappedValue: environment.appState)
        delegate.app = environment.appState
        let library = environment.library
        delegate.waitForPendingWrites = { await library.waitForPendingWrites() }
    }

    /// Die App-Tests starten die App als Host. Sie darf dabei nie die echte Bibliothek öffnen oder übernehmen.
    private static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
                .environment(environment.library)
                .environment(environment.recorder)
                .environment(environment.queue)
                .environment(environment.recorder.audioInputs)
                // Nur für die noch alten Sheets (Bereichs-Editor, Einrichtungsassistent) bis Phase 2b
                .environmentObject(app)
                .environmentObject(app.meter)
                .environmentObject(app.live)
                .modelContainer(environment.container)
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 780)
        .commands {
            SidebarCommands()
            EarnoteCommands(library: environment.library, recorder: environment.recorder,
                            audioInputs: environment.recorder.audioInputs)
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(app.meter)
                .environmentObject(app.live)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
                .environmentObject(app.meter)
                .environmentObject(app.live)
        } label: {
            MenuBarLabel()
                .environmentObject(app)
                .environmentObject(app.meter)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Wird in `EarnoteApp.init` gesetzt
    var app: AppState?
    /// Wartet auf noch laufende Schreibvorgänge der Bibliothek (in `EarnoteApp.init` gesetzt)
    var waitForPendingWrites: (@MainActor () async -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        // Nur für Tests: hell oder dunkel prüfen, ohne die Systemeinstellung des Nutzers zu ändern
        switch ProcessInfo.processInfo.environment["EARNOTE_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        #endif
        guard let state = app else { return }
        Log.info("\(AppInfo.name) gestartet")
        // Wer das Fenster beim Start nicht will, ist die App nur in der Menüleiste.
        // Beim allerersten Start bleibt es offen, damit der Einrichtungsassistent erscheint.
        if !state.settings.openWindowAtLaunch && state.settings.onboardingCompleted {
            DispatchQueue.main.async {
                NSApp.windows.filter { $0.identifier?.rawValue.contains("main") == true }.forEach { $0.close() }
            }
        }
    }

    /// Klick aufs Dock-Symbol ohne offenes Fenster: Hauptfenster wieder zeigen
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !flag
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let state = app, state.isRecording {
            let alert = NSAlert()
            alert.messageText = "Aufnahme läuft noch"
            alert.informativeText = "Soll die Aufnahme gespeichert werden? Sie wird beim nächsten Start verarbeitet."
            alert.addButton(withTitle: "Speichern & beenden")
            alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            state.stopRecording()
        }
        // Eine gerade angelegte Notiz, ein neuer Bereich oder ein Umbenennen wird im Hintergrund
        // gespeichert. Erst beenden, wenn das durch ist – sonst geht die letzte Änderung verloren.
        guard let waitForPendingWrites else { return .terminateNow }
        Task { @MainActor in
            await waitForPendingWrites()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
