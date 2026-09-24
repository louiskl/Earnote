import EarnoteCore
import EarnoteML
import Foundation
import SwiftData
import UserNotifications

/// Erzeugt beim Start einmal Speicher, Warteschlange und Stores – wie `AppEnvironment` am Mac,
/// ohne Mac-Dienste (Call-Erkennung, Menüleiste, Sparkle, AppleScript-Ziele).
@MainActor
final class PhoneEnvironment {
    let library: LibraryStore
    let queue: ProcessingQueue
    let recorder: PhoneRecorder
    let background: BackgroundProcessing
    let liveActivity = LiveActivityController()

    init(storage: Storage = .standard, defaults: UserDefaults = .standard) {
        let settingsRepository = UserDefaultsSettingsRepository(defaults: defaults)
        let container: ModelContainer
        var openError: String?
        do {
            // iCloud kommt mit Weg B (docs/IPHONE.md); bis dahin bleibt die Bibliothek auf dem iPhone
            container = try LibraryContainer.make(url: storage.root.appendingPathComponent(LibraryContainer.fileName),
                                                  syncsWithCloud: false)
        } catch {
            Log.error("Bibliothek öffnen: \(error)")
            openError = String(localized: "Die Bibliothek konnte nicht geöffnet werden (\(error.localizedDescription)). Änderungen werden in dieser Sitzung nicht gespeichert.")
            container = try! LibraryContainer.makeInMemory()
        }
        let repository = SwiftDataLibraryRepository(modelContainer: container)
        let audio = FileAudioStore(storage: storage)
        let llm = LLMFactory(platform: PlatformLLMClients())
        let pipeline = ProcessingPipeline(library: repository, audio: audio, transcribers: PlatformTranscribers(), llm: llm,
                                          destinations: NoDestinations(), precondensed: PreCondensedStore(),
                                          notify: { Notifier.send($0, $1) })
        let queue = ProcessingQueue(pipeline: pipeline) {
            Task { await LocalLLMCache.shared.release() }
        }
        let library = LibraryStore(library: repository, audio: audio, settingsRepository: settingsRepository,
                                   queue: queue, llm: llm)
        library.lastError = openError
        queue.library = library
        if !library.settings.onboardingCompleted { library.settings = Self.phoneDefaults(library.settings) }
        library.onSettingsChanged = { [weak queue] old, new in
            if old.ai.localModel != new.ai.localModel { LocalModels.apply(new) }
            if old.ai != new.ai { queue?.aiProviderChanged() }
        }
        LocalModels.apply(library.settings)

        self.library = library
        self.queue = queue
        recorder = PhoneRecorder(library: library)
        background = BackgroundProcessing(queue: queue, library: library)
        recorder.onChange = { [weak recorder, liveActivity] in
            if let recorder { liveActivity.update(recorder) }
        }
        // Kontrollzentrum, Live-Aktivität, Siri: dieselben Befehle wie die Knöpfe in der App
        RecordingCommands.start = { [weak recorder] in await recorder?.start(category: nil) }
        RecordingCommands.togglePause = { [weak recorder] in recorder?.togglePause() }
        RecordingCommands.stop = { [weak recorder] in recorder?.stop() }
        watchQueue()
        Task { await start() }
    }

    /// Sobald die Warteschlange arbeitet (nach Stopp, Import, „Erneut versuchen“), darf sie im Hintergrund weitermachen
    private func watchQueue() {
        withObservationTracking { _ = queue.processingID } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.queue.processingID != nil { self.background.begin() }
                self.watchQueue()
            }
        }
    }

    /// Voreinstellungen fürs iPhone: Apples Spracherkennung (kein Download, läuft im Hintergrund sparsam),
    /// lokale KI nur, wo sie in den Speicher passt – sonst entscheidet das Onboarding (Weg C).
    static func phoneDefaults(_ settings: AppSettings) -> AppSettings {
        var s = settings
        s.transcriptionEngine = .apple
        s.language = Locale.current.language.languageCode?.identifier ?? "de"
        if !DeviceCapabilities.supportsLocalModel && s.ai.provider == .localModel { s.ai.provider = .none }
        return s
    }

    private func start() async {
        await library.load()
        if library.categories.isEmpty {
            library.categories = RecordingCategory.defaults
        }
        queue.resumeInterruptedWork()
        #if DEBUG
        // Zum Testen im Simulator: EARNOTE_IMPORT=<Pfad> importiert eine Audiodatei vom Mac
        if let path = ProcessInfo.processInfo.environment["EARNOTE_IMPORT"], !path.isEmpty {
            library.importAudio([URL(fileURLWithPath: path)], category: library.categories.first)
        }
        #endif
    }
}

/// Am iPhone gibt es keine direkten Ziele – geteilt wird über das Teilen-Menü.
struct NoDestinations: DestinationProvider {
    var all: [DestinationInfo] { [] }
    func make(_ id: String) -> (any Destination)? { nil }
    func setupProblem(_ id: String, _ settings: DestinationSettings) -> String? { nil }
}

enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func send(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
