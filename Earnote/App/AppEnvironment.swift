import EarnoteCore
import EarnoteML
import Foundation
import SwiftData

/// Erzeugt beim Start einmal alle Speicher, Dienste und Stores und verdrahtet sie miteinander.
@MainActor
final class AppEnvironment {
    /// Gemeinsamer Speicher: Das Hauptfenster liest per `@Query`, geschrieben wird über `LibraryRepository`
    let container: ModelContainer
    let libraryRepository: any LibraryRepository
    let audio: any AudioStore
    let llm: LLMFactory
    let queue: ProcessingQueue
    let library: LibraryStore
    let recorder: RecordingController
    let power: PowerSource
    /// Sprechererkennung (FluidAudio, auf dem Mac). Läuft nur, wenn „Sprecher erkennen“ an ist – nach der Aufnahme.
    let diarizer: any SpeakerDiarizer = FluidSpeakerDiarizer()
    /// Übergang bis Phase 2b: Schnittstelle der noch alten Views (Einstellungen, Einrichtung, Menüleiste, Call-Pop-up)
    /// Sucht einmal am Tag nach einer neueren Version
    let updates = AppUpdater()
    let cloudSync = CloudSyncStatus()
    /// Weg B: Aufnahmen vom iPhone über iCloud abholen
    let handoffs: HandoffWatcher

    private let storage: Storage
    private let defaults: UserDefaults

    init(storage: Storage = .standard, defaults: UserDefaults = .standard) {
        let container: ModelContainer
        var openError: String?
        // Vorgaben per Konfigurationsprofil gehen den gespeicherten Einstellungen vor
        let managed = ManagedSettings.read(from: defaults)
        // Die Einstellung wird gebraucht, bevor der Store steht – deshalb hier direkt gelesen.
        let settings = managed.apply(to: UserDefaultsSettingsRepository(defaults: defaults).loadSettings() ?? AppSettings())
        do {
            container = try LibraryContainer.make(url: storage.root.appendingPathComponent(LibraryContainer.fileName),
                                                  syncsWithCloud: settings.syncWithCloud)
        } catch {
            // Nicht einfach mit einer leeren Bibliothek weitermachen, ohne es zu sagen
            Log.error("Bibliothek öffnen: \(error)")
            openError = String(localized: "Die Bibliothek konnte nicht geöffnet werden (\(error.localizedDescription)). Änderungen werden in dieser Sitzung nicht gespeichert.")
            container = try! LibraryContainer.makeInMemory()
        }
        let libraryRepository = SwiftDataLibraryRepository(modelContainer: container)
        let audio = FileAudioStore(storage: storage)
        let llm = LLMFactory(platform: PlatformLLMClients(), managed: managed)
        let precondensed = PreCondensedStore()
        let pipeline = ProcessingPipeline(library: libraryRepository, audio: audio, transcribers: PlatformTranscribers(), llm: llm,
                                          destinations: AppDestinations(), precondensed: precondensed,
                                          diarizer: diarizer,
                                          notify: { Notifier.send($0, $1) })
        let queue = ProcessingQueue(pipeline: pipeline) {
            // Nichts mehr zu tun: geladene Modelle aus dem Speicher nehmen
            Task {
                await WhisperKitCache.shared.release()
                await LocalLLMCache.shared.release()
            }
        }
        let library = LibraryStore(library: libraryRepository, audio: audio,
                                   settingsRepository: UserDefaultsSettingsRepository(defaults: defaults),
                                   queue: queue, llm: llm, managed: managed)
        library.lastError = openError
        queue.library = library
        AudioInputDevices.removeLeftoversFromEarlierRuns()
        let power = PowerSource()
        let recorder = RecordingController(library: library, detector: MeetingDetector(), audioInputs: AudioInputDevices(),
                                           transcribers: PlatformTranscribers(), llm: llm, precondensed: precondensed,
                                           power: power, notify: { Notifier.send($0, $1) })
        // „Erst am Netzteil“: nur auf Akku zurückhalten, nicht im Stromsparmodus am Netzteil
        queue.isHeld = { [weak library, weak power] in
            (library?.settings.processOnlyOnPower ?? false) && (power?.isOnBattery ?? false)
        }
        power.onChange = { [weak recorder, weak queue] in
            recorder?.energyConditionsChanged()
            queue?.resume()
        }
        power.start()

        library.willDelete = { [weak recorder] id in recorder?.endIfActive(id) }
        library.onSettingsChanged = { [weak recorder, weak queue, updates] old, new in
            if old.appearance != new.appearance { Appearance.apply(new.appearance) }
            if old.ai.localModel != new.ai.localModel { LocalModels.apply(new) }
            if old.checkForUpdates != new.checkForUpdates { updates.automaticallyChecks = new.checkForUpdates }
            recorder?.updateDetection(enabled: new.meetingDetection)
            if old.ai != new.ai { queue?.aiProviderChanged() }
            if old.livePreviewOnBattery != new.livePreviewOnBattery { recorder?.energyConditionsChanged() }
            if old.processOnlyOnPower != new.processOnlyOnPower { queue?.resume() }
        }
        recorder.showCallPrompt = { [weak recorder, weak library] app in
            guard let recorder, let library else { return }
            FloatingPanels.shared.showCallPrompt(app: app) {
                recorder.startRecording(category: library.category(library.settings.defaultCategoryID),
                                        sourceApp: app, byCall: true)
            }
        }
        recorder.hideCallPrompt = { FloatingPanels.shared.hideCallPrompt() }

        LocalModels.apply(library.settings)
        let handoffs = HandoffWatcher(handoffs: libraryRepository, library: library, defaults: defaults,
                                      deviceName: Host.current().localizedName ?? "Mac")
        cloudSync.onImportFinished = { [weak library, weak handoffs] in
            Task {
                await library?.mergeSyncDuplicates()
                await handoffs?.check()
            }
        }
        cloudSync.start(enabled: settings.syncWithCloud)

        self.container = container
        self.libraryRepository = libraryRepository
        self.audio = audio
        self.storage = storage
        self.defaults = defaults
        self.llm = llm
        self.queue = queue
        self.library = library
        self.recorder = recorder
        self.power = power
        self.handoffs = handoffs

        if library.settings.meetingDetection { recorder.detector.start() }
        Task { await start() }
        updates.automaticallyChecks = library.settings.checkForUpdates
    }

