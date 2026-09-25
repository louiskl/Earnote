import EarnoteCore
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

/// Feste Wurzel: drei Tabs, jeder mit eigenem Navigationsstapel. Die laufende Aufnahme sitzt im
/// `tabViewBottomAccessory` – wie „Jetzt läuft“ in Musik. Am iPad wird daraus eine Seitenleiste (`sidebarAdaptable`).
struct RootView: View {
    /// Tabs am iPhone; am iPad zusätzlich jeder Filter und jeder Bereich als Eintrag der Seitenleiste (wie am Mac)
    enum Tab: Hashable, RawRepresentable {
        case recordings, library, search
        case filter(LibraryFilter)

        init?(rawValue: String) {
            switch rawValue {
            case "recordings": self = .recordings
            case "library": self = .library
            case "search": self = .search
            default:
                guard rawValue.hasPrefix("filter:"), let filter = LibraryFilter(rawValue: String(rawValue.dropFirst(7))) else { return nil }
                self = .filter(filter)
            }
        }

        var rawValue: String {
            switch self {
            case .recordings: "recordings"
            case .library: "library"
            case .search: "search"
            case .filter(let filter): "filter:" + filter.rawValue
            }
        }
    }

    @Environment(LibraryStore.self) private var library
    @Environment(PhoneRecorder.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("tab") private var tab: Tab = .recordings
    @State private var showsRecorder = false
    /// Navigationspfade der Tabs – damit Links aus Widgets direkt an die richtige Stelle springen
    @State private var recordingsPath: [UUID] = []
    @State private var libraryPath = NavigationPath()
    @State private var filterPaths: [LibraryFilter: [UUID]] = [:]
    @State private var showsSettings = false
    @State private var importing = false
    // „Neu in Earnote“, Bewertung, Dankeschön-Paket (`FeedbackMoment`) – höchstens eins je Start der App
    @Environment(\.requestReview) private var requestReview
    @AppStorage("feedback.lastSeenVersion") private var lastSeenVersion: String?
    @AppStorage("feedback.reviewAskedVersion") private var reviewAskedVersion: String?
    @AppStorage("feedback.supporterAskedAt") private var supporterAskedAt: Double = 0
    @AppStorage(TipJar.supporterKey) private var isSupporter = false
    @State private var feedbackSheet: FeedbackMoment?
    @State private var feedbackDone = false

    var body: some View {
        @Bindable var library = library
        @Bindable var recorder = recorder
        TabView(selection: $tab) {
            SwiftUI.Tab("Aufnahmen", systemImage: "waveform", value: .recordings) {
                RecordingsView(path: $recordingsPath, showsSettings: $showsSettings, importing: $importing)
            }
            SwiftUI.Tab("Bereiche", systemImage: "square.stack.fill", value: .library) {
                LibraryView(path: $libraryPath)
            }
            // In der Seitenleiste stehen die Bereiche einzeln – der Sammel-Tab wäre dort doppelt
            .defaultVisibility(.hidden, for: .sidebar)
            SwiftUI.Tab(value: .search, role: .search) {
                SearchView()
            }
            // Nur mit Platz (iPad, breites Fenster): Am iPhone und in schmalen Fenstern landeten sie sonst in der Tab-Leiste
            if sizeClass == .regular {
            TabSection("Bibliothek") {
                filterTab(.openTasks, "Offene Aufgaben", symbol: "checklist")
                filterTab(.uncategorized, "Ohne Bereich", symbol: "tray")
                // Wie am Mac nur, wenn es etwas zu tun gibt
                if LibraryListing.counts(library.recordings).problems > 0 {
                    filterTab(.problems, "Probleme", symbol: "exclamationmark.triangle")
                }
            }
            TabSection("Bereiche") {
                ForEach(library.categories) { category in
                    filterTab(.category(category.id), category.name, symbol: category.symbol)
                }
            }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewBottomAccessory {
            RecordAccessory(showsRecorder: $showsRecorder)
        }
        .sheet(isPresented: $showsRecorder) {
            RecordSheet()
        }
        .sheet(isPresented: $showsSettings) { SettingsSheet() }
        // Audio und Video aus der Dateien-App (Sprachmemos, Aufnahmen anderer Apps)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            AudioImport.run(urls, into: library, category: nil)
            tab = .recordings
        }
        // Am iPad: Audiodateien ins Fenster ziehen
        .dropDestination(for: URL.self) { urls, _ in
            let audio = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audiovisualContent) == true }
            guard !audio.isEmpty else { return false }
            AudioImport.run(audio, into: library, category: nil)
            tab = .recordings
            return true
        }
        // Menüleiste und Tastenkürzel am iPad (`PhoneCommands`) – je Fenster
        .focusedSceneValue(\.phoneActions, PhoneActions(
            showSettings: { showsSettings = true },
            importAudio: { importing = true },
            search: { tab = .search }))
        // „Mit Earnote öffnen“ aus Sprachmemos, WhatsApp, Dateien (Dokumenttypen im Info.plist)
        .onOpenURL { url in open(url) }
        // „Mit Earnote teilen“ (Share Extension): Dateien übernehmen, sobald die App vorn und die Bibliothek geladen ist
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                collectShared()
                Task { await showFeedbackMoment() }
            }
        }
        .onChange(of: library.isLoaded) {
            collectShared()
            Task { await showFeedbackMoment() }
        }
        .fullScreenCover(isPresented: .constant(library.isLoaded && !library.settings.onboardingCompleted), onDismiss: {
            // Neue Nutzer kennen alles schon aus dem Onboarding – keine Neuigkeiten, und heute nichts mehr fragen
            lastSeenVersion = Self.appVersion
            feedbackDone = true
        }) {
            OnboardingView()
        }
        .sheet(item: $feedbackSheet) { moment in
            switch moment {
            case .whatsNew: WhatsNewView()
            default: SupporterSheet()
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
        .alert("Aufnahme", isPresented: Binding(get: { recorder.lastError != nil }, set: { if !$0 { recorder.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.lastError ?? "")
        }
    }

    /// Ein Eintrag der Seitenleiste: Liste des Filters, daneben die Notiz
    private func filterTab(_ filter: LibraryFilter, _ title: String, symbol: String) -> some TabContent<Tab> {
        SwiftUI.Tab(LocalizedStringKey(title), systemImage: symbol, value: Tab.filter(filter)) {
            RecordingSplit(path: Binding(get: { filterPaths[filter] ?? [] }, set: { filterPaths[filter] = $0 })) {
                FilteredRecordingsView(filter: filter, selection: $0)
            }
        }
        .badge(LibraryListing.counts(library.recordings).count(for: filter))
    }

    private static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// Nie während einer Aufnahme und nie über einem anderen Blatt
    private func showFeedbackMoment() async {
        guard !feedbackDone, library.isLoaded, library.settings.onboardingCompleted,
              !recorder.isRecording, !showsRecorder, !showsSettings, feedbackSheet == nil else { return }
        let version = Self.appVersion
        let moment = FeedbackMoment.next(
            version: version, whatsNewVersion: WhatsNew.version,
            finishedNotes: library.recordings.count { $0.status == .done }, isSupporter: isSupporter,
            lastSeenVersion: lastSeenVersion, reviewAskedVersion: reviewAskedVersion,
            supporterAskedAt: supporterAskedAt > 0 ? Date(timeIntervalSince1970: supporterAskedAt) : nil)
        switch moment {
        case .whatsNew:
            lastSeenVersion = version
            feedbackSheet = .whatsNew
        case .review:
            reviewAskedVersion = version
            // Apples eigener Sterne-Dialog; iOS zeigt ihn höchstens dreimal im Jahr
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        case .supporter:
            // Ohne Trinkgelder im Store (kein Netz, Vertrag noch nicht aktiv) gibt es nichts zu zeigen
            guard !(await TipJar.products()).isEmpty else { return }
            supporterAskedAt = Date.now.timeIntervalSince1970
            feedbackSheet = .supporter
        case nil:
            return
        }
        feedbackDone = true
    }

    private func collectShared() {
        guard library.isLoaded else { return }
        let files = ShareInbox.pending()
        guard !files.isEmpty else { return }
        library.importAudio(files, category: nil)
        files.forEach(ShareInbox.remove)
        tab = .recordings
    }

    /// Dateien (Teilen › „Mit Earnote öffnen“) und Links aus Widgets (`EarnoteLink`)
    private func open(_ url: URL) {
        if url.isFileURL {
            AudioImport.run([url], into: library, category: nil)
            tab = .recordings
            return
        }
        guard url.scheme == EarnoteLink.scheme else { return }
        switch url.host() {
        case "recording":
            guard let id = UUID(uuidString: url.lastPathComponent), library.recording(id) != nil else { return }
            tab = .recordings
            recordingsPath = [id]
        case "tasks":
            tab = .library
            libraryPath = NavigationPath([LibraryFilter.openTasks])
        case "record":
            Task {
                await recorder.start(category: nil)
                if recorder.isRecording { showsRecorder = true }
            }
        default:
            break
        }
    }
}

/// Leiste über den Tabs: „Aufnehmen“ – oder, während aufgenommen wird, Laufzeit mit Pause und Stopp.
private struct RecordAccessory: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PhoneRecorder.self) private var recorder
    @Binding var showsRecorder: Bool

    var body: some View {
        if recorder.isRecording {
            HStack(spacing: 12) {
                Button { showsRecorder = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recorder.isPaused ? "pause.circle.fill" : "record.circle")
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse, isActive: !recorder.isPaused)
                        ElapsedText()
                            .monospacedDigit()
                        if let name = recorder.categoryName {
                            Text(name).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.isPaused ? "Aufnahme pausiert, öffnen" : "Aufnahme läuft, öffnen")
                Button(recorder.isPaused ? "Fortsetzen" : "Pause",
                       systemImage: recorder.isPaused ? "play.fill" : "pause.fill") { recorder.togglePause() }
                    .labelStyle(.iconOnly)
                Button("Stopp", systemImage: "stop.fill") { recorder.stop() }
                    .labelStyle(.iconOnly)
            }
            .padding(.horizontal)
            .sensoryFeedback(.impact, trigger: recorder.isPaused)
        } else {
            Button { start(nil) } label: {
                Label {
                    Text("Aufnehmen").fontWeight(.semibold)
                } icon: {
                    Image(systemName: "record.circle").foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Section("Aufnehmen in …") {
                    ForEach(library.categories) { category in
                        Button(category.name, systemImage: category.symbol) { start(category) }
                    }
                }
            }
        }
    }

    private func start(_ category: RecordingCategory?) {
        Task {
            await recorder.start(category: category)
            if recorder.isRecording { showsRecorder = true }
        }
    }
}

/// Laufzeit, die sich jede Sekunde selbst neu zeichnet
struct ElapsedText: View {
    @Environment(PhoneRecorder.self) private var recorder

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Duration.seconds(recorder.elapsed(at: context.date)).formatted(.time(pattern: .hourMinuteSecond)))
        }
    }
}

extension FeedbackMoment: @retroactive Identifiable {
    public var id: Self { self }
}

/// Das Dankeschön-Paket, von selbst angeboten (höchstens einmal im Monat)
private struct SupporterSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SupporterView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Später") { dismiss() } }
                }
        }
    }
}
