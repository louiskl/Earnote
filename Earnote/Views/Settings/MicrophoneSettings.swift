import EarnoteCore
import SwiftUI

/// Auswahl des Mikrofons: „Systemstandard“ oder ein bestimmtes Gerät. Ein gewähltes, gerade nicht
/// angeschlossenes Gerät bleibt als „(nicht verbunden)“ in der Liste.
struct MicrophonePicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Environment(AudioInputDevices.self) private var inputs
    var title = "Mikrofon"

    private var selection: Binding<String?> {
        Binding(get: { library.settings.microphoneDeviceUID }, set: { uid in
            library.settings.microphoneDeviceUID = uid
            library.settings.microphoneDeviceName = uid.flatMap { inputs.device($0)?.name }
        })
    }

    var body: some View {
        Picker(title, selection: selection) {
            Text("Systemstandard (\(inputs.defaultDevice?.name ?? "keins"))").tag(String?.none)
            Divider()
            ForEach(inputs.sorted) { device in
                Text(device.name).tag(Optional(device.uid))
            }
            if let uid = library.settings.microphoneDeviceUID, inputs.device(uid) == nil {
                Text("\(library.settings.microphoneDeviceName ?? String(localized: "Gewähltes Mikrofon")) (nicht verbunden)").tag(Optional(uid))
            }
        }
        .disabled(recorder.isRecording)
        .accessibilityLabel("Mikrofon für Aufnahmen")
        .accessibilityHint(recorder.isRecording ? "Während einer Aufnahme gesperrt" : "Wähle, welches Mikrofon \(AppInfo.name) verwendet")
    }
}

/// Mikrofon-Einstellungen: Auswahl und eine Pegelanzeige zum Ausprobieren.
/// Der Pegeltest läuft nur, solange die Einstellungen sichtbar sind und keine Aufnahme läuft.
struct MicrophoneSettings: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Environment(AudioInputDevices.self) private var inputs
    @StateObject private var monitor = MicrophoneLevelMonitor()

    /// Das Gerät, das eine Aufnahme jetzt benutzen würde
    private var testedDevice: AudioInputDeviceInfo? {
        library.settings.microphoneDeviceUID.flatMap { inputs.device($0) } ?? inputs.defaultDevice
    }

    /// Ändert sich etwas davon, startet der Test neu
    private var monitorKey: String {
        "\(testedDevice?.uid ?? "-")|\(recorder.isRecording)|\(inputs.devices.map(\.uid).joined(separator: ","))"
    }

    var body: some View {
        Group {
            // Der Test hängt an der Picker-Zeile: Sie ist immer sichtbar, solange die Einstellungen offen sind
            MicrophonePicker()
                .onAppear(perform: restartMonitor)
                .onDisappear { monitor.stop() }
                .onChange(of: monitorKey) { _, _ in restartMonitor() }
            if recorder.isRecording {
                Text("Während einer Aufnahme lässt sich das Mikrofon nicht wechseln.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if monitor.needsPermission {
                LabeledContent("Pegel") {
                    HStack {
                        Text("\(AppInfo.name) darf das Mikrofon noch nicht verwenden.")
                            .font(.callout).foregroundStyle(.orange)
                        Button("Erlauben …") {
                            Task {
                                if MicRecorder.permission == .denied { SystemSettingsLink.microphone() }
                                _ = await MicRecorder.requestPermission()
                                restartMonitor()
                            }
                        }
                    }
                }
            } else {
                LabeledContent("Pegel") {
                    ProgressView(value: Double(monitor.level))
                        .accessibilityLabel("Pegel des Mikrofons")
                        .accessibilityValue("\(Int(monitor.level * 100)) Prozent")
                }
                Text(monitor.failed ? "Dieses Mikrofon reagiert gerade nicht. Steck es kurz ab und wieder an oder wähle ein anderes."
                                    : "Sprich kurz, um das Mikrofon zu testen.")
                    .font(.callout).foregroundStyle(monitor.failed ? .orange : .secondary)
            }
        }
    }

    private func restartMonitor() {
        if recorder.isRecording { monitor.stop() } else { monitor.start(device: testedDevice) }
    }
}

/// Mikrofon-Auswahl als Menü (Menüleiste): Häkchen am gewählten Eintrag.
struct MicrophoneMenu: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Environment(AudioInputDevices.self) private var inputs

    var body: some View {
        Menu {
            MicrophonePicker(title: "Mikrofon")
                .pickerStyle(.inline)
            if recorder.isRecording {
                Text("Während einer Aufnahme gesperrt")
            }
        } label: {
            Label(currentName, systemImage: "mic")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Mikrofon wählen")
        .accessibilityLabel("Mikrofon: \(currentName)")
    }

    private var currentName: String {
        if let uid = library.settings.microphoneDeviceUID {
            return inputs.device(uid)?.name ?? String(localized: "\(library.settings.microphoneDeviceName ?? String(localized: "Mikrofon")) (nicht verbunden)")
        }
        return inputs.defaultDevice?.name ?? "Mikrofon"
    }
}
