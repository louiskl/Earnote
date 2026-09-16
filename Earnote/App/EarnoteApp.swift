import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
struct EarnoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app: AppState

    init() {
        // Muss vor allem anderen laufen: AppState, Storage und Log würden sonst schon im neuen,
        // leeren Datenordner lesen oder ihn anlegen, bevor die alten Daten übernommen sind.
        LegacyMigration.runIfNeeded()
        _app = StateObject(wrappedValue: AppState.shared)
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            MainView()
                .environmentObject(app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Seitenleiste ein-/ausblenden") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .newItem) {
                Button(app.isRecording ? "Aufnahme stoppen" : "Neue Aufnahme") {
                    if app.isRecording { app.stopRecording() } else { app.startRecording(category: nil) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button(app.isPaused ? "Aufnahme fortsetzen" : "Aufnahme pausieren") { app.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!app.isRecording)
                Button("Audiodatei importieren …") { ImportHelper.pickAndImport() }
                    .keyboardShortcut("i", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let state = AppState.shared
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
        let state = AppState.shared
        if state.isRecording {
            let alert = NSAlert()
            alert.messageText = "Aufnahme läuft noch"
            alert.informativeText = "Soll die Aufnahme gespeichert werden? Sie wird beim nächsten Start verarbeitet."
            alert.addButton(withTitle: "Speichern & beenden")
            alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            state.stopRecording()
        }
        return .terminateNow
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
enum ImportHelper {
    static func pickAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.message = "Audiodateien zum Transkribieren auswählen"
        if panel.runModal() == .OK { AppState.shared.importAudio(panel.urls, category: nil) }
    }
}
