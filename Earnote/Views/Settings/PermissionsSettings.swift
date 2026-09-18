import EarnoteCore
import SwiftUI
import UserNotifications

/// Berechtigungen: pro Freigabe eine Zeile mit Erklärung und – solange sie fehlt – einem Knopf.
struct PermissionsSettings: View {
    @State private var microphone = MicRecorder.permission == .authorized
    @State private var systemAudioAsked = UserDefaults.standard.bool(forKey: "systemAudioRequested")
    @State private var notifications = false

    var body: some View {
        Form {
            Section {
                PermissionRow(title: "Mikrofon",
                              detail: "Damit \(AppInfo.name) deine Stimme aufnehmen kann.",
                              granted: microphone, action: askMicrophone)
                PermissionRow(title: "Systemton",
                              detail: "Damit die anderen Teilnehmer in Zoom, Teams und Meet mitaufgenommen werden.",
                              granted: systemAudioAsked, grantedText: "Gefragt", action: askSystemAudio)
                PermissionRow(title: "Mitteilungen",
                              detail: "Damit du erfährst, wann eine Notiz fertig ist.",
                              granted: notifications, action: askNotifications)
            } footer: {
                Text("Alle Freigaben lassen sich jederzeit in den Systemeinstellungen ändern.")
            }
            Section {
                Button("Datenschutz-Einstellungen von macOS öffnen") { SystemSettingsLink.microphone() }
            }
        }
        .formStyle(.grouped)
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notifications = status == .authorized
        }
    }

    private func askMicrophone() {
        Task {
            if MicRecorder.permission == .denied { SystemSettingsLink.microphone() }
            microphone = await MicRecorder.requestPermission()
        }
    }

    private func askSystemAudio() {
        Task {
            await SystemAudioTap.requestPermission()
            UserDefaults.standard.set(true, forKey: "systemAudioRequested")
            systemAudioAsked = true
        }
    }

    private func askNotifications() {
        Task { notifications = await Notifier.requestPermission() }
    }
}

/// Eine Freigabe: Name, Erklärung und rechts entweder „Erlaubt“ oder der Knopf zum Fragen.
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var grantedText = "Erlaubt"
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label(grantedText, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Erlauben …", action: action)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}
