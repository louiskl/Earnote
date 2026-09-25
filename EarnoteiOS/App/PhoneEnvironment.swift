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
    let power = PhonePower()
    /// Weg B: Aufnahmen an den eigenen Mac übergeben
    let handoffs: HandoffSender
    let cloudSync = CloudSyncStatus()
    /// Trinkgeld-Käufe, die beim letzten Start offen blieben, abschließen
    private let tipTransactions = TipJar.finishPendingTransactions()
    let liveActivity = LiveActivityController()
    private(set) var widgets: WidgetPublisher?
    private let repository: any LibraryRepository
    /// Sprechererkennung (Earnote Pro) – für neue Aufnahmen in der Warteschlange und „Sprecher erkennen“ in der Notiz
    let diarizer: any SpeakerDiarizer

    init(storage: Storage = .standard, defaults: UserDefaults = .standard) {
        let settingsRepository = UserDefaultsSettingsRepository(defaults: defaults)
        let container: ModelContainer
        var openError: String?
        // Wird gebraucht, bevor der Store steht – deshalb hier direkt gelesen (wie am Mac)
        let syncsWithCloud = settingsRepository.loadSettings()?.syncWithCloud ?? false
        do {
            // iCloud ist aus, bis man es einschaltet (Einstellungen › Mac); gilt ab dem nächsten Start
            container = try LibraryContainer.make(url: storage.root.appendingPathComponent(LibraryContainer.fileName),
                                                  syncsWithCloud: syncsWithCloud)
        } catch {
            Log.error("Bibliothek öffnen: \(error)")
            openError = String(localized: "Die Bibliothek konnte nicht geöffnet werden (\(error.localizedDescription)). Änderungen werden in dieser Sitzung nicht gespeichert.")
            container = try! LibraryContainer.makeInMemory()
        }
        let repository = SwiftDataLibraryRepository(modelContainer: container)
        let audio = FileAudioStore(storage: storage)
        let llm = LLMFactory(platform: PlatformLLMClients())
        let diarizer = Pro.GatedDiarizer(inner: FluidSpeakerDiarizer())
        self.diarizer = diarizer
        let pipeline = ProcessingPipeline(library: repository, audio: audio, transcribers: PlatformTranscribers(), llm: llm,
                                          destinations: PhoneDestinations(), precondensed: PreCondensedStore(),
                                          diarizer: diarizer,
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
            if old.processOnlyOnPower != new.processOnlyOnPower { queue?.resume() }
        }
        LocalModels.apply(library.settings)

        self.library = library
        self.queue = queue
        self.repository = repository
        recorder = PhoneRecorder(library: library)
        let handoffs = HandoffSender(handoffs: repository, library: library, defaults: defaults)
        queue.resumes = { recording in handoffs.resumesHere(recording) }
        self.handoffs = handoffs
        background = BackgroundProcessing(queue: queue, library: library)
        background.registerChargingTask()
        recorder.finish = { id in handoffs.finish(id) }
        cloudSync.onImportFinished = { [weak library] in
            Task {
                // Neues vom Mac (Notizen, Geräte) sichtbar machen
                await library?.mergeSyncDuplicates()
                await library?.load()
                await handoffs.refresh()
            }
        }
        cloudSync.start(enabled: syncsWithCloud)
        // „Erst am Ladekabel“ und Stromsparmodus: Neues beginnt erst am Strom, Laufendes wird fertig
        queue.isHeld = { [weak library, power] in
            power.holdsProcessing(onlyWhenCharging: library?.settings.processOnlyOnPower ?? false)
        }
        power.onChange = { [weak queue] in queue?.resume() }
        recorder.onChange = { [weak recorder, liveActivity] in
            if let recorder { liveActivity.update(recorder) }
        }
        // Kontrollzentrum, Live-Aktivität, Siri: dieselben Befehle wie die Knöpfe in der App
        RecordingCommands.start = { [weak recorder] in await recorder?.start(category: nil) }
        RecordingCommands.togglePause = { [weak recorder] in recorder?.togglePause() }
        RecordingCommands.stop = { [weak recorder] in recorder?.stop() }
        RecordingCommands.markImportant = { [weak recorder] in recorder?.markImportant() }
        watchQueue()
        widgets = WidgetPublisher(library: library, recorder: recorder)
        Task { await start() }
    }

    /// Sobald die Warteschlange arbeitet (nach Stopp, Import, „Erneut versuchen“), darf sie im Hintergrund weitermachen.
    /// Wartet sie aufs Ladekabel, bittet sie iOS, sie am Strom zu wecken – auch wenn die App dann zu ist.
    private func watchQueue() {
        withObservationTracking {
            _ = queue.processingID
            _ = queue.isWaitingForPower
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.queue.processingID != nil { self.background.begin() }
                if self.queue.isWaitingForPower { self.background.scheduleCharging() }
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
        if !NoteWay.worksHere(s.ai.provider) { s.ai.provider = .none }
        return s
    }

    private func start() async {
        await library.load()
        #if DEBUG
        // Vor den Standardbereichen: Die Beispieldaten bringen ihre eigenen Bereiche mit
        await DemoLibrary.fill(library: library, repository: repository, audio: library.audio)
        #endif
        if library.categories.isEmpty {
            library.categories = RecordingCategory.defaults
        }
        queue.resumeInterruptedWork()
        await handoffs.refresh()
        #if DEBUG
        // Zum Testen im Simulator: EARNOTE_IMPORT=<Pfad> importiert eine Audiodatei vom Mac
        if let path = ProcessInfo.processInfo.environment["EARNOTE_IMPORT"], !path.isEmpty {
            library.importAudio([URL(fileURLWithPath: path)], category: library.categories.first)
        }
        #endif
    }
}

#if DEBUG
extension PhoneEnvironment {
    /// Beispieldaten wie am Mac (Bereiche, Notizen, Aufgaben, Karteikarten) – nur in Test-Fassungen
    func loadDemoLibrary() async {
        await DemoLibrary.fill(library: library, repository: repository, audio: library.audio, force: true)
        await library.load()
    }
}
#endif

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
