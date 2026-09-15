import Combine
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case all, category(UUID), openTasks, failed
}

struct MainView: View {
    @EnvironmentObject var app: AppState
    @State private var sidebar: SidebarItem? = .all
    @State private var search = ""
    @State private var showOnboarding = false
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebar)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } content: {
            RecordingListView(filter: sidebar ?? .all, search: search)
                .navigationSplitViewColumnWidth(min: 280, ideal: 330)
        } detail: {
            if let id = app.activeRecordingID, app.selection == id || app.selection == nil {
                LiveRecordingView()
            } else if let id = app.selection, app.recording(id) != nil {
                RecordingDetailView(recordingID: id)
                    .id(id)
            } else {
                EmptyDetailView()
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Aufnahmen durchsuchen")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ImportButton()
                RecordToolbarButton()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers); return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
                    .overlay(Text("Audiodatei hier ablegen").font(.title3.bold()).foregroundStyle(Theme.accent))
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
                .interactiveDismissDisabled()
        }
        .alert("Hinweis", isPresented: Binding(get: { app.lastError != nil }, set: { if !$0 { app.lastError = nil } })) {
            Button("OK") { app.lastError = nil }
        } message: {
            Text(app.lastError ?? "")
        }
        .onAppear { if !app.settings.onboardingCompleted { showOnboarding = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in showOnboarding = true }
        .frame(minWidth: 900, minHeight: 560)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    let cat: RecordingCategory? = {
                        if case .category(let id) = sidebar { return app.category(id) }
                        return nil
                    }()
                    app.importAudio([url], category: cat)
                }
            }
        }
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("earmark.showOnboarding")
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Alle Aufnahmen", systemImage: "tray.full").tag(SidebarItem.all)
                    .badge(app.recordings.count)
                Label("Offene Aufgaben", systemImage: "checklist").tag(SidebarItem.openTasks)
                    .badge(app.recordings.filter { $0.taskCount > 0 }.count)
                if app.recordings.contains(where: { $0.status == .failed }) {
                    Label("Probleme", systemImage: "exclamationmark.triangle").tag(SidebarItem.failed)
                        .badge(app.recordings.filter { $0.status == .failed }.count)
                }
            }
            Section("Kategorien") {
                ForEach(app.categories) { cat in
                    HStack(spacing: 8) {
                        Image(systemName: cat.symbol).foregroundStyle(cat.color).frame(width: 18)
                        Text(cat.name)
                    }
                    .tag(SidebarItem.category(cat.id))
                    .badge(app.recordings.filter { $0.categoryID == cat.id }.count)
                }
                SettingsLink {
                    Label("Kategorien bearbeiten …", systemImage: "plus.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { SidebarRecordCard().padding(12) }
    }
}

struct SidebarRecordCard: View {
    @EnvironmentObject var app: AppState
    @State private var categoryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.isRecording {
                RecordingStatusCompact()
            } else {
                HStack {
                    Text("Neue Aufnahme").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let call = app.detector.activeCallApp {
                        Label(call, systemImage: "phone.fill").font(.system(size: 10)).foregroundStyle(.green).lineLimit(1)
                    }
                }
                Picker("", selection: $categoryID) {
                    ForEach(app.categories) { c in
                        Label(c.name, systemImage: c.symbol).tag(Optional(c.id))
                    }
                }
                .labelsHidden()
                Button {
                    app.startRecording(category: app.category(categoryID), sourceApp: app.detector.activeCallApp)
                } label: {
                    Label("Aufnahme starten", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card(padding: 12)
        .onAppear { categoryID = categoryID ?? app.settings.defaultCategoryID ?? app.categories.first?.id }
    }
}

struct RecordingStatusCompact: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var meter = AppState.shared.meter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                    .opacity(Int(meter.elapsed) % 2 == 0 ? 1 : 0.35)
                Text("Aufnahme läuft").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(TimeFormat.duration(meter.elapsed)).font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            LevelMeter(level: max(meter.mic, meter.system), bars: 20)
            Button { app.stopRecording() } label: {
                Label("Stoppen & auswerten", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(color: .primary.opacity(0.85)))
        }
    }
}

struct RecordToolbarButton: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        if app.isRecording {
            Button { app.stopRecording() } label: { Label("Stoppen", systemImage: "stop.circle.fill") }
                .tint(Theme.accent)
        } else {
            Menu {
                ForEach(app.categories) { c in
                    Button { app.startRecording(category: c, sourceApp: app.detector.activeCallApp) } label: {
                        Label(c.name, systemImage: c.symbol)
                    }
                }
            } label: {
                Label("Aufnehmen", systemImage: "record.circle")
            } primaryAction: {
                app.startRecording(category: nil, sourceApp: app.detector.activeCallApp)
            }
            .help("Aufnahme starten")
        }
    }
}

