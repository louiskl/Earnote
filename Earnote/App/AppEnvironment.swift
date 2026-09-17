import EarnoteCore
import EarnoteML
import Foundation
import SwiftData

/// Erzeugt beim Start einmal alle Speicher, Dienste und Stores und verdrahtet sie miteinander.
@MainActor
final class AppEnvironment {
    let libraryRepository: any LibraryRepository
    let audio: any AudioStore
    let llm: LLMFactory
    let queue: ProcessingQueue
    let library: LibraryStore
    let recorder: RecordingController
    /// Übergang bis Phase 2: die bisherige Schnittstelle der Views
    let appState: AppState

    private let storage: Storage
    private let defaults: UserDefaults

    init(storage: Storage = .standard, defaults: UserDefaults = .standard) {
        let container: ModelContainer
        var openError: String?
        do {
            container = try LibraryContainer.make(url: storage.root.appendingPathComponent(LibraryContainer.fileName))
        } catch {
            // Nicht einfach mit einer leeren Bibliothek weitermachen, ohne es zu sagen
            Log.error("Bibliothek öffnen: \(error)")
            openError = "Die Bibliothek konnte nicht geöffnet werden (\(error.localizedDescription)). "
                + "Änderungen werden in dieser Sitzung nicht gespeichert."
            container = try! LibraryContainer.makeInMemory()
        }
        let libraryRepository = SwiftDataLibraryRepository(modelContainer: container)
        let audio = FileAudioStore(storage: storage)
        let llm = LLMFactory(platform: PlatformLLMClients())
        let pipeline = ProcessingPipeline(library: libraryRepository, audio: audio, transcribers: PlatformTranscribers(), llm: llm,
                                          destinations: AppDestinations(), notify: { Notifier.send($0, $1) })
        let queue = ProcessingQueue(pipeline: pipeline) {
            // Nichts mehr zu tun: geladene Modelle aus dem Speicher nehmen
            Task {
                await WhisperKitCache.shared.release()
                await LocalLLMCache.shared.release()
            }
        }
        let library = LibraryStore(library: libraryRepository, audio: audio,
                                   settingsRepository: UserDefaultsSettingsRepository(defaults: defaults), queue: queue)
        library.lastError = openError
        queue.library = library
        let recorder = RecordingController(library: library, detector: MeetingDetector(), notify: { Notifier.send($0, $1) })
        let appState = AppState(library: library, recorder: recorder, llm: llm)

        library.willDelete = { [weak recorder] id in recorder?.endIfActive(id) }
        library.onSettingsChanged = { [weak recorder, weak queue] old, new in
            recorder?.updateDetection(enabled: new.meetingDetection)
            if old.ai != new.ai { queue?.aiProviderChanged() }
        }
        recorder.showCallPrompt = { [weak appState] app in
            guard let appState else { return }
            FloatingPanels.shared.showCallPrompt(app: app, state: appState)
        }
        recorder.hideCallPrompt = { FloatingPanels.shared.hideCallPrompt() }

        self.libraryRepository = libraryRepository
        self.audio = audio
        self.storage = storage
        self.defaults = defaults
        self.llm = llm
        self.queue = queue
        self.library = library
        self.recorder = recorder
        self.appState = appState

        if library.settings.meetingDetection { recorder.detector.start() }
        Task { await start() }
    }

    /// Leere Umgebung in einem temporären Ordner für die App-Tests
    static func forTestHost() -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EarnoteTestHost-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "app.earnote.testhost.\(UUID().uuidString)"
        Log.url = root.appendingPathComponent(AppInfo.logFileName)
        return AppEnvironment(storage: Storage(root: root), defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    /// Alte Dateien einmalig übernehmen (im Hintergrund), dann die Bibliothek laden und unterbrochene Arbeit fortsetzen.
    private func start() async {
        let importer = FileLibraryImporter(reader: LegacyFileLibraryReader(storage: storage), library: libraryRepository,
                                           audio: audio, defaults: defaults)
        _ = await Task.detached(priority: .userInitiated) { await importer.runIfNeeded() }.value
        await library.load()
        queue.resumeInterruptedWork()
    }
}