    /// Leere Umgebung in einem temporären Ordner für die App-Tests
    static func forTestHost() -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EarnoteTestHost-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "app.earnote.testhost.\(UUID().uuidString)"
        Log.url = root.appendingPathComponent(AppInfo.logFileName)
        return AppEnvironment(storage: Storage(root: root), defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    #if DEBUG
    /// Beispieldaten für Bildschirmfotos und das Demo-Video (siehe `DemoLibrary`)
    private func addDemoLibraryIfRequested() async {
        await DemoLibrary.fill(library: library, repository: libraryRepository, audio: audio)
    }

    /// Nur Debug-Build: `EARNOTE_SANDBOX=<Ordner>` startet mit eigenem Datenordner und eigener Einstellungs-Domäne
    /// („app.earnote.sandbox“). So berühren Tests und Screenshots weder Aufnahmen noch Einstellungen des Nutzers.
    static func sandboxIfRequested() -> AppEnvironment? {
        guard let path = ProcessInfo.processInfo.environment["EARNOTE_SANDBOX"], !path.isEmpty else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        Log.url = root.appendingPathComponent(AppInfo.logFileName)
        Log.info("Sandbox-Modus: \(root.path)")
        return AppEnvironment(storage: Storage(root: root), defaults: UserDefaults(suiteName: "app.earnote.sandbox") ?? .standard)
    }
    #endif

    /// Alte Dateien einmalig übernehmen (im Hintergrund), dann die Bibliothek laden und unterbrochene Arbeit fortsetzen.
    private func start() async {
        let importer = FileLibraryImporter(reader: LegacyFileLibraryReader(storage: storage), library: libraryRepository,
                                           audio: audio, defaults: defaults)
        _ = await Task.detached(priority: .userInitiated) { await importer.runIfNeeded() }.value
        await library.load()
        await library.mergeSyncDuplicates()
        #if DEBUG
        await addDemoLibraryIfRequested()
        #endif
        queue.resumeInterruptedWork()
        handoffs.start()
    }
}
