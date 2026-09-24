import EarnoteCore
import SwiftUI

/// Feste Wurzel: drei Tabs, jeder mit eigenem Navigationsstapel. Die laufende Aufnahme sitzt im
/// `tabViewBottomAccessory` – wie „Jetzt läuft“ in Musik.
struct RootView: View {
    enum Tab: String, Hashable { case recordings, library, search }

    @Environment(LibraryStore.self) private var library
    @Environment(PhoneRecorder.self) private var recorder
    @SceneStorage("tab") private var tab: Tab = .recordings
    @State private var showsRecorder = false
    /// Navigationspfade der Tabs – damit Links aus Widgets direkt an die richtige Stelle springen
    @State private var recordingsPath: [UUID] = []
    @State private var libraryPath = NavigationPath()

    var body: some View {
        @Bindable var library = library
        @Bindable var recorder = recorder
        TabView(selection: $tab) {
            SwiftUI.Tab("Aufnahmen", systemImage: "waveform", value: .recordings) {
                RecordingsView(path: $recordingsPath)
            }
            SwiftUI.Tab("Bereiche", systemImage: "square.stack.fill", value: .library) {
                LibraryView(path: $libraryPath)
            }
            SwiftUI.Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        .tabViewBottomAccessory {
            RecordAccessory(showsRecorder: $showsRecorder)
        }
        .sheet(isPresented: $showsRecorder) {
            RecordSheet()
        }
        // „Mit Earnote öffnen“ aus Sprachmemos, WhatsApp, Dateien (Dokumenttypen im Info.plist)
        .onOpenURL { url in open(url) }
        .fullScreenCover(isPresented: .constant(library.isLoaded && !library.settings.onboardingCompleted)) {
            OnboardingView()
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
