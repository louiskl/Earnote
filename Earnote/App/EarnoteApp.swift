import EarnoteCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
struct EarnoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let environment: AppEnvironment

    init() {
        #if DEBUG
        // Einmaliger Wartungslauf: CloudKit-Schema anlegen, dann beenden (siehe CloudSchemaSetup).
        // Muss vor jeder Umgebung laufen: Sonst spiegelt die Bibliothek des Nutzers schon, und der
        // Schema-Lauf wartet vergeblich auf einen freien Platz („already a pending request“).
        if CloudSchemaSetup.isRequested {
            let ok = CloudSchemaSetup.run()
            Log.flush()
            exit(ok ? 0 : 1)
        }
        #endif
        // Der Testbereich wird zuerst geprüft: sonst würde schon das Erzeugen der echten Umgebung
        // die Bibliothek des Nutzers öffnen, obwohl der Test in seinem eigenen Ordner laufen soll.
        var sandbox: AppEnvironment?
        #if DEBUG
        if !Self.isTestHost { sandbox = AppEnvironment.sandboxIfRequested() }
        #endif
        let environment: AppEnvironment
        if let sandbox {
            environment = sandbox
        } else if Self.isTestHost {
            environment = AppEnvironment.forTestHost()
        } else {
            environment = AppEnvironment()
        }
        self.environment = environment
        let recorder = environment.recorder
        let library = environment.library
        delegate.isRecording = { recorder.isRecording }
        delegate.stopRecording = { recorder.stopRecording() }
        delegate.settings = { library.settings }
        delegate.waitForPendingWrites = { await library.waitForPendingWrites() }
        // Globales Kürzel: startet und stoppt im Standardbereich, egal welche App gerade vorn ist
        delegate.toggleRecording = {
            if recorder.isRecording {
                recorder.stopRecording()
            } else {
                recorder.startRecording(category: library.category(library.settings.defaultCategoryID))
            }
        }
        delegate.globalShortcutEnabled = library.settings.globalShortcut
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
                .environment(environment.updates)
                .environment(environment.cloudSync)
                .environmentObject(environment.recorder.meter)
                .environmentObject(environment.recorder.live)
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
            SettingsView(llm: environment.llm)
                .environment(environment.updates)
                .environment(environment.cloudSync)
                .environment(environment.library)
                .environment(environment.recorder)
                .environment(environment.recorder.audioInputs)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(environment.library)
                .environment(environment.recorder)
                .environment(environment.recorder.audioInputs)
                .environmentObject(environment.recorder.meter)
                .environmentObject(environment.recorder.live)
        } label: {
            MenuBarLabel()
                .environment(environment.library)
                .environment(environment.recorder)
                .environmentObject(environment.recorder.meter)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Läuft gerade eine Aufnahme? (in `EarnoteApp.init` gesetzt)
    var isRecording: () -> Bool = { false }
    /// Aktuelle Einstellungen (für „Fenster beim Start zeigen“)
    var settings: () -> AppSettings = { AppSettings() }
    /// Laufende Aufnahme beenden und speichern
    var stopRecording: () -> Void = {}
    /// Wartet auf noch laufende Schreibvorgänge der Bibliothek (in `EarnoteApp.init` gesetzt)
    var waitForPendingWrites: (@MainActor () async -> Void)?
    /// Aufnahme starten/stoppen für das globale Tastenkürzel (in `EarnoteApp.init` gesetzt)
    var toggleRecording: (@MainActor () -> Void)?
    var globalShortcutEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        GlobalShortcut.action = { [weak self] in self?.toggleRecording?() }
        GlobalShortcut.apply(enabled: globalShortcutEnabled)
        #if DEBUG
        // Nur für Tests: hell oder dunkel prüfen, ohne die Systemeinstellung des Nutzers zu ändern
        switch ProcessInfo.processInfo.environment["EARNOTE_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        // Nur für Tests: die Einstellungen direkt öffnen (Bildschirmfotos, Design-Review)
        if ProcessInfo.processInfo.environment["EARNOTE_SHOW_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApp.activate(ignoringOtherApps: true)
                // Über den Menübefehl, weil `showSettingsWindow:` ohne aktives Fenster nicht greift
                let items = NSApp.mainMenu?.items.first?.submenu?.items ?? []
                if let item = items.first(where: { $0.title.contains("Einstellungen") || $0.title.contains("Settings") }),
                   let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                }
            }
        }
        // Nur für Tests: den Call-Hinweis einmal zeigen, ohne dass ein echter Call laufen muss
        if let demoCall = ProcessInfo.processInfo.environment["EARNOTE_DEMO_CALL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                FloatingPanels.shared.showCallPrompt(app: demoCall) {}
            }
        }
        #endif
        Log.info("\(AppInfo.name) gestartet")
        // Wer das Fenster beim Start nicht will, ist die App nur in der Menüleiste.
        // Beim allerersten Start bleibt es offen, damit der Einrichtungsassistent erscheint.
        if !settings().openWindowAtLaunch && settings().onboardingCompleted {
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
        if isRecording() {
            let alert = NSAlert()
            alert.messageText = "Aufnahme läuft noch"
            alert.informativeText = "Soll die Aufnahme gespeichert werden? Sie wird beim nächsten Start verarbeitet."
            alert.addButton(withTitle: "Speichern & beenden")
            alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            stopRecording()
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
