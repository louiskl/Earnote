import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
struct EarmarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        Window("Earmark", id: "main") {
            MainView()
                .environmentObject(app)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(app.isRecording ? "Aufnahme stoppen" : "Neue Aufnahme") {
                    if app.isRecording { app.stopRecording() } else { app.startRecording(category: nil) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
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
        _ = AppState.shared
        Log.info("Earmark gestartet")
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
