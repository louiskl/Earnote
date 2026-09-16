import EarnoteCore
import EarnoteML
import Foundation

/// Erzeugt beim Start einmal alle Speicher, Dienste und Stores und verdrahtet sie miteinander.
@MainActor
final class AppEnvironment {
    let repository: any RecordingRepository
    let llm: LLMFactory
    let queue: ProcessingQueue
    let library: LibraryStore
    let recorder: RecordingController
    /// Übergang bis Phase 2: die bisherige Schnittstelle der Views
    let appState: AppState

    init(storage: Storage = .standard, defaults: UserDefaults = .standard) {
        let repository = FileRecordingRepository(storage: storage)
        let llm = LLMFactory(platform: PlatformLLMClients())
        let pipeline = ProcessingPipeline(repository: repository, transcribers: PlatformTranscribers(), llm: llm,
                                          destinations: AppDestinations(), notify: { Notifier.send($0, $1) })
        let queue = ProcessingQueue(pipeline: pipeline) {
            // Nichts mehr zu tun: geladene Modelle aus dem Speicher nehmen
            Task {
                await WhisperKitCache.shared.release()
                await LocalLLMCache.shared.release()
            }
        }
        let library = LibraryStore(repository: repository,
                                   settingsRepository: UserDefaultsSettingsRepository(defaults: defaults), queue: queue)
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

        self.repository = repository
        self.llm = llm
        self.queue = queue
        self.library = library
        self.recorder = recorder
        self.appState = appState

        queue.resumeInterruptedWork()
        if library.settings.meetingDetection { recorder.detector.start() }
    }
}
