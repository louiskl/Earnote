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
            Section {
                Toggle("Einmal am Tag nach Updates suchen", isOn: $library.settings.checkForUpdates)
            } footer: {
                Text("Fragt bei GitHub nach der neuesten Version. Das ist der einzige Netzzugriff von \(AppInfo.name), solange du keine Cloud-KI verwendest – Aufnahmen und Notizen bleiben in jedem Fall auf dem Mac.")
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
            Section {
                Toggle("Schon während der Aufnahme transkribieren", isOn: $library.settings.transcribeWhileRecording)
            } footer: {
                Text("Die Notiz ist dann kurz nach dem Ende fertig statt erst nach einer langen Rechenzeit. Kostet währenddessen etwas Akku – am Netzteil merkst du nichts davon.")
            }
            Section {
                Toggle("Aufnahme mit \(GlobalShortcut.display) aus jeder App starten und stoppen",
                       isOn: $library.settings.globalShortcut)
                    .onChange(of: library.settings.globalShortcut) { _, on in GlobalShortcut.apply(enabled: on) }
            } footer: {
                Text("Das Kürzel wirkt auch, wenn \(AppInfo.name) im Hintergrund ist – etwa mitten in der Vorlesung oder im Call. Belegt eine andere App dasselbe Kürzel, gewinnt die andere App.")
            }
            CalendarSettings()
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

/// Rückmeldung geben: Mail mit den wichtigsten Angaben oder Diagnose in die Zwischenablage,
/// dazu der Weg zum Protokoll. Ohne diese Angaben ist ein Fehlerbericht selten zu gebrauchen.
struct FeedbackButtons: View {
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        HStack {
            Button("Fehler melden …") { openURL(Diagnostics.issueURL()) }
            Button(copied ? "Diagnose kopiert" : "Diagnose kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Diagnostics.text(), forType: .string)
                copied = true
            }
            Button("Protokoll zeigen") { NSWorkspace.shared.activateFileViewerSelecting([Log.url]) }
        }
        .controlSize(.small)
    }

}

/// Angaben, die bei jeder Rückmeldung helfen – ohne Aufnahmen oder Notizen.
enum Diagnostics {
    /// Vorausgefülltes Issue auf GitHub: Die Angaben stehen schon drin, es fehlt nur die Beschreibung.
    static func issueURL() -> URL {
        var components = URLComponents(url: AppInfo.repository.appendingPathComponent("issues/new"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: ""),
            URLQueryItem(name: "body", value: "**Was ist passiert?**\n\n\n**Was hattest du erwartet?**\n\n\n"
                         + "**So lässt es sich wiederholen:**\n1. \n2. \n\n---\n```\n\(text())\n```"),
        ]
        return components?.url ?? AppInfo.repository.appendingPathComponent("issues")
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    static func text() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var model = "Mac"
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &buffer, &size, nil, 0)
            model = String(cString: buffer)
        }
        let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        return """
            \(AppInfo.name) \(version)
            macOS: \(os)
            Mac: \(model), \(memory) GB
            Letzte Protokollzeilen:
            \(Log.lastLines(20))
            """
    }
}

/// Über: Version, Zweck, Quellcode.
struct AboutSettings: View {
    @Environment(AppUpdater.self) private var updates
    @Environment(\.openURL) private var openURL

    private var version: String { updates.currentVersion }

    /// Sparkle zeigt Fund, Änderungen und Fortschritt in seinem eigenen Fenster – hier steht nur der Knopf.
    @ViewBuilder private var updateLine: some View {
        Button("Nach Updates suchen") { updates.checkNow() }
            .controlSize(.small)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(AppInfo.name).font(.title.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            updateLine
            Text("Kostenlose, quelloffene Notizen für Vorlesungen, Meetings und Calls.\nLokal transkribiert – deine Aufnahmen bleiben auf deinem Mac.")
                .multilineTextAlignment(.center)
            Link("Quellcode auf GitHub", destination: AppInfo.repository)
            FeedbackButtons()
            Text("MIT-Lizenz").font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
