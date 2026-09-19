import EarnoteCore
import EarnoteML
import SwiftUI

/// Transkription: Sprache, Verfahren und – bei Whisper – das Modell samt Download und Vorbereitung.
struct TranscriptionSettings: View {
    @Environment(LibraryStore.self) private var library

    /// Apple-Spracherkennung nur anbieten, wo es sie gibt
    private var engines: [TranscriptionEngineKind] {
        TranscriptionEngineKind.allCases.filter { $0 != .apple || TranscriberFactory.appleSpeechAvailable }
    }

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Picker("Sprache der Aufnahmen", selection: $library.settings.language) {
                    ForEach(AppSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker("Spracherkennung", selection: $library.settings.transcriptionEngine) {
                    ForEach(engines) { Text($0.label).tag($0) }
                }
            } footer: {
                Text(library.settings.transcriptionEngine == .apple
                     ? "In macOS eingebaut: schnell und ohne Download. Die Sprachdaten lädt macOS selbst."
                     : "Whisper läuft lokal auf deinem Mac. Sehr genau, auch bei Fachbegriffen – einmaliger Download.")
            }

            if library.settings.transcriptionEngine == .whisperKit {
                WhisperModelSection(model: $library.settings.whisperModel)
            }

            Section {
                Toggle("Sprecher unterscheiden („Ich“ und „Andere“)", isOn: $library.settings.speakerLabels)
            } footer: {
                Text("\(AppInfo.name) erkennt anhand von Mikrofon und Systemton, wer gerade spricht.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if library.settings.whisperModel.isEmpty { library.settings.whisperModel = WhisperModelManager.curated[0].id }
        }
    }
}

/// Whisper-Modell wählen, laden und für den Chip vorbereiten.
/// Die Vorbereitung passiert sonst unsichtbar bei der ersten Aufnahme und dauert dort minutenlang.
struct WhisperModelSection: View {
    @Binding var model: String
    @ObservedObject private var models = WhisperModelManager.shared

    private var info: WhisperModelManager.ModelInfo? {
        WhisperModelManager.curated.first { $0.id == model }
    }
    private var isInstalled: Bool { models.installed[model] != nil }

    var body: some View {
        Section("Whisper-Modell") {
            Picker("Modell", selection: $model) {
                ForEach(WhisperModelManager.curated) { Text($0.title).tag($0.id) }
            }
            if let info { Text(info.detail).font(.callout).foregroundStyle(.secondary) }
            LabeledContent("Status") { status }
            if let error = models.lastError {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if models.downloading == model {
            HStack {
                ProgressView(value: models.downloadProgress).frame(width: 120)
                Text("\(Int(models.downloadProgress * 100)) %").font(.callout.monospacedDigit())
                Button("Abbrechen") { models.cancelDownload() }
            }
        } else if models.preparing == model {
            HStack {
                ProgressView().controlSize(.small)
                Text("Wird für deinen Mac vorbereitet – das kann einige Minuten dauern.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else if isInstalled {
            HStack {
                if models.prepared.contains(model) {
                    Label("Bereit", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else {
                    Button("Für diesen Mac vorbereiten") { Task { await models.prepare(model) } }
                        .help("Einmalig: danach startet die erste Aufnahme ohne Wartezeit.")
                        .disabled(models.preparing != nil)
                }
                Button("Löschen") { models.delete(model) }
            }
        } else {
            Button("Laden") { models.startDownload(model) }
                .disabled(models.downloading != nil)
        }
    }
}
