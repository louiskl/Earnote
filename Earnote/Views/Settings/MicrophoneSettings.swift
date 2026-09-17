import EarnoteCore
import SwiftUI

/// Auswahl des Mikrofons: „Systemstandard“ oder ein bestimmtes Gerät. Ein gewähltes, gerade nicht
/// angeschlossenes Gerät bleibt als „(nicht verbunden)“ in der Liste.
struct MicrophonePicker: View {
    @EnvironmentObject var app: AppState
    var title = "Mikrofon"

    private var selection: Binding<String?> {
        Binding(get: { app.settings.microphoneDeviceUID }, set: { uid in
            app.settings.microphoneDeviceUID = uid
            app.settings.microphoneDeviceName = uid.flatMap { app.audioInputs.device($0)?.name }
        })
    }

    var body: some View {
        let inputs = app.audioInputs
        Picker(title, selection: selection) {
            Text("Systemstandard (\(inputs.defaultDevice?.name ?? "keins"))").tag(String?.none)
            Divider()
            ForEach(inputs.sorted) { device in
                Text(device.name).tag(Optional(device.uid))
            }
            if let uid = app.settings.microphoneDeviceUID, inputs.device(uid) == nil {
                Text("\(app.settings.microphoneDeviceName ?? "Gewähltes Mikrofon") (nicht verbunden)").tag(Optional(uid))
            }
        }
        .disabled(app.isRecording)
        .accessibilityLabel("Mikrofon für Aufnahmen")
        .accessibilityHint(app.isRecording ? "Während einer Aufnahme gesperrt" : "Wähle, welches Mikrofon Earnote verwendet")
    }
}

/// Mikrofon-Einstellungen im Bereich „Aufnahme“: Auswahl und eine Pegelanzeige zum Ausprobieren.
/// Der Pegeltest läuft nur, solange die Einstellungen sichtbar sind und keine Aufnahme läuft.
struct MicrophoneSettings: View {
    @EnvironmentObject var app: AppState
    @State private var monitor = MicrophoneLevelMonitor()

    /// Das Gerät, das eine Aufnahme jetzt benutzen würde
    private var testedDevice: AudioInputDeviceInfo? {
        let inputs = app.audioInputs
        return app.settings.microphoneDeviceUID.flatMap { inputs.device($0) } ?? inputs.defaultDevice
    }

    /// Ändert sich etwas davon, startet der Test neu
    private var monitorKey: String {
        "\(testedDevice?.uid ?? "-")|\(app.isRecording)|\(app.audioInputs.devices.map(\.uid).joined(separator: ","))"
    }

    var body: some View {
        Group {
            MicrophonePicker()
            if app.isRecording {
                Text("Während einer Aufnahme lässt sich das Mikrofon nicht wechseln.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LabeledContent("Pegel") {
                    ProgressView(value: Double(monitor.level))
                        .accessibilityLabel("Pegel des Mikrofons")
                        .accessibilityValue("\(Int(monitor.level * 100)) Prozent")
                }
                Text(monitor.failed ? "Dieses Mikrofon reagiert gerade nicht. Steck es kurz ab und wieder an oder wähle ein anderes."
                                    : "Sprich kurz, um das Mikrofon zu testen.")
                    .font(.caption).foregroundStyle(monitor.failed ? .orange : .secondary)
            }
        }
        .onAppear(perform: restartMonitor)
        .onDisappear { monitor.stop() }
        .onChange(of: monitorKey) { _, _ in restartMonitor() }
    }

    private func restartMonitor() {
        if app.isRecording { monitor.stop() } else { monitor.start(device: testedDevice) }
    }
}

/// Mikrofon-Auswahl als Menü (Menüleiste): Häkchen am gewählten Eintrag.
struct MicrophoneMenu: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Menu {
            MicrophonePicker(title: "Mikrofon")
                .pickerStyle(.inline)
            if app.isRecording {
                Text("Während einer Aufnahme gesperrt")
            }
        } label: {
            Label(currentName, systemImage: "mic")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Mikrofon wählen")
        .accessibilityLabel("Mikrofon: \(currentName)")
    }

    private var currentName: String {
        let inputs = app.audioInputs
        if let uid = app.settings.microphoneDeviceUID {
            return inputs.device(uid)?.name ?? "\(app.settings.microphoneDeviceName ?? "Mikrofon") (nicht verbunden)"
        }
        return inputs.defaultDevice?.name ?? "Mikrofon"
    }
}
