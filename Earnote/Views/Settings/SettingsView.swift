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
    @Environment(CloudSyncStatus.self) private var cloudSync
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        @Bindable var library = library
        Form {
            if !library.managed.isEmpty {
                Section {
                    Label("Einige Einstellungen gibt deine Organisation vor.", systemImage: "building.2")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Erscheinungsbild", selection: $library.settings.appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Einmal am Tag nach Updates suchen", isOn: $library.settings.checkForUpdates)
                    .lockedByOrganization(library.managed.isLocked(.checkForUpdates))
            } footer: {
                Text("Fragt bei GitHub nach der neuesten Version. Das ist der einzige Netzzugriff von \(AppInfo.name), solange du keine Cloud-KI verwendest – Aufnahmen und Notizen bleiben in jedem Fall auf dem Mac.")
            }
            Section {
                Toggle("Bibliothek über iCloud synchronisieren", isOn: $library.settings.syncWithCloud)
                    .lockedByOrganization(library.managed.isLocked(.syncWithCloud))
                if library.settings.syncWithCloud {
                    LabeledContent("Stand") { Text(cloudSync.text).foregroundStyle(.secondary) }
                }
            } footer: {
                Text("Noch in Erprobung. Aufnahmedaten, Transkripte, Notizen, Bereiche und Wörterbuch stehen dann auf allen Macs mit derselben Apple-ID. Die Audiodateien bleiben immer lokal. Gilt ab dem nächsten Start von \(AppInfo.name).")
            }
            Section("Start") {
                Toggle("\(AppInfo.name) beim Start des Macs automatisch öffnen", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.set(on) }
                Toggle("Fenster beim Start zeigen", isOn: $library.settings.openWindowAtLaunch)
            }
            Section {
                Toggle("Audiodateien nach der Verarbeitung behalten", isOn: $library.settings.keepAudioFiles)
                    .lockedByOrganization(library.managed.isLocked(.keepAudioFiles))
                StorageCleanupRow()
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

extension View {
    /// Von der Organisation per Konfigurationsprofil vorgegeben: ausgegraut, mit Erklärung beim Darüberfahren
    @ViewBuilder
    func lockedByOrganization(_ locked: Bool) -> some View {
        if locked {
            disabled(true).help("Von deiner Organisation vorgegeben")
        } else {
            self
        }
    }
}

/// Aufnahme: Mikrofon, Systemton, Call-Erkennung und der Standard-Bereich.
struct RecordingSettings: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder

    var body: some View {
        @Bindable var library = library
        Form {
            Section("Mikrofon") {
                MicrophoneSettings()
            }
            Section {
                Toggle("Systemton mitaufnehmen", isOn: $library.settings.recordSystemAudio)
            } footer: {
                Text("Für Zoom, Teams, Meet und Videos. Im Hörsaal brauchst du ihn nicht – bei erkannten Calls nimmt Earnote ihn immer mit.")
            }
            Section {
                Toggle("Schon während der Aufnahme transkribieren", isOn: $library.settings.transcribeWhileRecording)
            } footer: {
                Text("Die Notiz ist dann kurz nach dem Ende fertig statt erst nach einer langen Rechenzeit. Kostet währenddessen etwas Akku – am Netzteil merkst du nichts davon.")
            }
            BatterySettings(power: recorder.power)
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
                    Text("Ohne Bereich (Alle Aufnahmen)").tag(UUID?.none)
                    ForEach(library.categories) { Text("\($0.displayEmoji)  \($0.name)").tag(Optional($0.id)) }
                }
                Toggle("Hinweis zum Einverständnis anzeigen", isOn: $library.settings.showConsentReminder)
                    .lockedByOrganization(library.managed.isLocked(.showConsentReminder))
            } footer: {
                Text("Bitte hole vor jeder Aufnahme das Einverständnis aller Beteiligten ein.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Was im Akkubetrieb (und im Stromsparmodus) gespart wird. Voreingestellt ist: sparen, wo es
/// niemand merkt – Vorschau und Vorverdichten aus, die Notiz entsteht trotzdem gleich.
private struct BatterySettings: View {
    let power: PowerSource
    @Environment(LibraryStore.self) private var library

    private var state: String {
        switch (power.isOnBattery, power.isLowPowerMode) {
        case (true, true): return String(localized: "Akku, Stromsparmodus")
        case (true, false): return String(localized: "Akku")
        case (false, true): return String(localized: "Netzteil, Stromsparmodus")
        case (false, false): return String(localized: "Netzteil")
        }
    }

    var body: some View {
        @Bindable var library = library
        Section {
            LabeledContent("Gerade") { Text(state).foregroundStyle(.secondary) }
            Toggle("Live-Mitschrift auch im Akkubetrieb", isOn: $library.settings.livePreviewOnBattery)
            if DeviceCapabilities.memoryGB >= 15.5 {
                Toggle("Auch im Stromsparmodus schon während der Aufnahme zusammenfassen",
                       isOn: $library.settings.condenseOnBattery)
                    .disabled(!library.settings.transcribeWhileRecording)
            }
            Toggle("Aufnahmen erst am Netzteil verarbeiten", isOn: $library.settings.processOnlyOnPower)
        } header: {
            Text("Akku")
        } footer: {
            Text("Im Akkubetrieb spart \(AppInfo.name) Strom, wo du es nicht merkst: Die Live-Mitschrift ist nur eine Vorschau, die Mitschrift entsteht trotzdem. Zusammengefasst wird schon während der Aufnahme – dieselbe Arbeit wie danach, nur früher –, außer im Stromsparmodus. Mit „erst am Netzteil“ beginnt die Verarbeitung, sobald der Mac am Strom hängt – das spart am meisten, die Notiz kommt dafür später.")
        }
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
            Link("Earnote unterstützen", destination: AppInfo.sponsor)
            FeedbackButtons()
            Text("MIT-Lizenz").font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Wie viel Platz die Audiodateien belegen – und der kurze Weg, alte davon loszuwerden.
/// Notizen und Transkripte bleiben dabei immer erhalten.
private struct StorageCleanupRow: View {
    @Environment(LibraryStore.self) private var library

    @State private var bytes: Int64 = 0
    @State private var pending: Period?

    private enum Period: Int, Identifiable, CaseIterable {
        case months3 = 90, month = 30, all = 0
        var id: Int { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .months3: return "Älter als drei Monate"
            case .month: return "Älter als ein Monat"
            case .all: return "Alle Audiodateien"
            }
        }

        var date: Date {
            rawValue == 0 ? .distantFuture : Calendar.current.date(byAdding: .day, value: -rawValue, to: Date()) ?? Date()
        }
    }

    var body: some View {
        LabeledContent("Audiodateien") {
            HStack {
                Text(bytes > 0 ? bytes.formatted(.byteCount(style: .file)) : "–")
                    .foregroundStyle(.secondary)
                Menu("Aufräumen …") {
                    ForEach(Period.allCases) { period in
                        Button(period.label) { pending = period }
                    }
                }
                .fixedSize()
                .disabled(bytes == 0)
            }
        }
        .task { bytes = library.audioBytes }
        .confirmationDialog(pending.map { confirmTitle($0) } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Audio löschen", role: .destructive) {
                if let pending { library.deleteAudio(olderThan: pending.date) }
                pending = nil
                bytes = library.audioBytes
            }
        } message: {
            Text("Notizen und Transkripte bleiben erhalten. Nur das Nachhören und das erneute Transkribieren fallen weg.")
        }
    }

    private func confirmTitle(_ period: Period) -> String {
        let count = library.recordingsWithAudio(olderThan: period.date)
        return count == 1
            ? String(localized: "Audio von einer Aufnahme löschen?")
            : String(localized: "Audio von \(count) Aufnahmen löschen?")
    }
}
