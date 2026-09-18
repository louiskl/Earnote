import AppKit
import EarnoteCore
import SwiftUI

/// Einstellungen als eigene Szene: pro Thema ein Tab, jeder Tab ein natives Formular.
struct SettingsView: View {
    let llm: LLMFactory
    /// Im Debug-Build kann `EARNOTE_SETTINGS_TAB` einen Tab direkt öffnen (Bildschirmfotos, Design-Review)
    @State private var tab = ProcessInfo.processInfo.environment["EARNOTE_SETTINGS_TAB"] ?? "allgemein"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("Allgemein", systemImage: "gearshape") }.tag("allgemein")
            RecordingSettings().tabItem { Label("Aufnahme", systemImage: "mic") }.tag("aufnahme")
            PermissionsSettings().tabItem { Label("Berechtigungen", systemImage: "lock.shield") }.tag("rechte")
            TranscriptionSettings().tabItem { Label("Transkription", systemImage: "waveform") }.tag("transkription")
            AISettings(llm: llm).tabItem { Label("KI", systemImage: "cpu") }.tag("ki")
            GlossarySettings().tabItem { Label("Wörterbuch", systemImage: "character.book.closed") }.tag("woerterbuch")
            DestinationsSettings().tabItem { Label("Ziele", systemImage: "square.and.arrow.up") }.tag("ziele")
            AboutSettings().tabItem { Label("Über", systemImage: "info.circle") }.tag("ueber")
        }
        .frame(width: 640, height: 500)
    }
}

/// Allgemein: Erscheinungsbild, Start, Speicher und der Einrichtungsassistent.
struct GeneralSettings: View {
    @Environment(LibraryStore.self) private var library
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Picker("Erscheinungsbild", selection: $library.settings.appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Start") {
                Toggle("\(AppInfo.name) beim Start des Macs automatisch öffnen", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.set(on) }
                Toggle("Fenster beim Start zeigen", isOn: $library.settings.openWindowAtLaunch)
            }
            Section {
                Toggle("Audiodateien nach der Verarbeitung behalten", isOn: $library.settings.keepAudioFiles)
            } header: {
                Text("Speicher")
            } footer: {
                Text("Behaltene Aufnahmen lassen sich später neu transkribieren. Eine Stunde braucht 250–600 MB.")
            }
            Section {
                HStack {
                    Button("Datenordner öffnen") { NSWorkspace.shared.open(Storage.standard.root) }
                    Button("Protokoll öffnen") { NSWorkspace.shared.open(Log.url) }
                }
                Button("Einrichtungsassistent erneut starten") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Aufnahme: Mikrofon, Systemton, Call-Erkennung und der Standard-Bereich.
struct RecordingSettings: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            Section("Mikrofon") {
                MicrophoneSettings()
            }
            Section {
                Toggle("Systemton mitaufnehmen", isOn: $library.settings.recordSystemAudio)
            } footer: {
                Text("Nimmt auch die anderen Teilnehmer in Zoom, Teams und Meet auf.")
            }
            Section("Calls") {
                Toggle("Calls automatisch erkennen und Aufnahme vorschlagen", isOn: $library.settings.meetingDetection)
                Toggle("Aufnahme beenden, wenn der Call endet", isOn: $library.settings.autoStopWhenCallEnds)
                    .disabled(!library.settings.meetingDetection)
            }
            Section {
                Picker("Standard-Bereich", selection: $library.settings.defaultCategoryID) {
                    Text("Erster Bereich").tag(UUID?.none)
                    ForEach(library.categories) { Text("\($0.displayEmoji)  \($0.name)").tag(Optional($0.id)) }
                }
                Toggle("Hinweis zum Einverständnis anzeigen", isOn: $library.settings.showConsentReminder)
            } footer: {
                Text("Bitte hole vor jeder Aufnahme das Einverständnis aller Beteiligten ein.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Über: Version, Zweck, Quellcode.
struct AboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(AppInfo.name).font(.title.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Kostenlose, quelloffene Notizen für Vorlesungen, Meetings und Calls.\nLokal transkribiert – deine Aufnahmen bleiben auf deinem Mac.")
                .multilineTextAlignment(.center)
            if let repository = AppInfo.repository {
                HStack {
                    Link("Quellcode", destination: repository)
                    Text("·")
                    Link("Fehler melden", destination: repository.appendingPathComponent("issues"))
                }
            }
            Text("MIT-Lizenz").font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
