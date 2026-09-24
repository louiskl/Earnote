import EarnoteCore
import SwiftUI

/// Aufnehmen – mit Bereichs- und Mikrofonwahl; während der Aufnahme Pause und Stopp mit Laufzeit.
/// Dieselbe Komponente benutzt die Toolbar des Hauptfensters und das Fenster in der Menüleiste.
struct RecordControl: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    /// Bereich, in dem eine neue Aufnahme landet (nil = Standardbereich)
    let categoryID: UUID?
    /// Lange Bereichsnamen kürzen, damit schmale Fenster nicht auseinandergezogen werden
    var maxNameLength = 34

    var body: some View {
        if recorder.isRecording {
            ControlGroup {
                Button {
                    recorder.togglePause()
                } label: {
                    Label(recorder.isPaused ? "Fortsetzen" : "Pause",
                          systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                }
                .help(recorder.isPaused ? "Aufnahme fortsetzen (⇧⌘P)" : "Aufnahme pausieren (⇧⌘P)")
                Button {
                    recorder.stopRecording()
                } label: {
                    StopLabel(meter: recorder.meter)
                }
                .help("Aufnahme stoppen (⇧⌘R)")
            }
        } else {
            Menu {
                Section("Aufnehmen in") {
                    ForEach(library.categories) { category in
                        Button("\(category.displayEmoji) \(shortened(category.name))") {
                            recorder.startRecording(category: category)
                        }
                    }
                }
                Divider()
                MicrophoneChoiceMenu(maxNameLength: maxNameLength)
            } label: {
                // Mit Text: verständlicher als ein Symbol allein, und VoiceOver liest nicht
                // den Symbolnamen („Bildschirmaufnahme“) vor.
                Label("Aufnehmen", systemImage: "record.circle")
                    .labelStyle(.titleAndIcon)
            } primaryAction: {
                recorder.startRecording(category: library.category(categoryID))
            }
            .menuIndicator(.visible)
            .help("Aufnahme starten (⇧⌘R)")
        }
    }

    private func shortened(_ name: String) -> String {
        TextShortening.middleTruncated(name, max: maxNameLength)
    }
}

struct StopLabel: View {
    @ObservedObject var meter: LiveMeter

    var body: some View {
        Label("Stopp \(TimeFormat.duration(meter.elapsed))", systemImage: "stop.fill")
            .labelStyle(.titleAndIcon)
            .monospacedDigit()
    }
}

/// Mikrofonwahl als Menü (Toolbar, Menü „Aufnahme“ und Menüleiste), Häkchen am gewählten Eintrag
struct MicrophoneChoiceMenu: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioInputDevices.self) private var inputs
    @Environment(RecordingController.self) private var recorder
    var maxNameLength = 34

    var body: some View {
        Picker("Mikrofon", selection: Binding(get: { library.settings.microphoneDeviceUID }, set: { uid in
            library.settings.microphoneDeviceUID = uid
            library.settings.microphoneDeviceName = uid.flatMap { inputs.device($0)?.name }
        })) {
            Text("Systemstandard (\(shortened(inputs.defaultDevice?.name ?? "keins")))").tag(String?.none)
            ForEach(inputs.sorted) { device in
                Text(shortened(device.name)).tag(Optional(device.uid))
            }
            if let uid = library.settings.microphoneDeviceUID, inputs.device(uid) == nil {
                Text("\(shortened(library.settings.microphoneDeviceName ?? String(localized: "Gewähltes Mikrofon"))) (nicht verbunden)")
                    .tag(Optional(uid))
            }
        }
        .pickerStyle(.menu)
        .disabled(recorder.isRecording)
    }

    private func shortened(_ name: String) -> String {
        TextShortening.middleTruncated(name, max: maxNameLength)
    }
}
