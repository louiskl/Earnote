import EarnoteCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Allgemein", systemImage: "gearshape") }
            page { PermissionsPanel() }.tabItem { Label("Berechtigungen", systemImage: "lock.shield") }
            page { TranscriptionPanel() }.tabItem { Label("Transkription", systemImage: "waveform") }
            page { AIPanel() }.tabItem { Label("KI", systemImage: "sparkles") }
            page { DestinationsPanel() }.tabItem { Label("Ziele", systemImage: "square.and.arrow.up") }
            page { CategoriesPanel() }.tabItem { Label("Bereiche", systemImage: "square.grid.2x2") }
            AboutView().tabItem { Label("Über", systemImage: "info.circle") }
        }
        .frame(width: 680, height: 620)
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView { content().padding(24) }
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var app: AppState
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Start") {
                Toggle("\(AppInfo.name) beim Start des Macs automatisch öffnen", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LoginItem.set(v) }
                Toggle("Fenster beim Start zeigen (sonst nur in der Menüleiste)", isOn: $app.settings.openWindowAtLaunch)
            }
            Section("Call-Erkennung") {
                Toggle("Calls automatisch erkennen und Aufnahme vorschlagen", isOn: $app.settings.meetingDetection)
                Toggle("Aufnahme automatisch beenden, wenn der Call endet", isOn: $app.settings.autoStopWhenCallEnds)
                    .disabled(!app.settings.meetingDetection)
            }
            Section("Aufnahme") {
                Toggle("Systemton mit aufnehmen (Teilnehmer in Calls)", isOn: $app.settings.recordSystemAudio)
                Toggle("Hinweis zum Einverständnis anzeigen", isOn: $app.settings.showConsentReminder)
                Picker("Standard-Bereich", selection: $app.settings.defaultCategoryID) {
                    Text("Erster Bereich").tag(UUID?.none)
                    ForEach(app.categories) { Text("\($0.displayEmoji)  \($0.name)").tag(Optional($0.id)) }
                }
            }
            Section("Speicher") {
                Toggle("Audiodateien nach der Verarbeitung behalten", isOn: $app.settings.keepAudioFiles)
                Text("Behaltene Audiodateien ermöglichen eine spätere Neu-Transkription. 1 Stunde ≈ 250–600 MB.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Datenordner öffnen") { NSWorkspace.shared.open(Storage.standard.root) }
                    Button("Protokoll öffnen") { NSWorkspace.shared.open(Log.url) }
                }
            }
            Section {
                Button("Einrichtungsassistent erneut starten") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(AppInfo.name).font(Theme.Font.title)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                .foregroundStyle(.secondary)
            Text("Kostenlose, quelloffene KI-Notizen für Meetings, Calls und Vorlesungen.\nLokal transkribiert. Deine Daten, deine Wahl.")
                .multilineTextAlignment(.center)
            if let repository = AppInfo.repository {
                HStack {
                    Link("GitHub", destination: repository)
                    Text("·")
                    Link("Fehler melden", destination: repository.appendingPathComponent("issues"))
                }
            }
            Text("MIT-Lizenz").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