struct ImportButton: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Button {
            ImportHelper.pickAndImport()
        } label: {
            Label("Importieren", systemImage: "square.and.arrow.down")
        }
        .help("Vorhandene Audiodatei transkribieren")
    }
}

struct EmptyDetailView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(app.recordings.isEmpty ? "Willkommen bei Earmark" : "Keine Aufnahme ausgewählt")
                .font(.title2.bold())
            Text(app.recordings.isEmpty
                 ? "Starte eine Aufnahme, sobald dein Meeting, Call oder deine Vorlesung beginnt.\nEarmark transkribiert lokal und erstellt dir automatisch Notizen."
                 : "Wähle links eine Aufnahme aus oder starte eine neue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if !app.isRecording {
                Button { app.startRecording(category: nil, sourceApp: app.detector.activeCallApp) } label: {
                    Label("Aufnahme starten", systemImage: "record.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("Tipp: Audiodateien einfach ins Fenster ziehen.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Liste

struct RecordingListView: View {
    @EnvironmentObject var app: AppState
    let filter: SidebarItem
    let search: String

    private var items: [Recording] {
        app.recordings.filter { r in
            switch filter {
            case .all: break
            case .category(let id): if r.categoryID != id { return false }
            case .openTasks: if r.taskCount == 0 { return false }
            case .failed: if r.status != .failed { return false }
            }
            guard !search.isEmpty else { return true }
            let q = search.lowercased()
            return r.title.lowercased().contains(q) || (r.summaryTitle?.lowercased().contains(q) ?? false)
                || (app.category(r.categoryID)?.name.lowercased().contains(q) ?? false)
        }
    }

    private var grouped: [(String, [Recording])] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEEE, d. MMMM"
        var groups: [(String, [Recording])] = []
        for r in items {
            let key: String
            if cal.isDateInToday(r.startedAt) { key = "Heute" }
            else if cal.isDateInYesterday(r.startedAt) { key = "Gestern" }
            else { key = df.string(from: r.startedAt) }
            if let i = groups.firstIndex(where: { $0.0 == key }) { groups[i].1.append(r) } else { groups.append((key, [r])) }
        }
        return groups
    }

    var body: some View {
        List(selection: $app.selection) {
            ForEach(grouped, id: \.0) { title, recs in
                Section(title) {
                    ForEach(recs) { r in
                        RecordingRow(recording: r).tag(r.id)
                            .contextMenu { RecordingActions(recordingID: r.id) }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if items.isEmpty {
                Text(search.isEmpty ? "Noch keine Aufnahmen" : "Keine Treffer")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RecordingRow: View {
    @EnvironmentObject var app: AppState
    let recording: Recording

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(category: app.category(recording.categoryID), size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.summaryTitle ?? recording.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(recording.startedAt, style: .time)
                    Text("·")
                    Text(TimeFormat.duration(recording.duration))
                    if let source = recording.sourceApp {
                        Text("·")
                        Text(source).lineLimit(1)
                    }
                    if recording.taskCount > 0 {
                        Text("·")
                        Label("\(recording.taskCount)", systemImage: "checklist").labelStyle(.titleAndIcon)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                if recording.status != .done { StatusBadge(recording: recording) }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecordingActions: View {
    @EnvironmentObject var app: AppState
    let recordingID: UUID

    var body: some View {
        let hasAudio = app.hasAudio(recordingID)
        Button("Erneut exportieren") { app.reexport(recordingID) }
        Button("Neu zusammenfassen") { app.reprocess(recordingID, retranscribe: false) }
        Button("Neu transkribieren") { app.reprocess(recordingID, retranscribe: true) }.disabled(!hasAudio)
        Divider()
        Menu("Kategorie") {
            ForEach(app.categories) { c in
                Button(c.name) { app.setCategory(recordingID, c.id) }
            }
        }
        Button("Im Finder zeigen") { app.revealInFinder(recordingID) }
        Divider()
        Button("Löschen", role: .destructive) { app.delete(recordingID) }
    }
}
