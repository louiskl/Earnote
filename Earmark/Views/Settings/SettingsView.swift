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
            page { CategoriesPanel() }.tabItem { Label("Kategorien", systemImage: "folder") }
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
                Toggle("Beim Anmelden automatisch starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LoginItem.set(v) }
            }
            Section("Call-Erkennung") {
                Toggle("Calls automatisch erkennen und Aufnahme vorschlagen", isOn: $app.settings.meetingDetection)
                Toggle("Aufnahme automatisch beenden, wenn der Call endet", isOn: $app.settings.autoStopWhenCallEnds)
                    .disabled(!app.settings.meetingDetection)
            }
            Section("Aufnahme") {
                Toggle("Systemton mit aufnehmen (Teilnehmer in Calls)", isOn: $app.settings.recordSystemAudio)
                Toggle("Hinweis zum Einverständnis anzeigen", isOn: $app.settings.showConsentReminder)
                Picker("Standard-Kategorie", selection: $app.settings.defaultCategoryID) {
                    Text("Erste Kategorie").tag(UUID?.none)
                    ForEach(app.categories) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Section("Speicher") {
                Toggle("Audiodateien nach der Verarbeitung behalten", isOn: $app.settings.keepAudioFiles)
                Text("Behaltene Audiodateien ermöglichen eine spätere Neu-Transkription. 1 Stunde ≈ 250–600 MB.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Datenordner öffnen") { NSWorkspace.shared.open(Storage.root) }
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
            Text("Earmark").font(.system(size: 26, weight: .bold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                .foregroundStyle(.secondary)
            Text("Kostenlose, quelloffene KI-Notizen für Meetings, Calls und Vorlesungen.\nLokal transkribiert. Deine Daten, deine Wahl.")
                .multilineTextAlignment(.center)
            HStack {
                Link("GitHub", destination: AppInfo.repository)
                Text("·")
                Link("Fehler melden", destination: AppInfo.repository.appendingPathComponent("issues"))
            }
            Text("MIT-Lizenz").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

enum AppInfo {
    /// Nach dem Hochladen auf GitHub hier die eigene Repository-Adresse eintragen.
    static let repository = URL(string: "https://github.com/YOUR-USERNAME/earmark")!
}
