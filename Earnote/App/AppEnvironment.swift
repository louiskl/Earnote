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
    /// Übergang bis Phase 2b: Schnittstelle der noch alten Views (Einstellungen, Einrichtung, Menüleiste, Call-Pop-up)
    let appState: AppState
    /// Sucht einmal am Tag nach einer neueren Version
    let updates = AppUpdater()
    let cloudSync = CloudSyncStatus()

    private let storage: Storage
    private let defaults: UserDefaults

    init(storage: Storage = .standard, defaults: UserDefaults = .standard) {
        let container: ModelContainer
        var openError: String?
        // Die Einstellung wird gebraucht, bevor der Store steht – deshalb hier direkt gelesen.
        let settings = UserDefaultsSettingsRepository(defaults: defaults).loadSettings() ?? AppSettings()
        do {
            container = try LibraryContainer.make(url: storage.root.appendingPathComponent(LibraryContainer.fileName),
                                                  syncsWithCloud: settings.syncWithCloud)
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
        let precondensed = PreCondensedStore()
        let pipeline = ProcessingPipeline(library: libraryRepository, audio: audio, transcribers: PlatformTranscribers(), llm: llm,
                                          destinations: AppDestinations(), precondensed: precondensed,
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
                                   queue: queue, llm: llm)
        library.lastError = openError
        queue.library = library
        AudioInputDevices.removeLeftoversFromEarlierRuns()
        let recorder = RecordingController(library: library, detector: MeetingDetector(), audioInputs: AudioInputDevices(),
                                           transcribers: PlatformTranscribers(), llm: llm, precondensed: precondensed,
                                           notify: { Notifier.send($0, $1) })
        let appState = AppState(library: library, recorder: recorder, llm: llm)

        library.willDelete = { [weak recorder] id in recorder?.endIfActive(id) }
        library.onSettingsChanged = { [weak recorder, weak queue, updates] old, new in
            if old.appearance != new.appearance { Appearance.apply(new.appearance) }
            if old.ai.localModel != new.ai.localModel { LocalModels.apply(new) }
            if old.checkForUpdates != new.checkForUpdates { updates.automaticallyChecks = new.checkForUpdates }
            recorder?.updateDetection(enabled: new.meetingDetection)
            if old.ai != new.ai { queue?.aiProviderChanged() }
        }
        recorder.showCallPrompt = { [weak appState] app in
            guard let appState else { return }
            FloatingPanels.shared.showCallPrompt(app: app, state: appState)
        }
        recorder.hideCallPrompt = { FloatingPanels.shared.hideCallPrompt() }

        LocalModels.apply(library.settings)
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
        self.appState = appState

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
    /// Nur Debug-Build: `EARNOTE_DEMO_LIBRARY=1` legt im Sandbox-Ordner eine Beispielaufnahme mit Notiz
    /// und Transkript an – für Bildschirmfotos und den Design-Review, ohne echte Daten anzufassen.
    private func addDemoLibraryIfRequested() async {
        guard ProcessInfo.processInfo.environment["EARNOTE_DEMO_LIBRARY"] != nil,
              (try? await libraryRepository.recordings())?.isEmpty == true else { return }
        // Auf Englisch gestartet? Dann auch englische Beispieldaten – sonst passen die Bildschirmfotos nicht.
        let english = Locale.preferredLanguages.first?.hasPrefix("en") == true
        var rec = Recording(title: english ? "Linear Algebra – Eigenvalues" : "Analysis II – Eigenwerte",
                            categoryID: library.categories.first?.id,
                            startedAt: Date().addingTimeInterval(-5_400))
        rec.endedAt = rec.startedAt.addingTimeInterval(5_100)
        rec.status = .done
        try? await libraryRepository.insertRecording(rec)
        try? await libraryRepository.saveTranscript(
            Transcript(segments: english
                       ? [TranscriptSegment(start: 0, end: 6, text: "Today we talk about eigenvalues, says Professor Meyer."),
                          TranscriptSegment(start: 6, end: 14, text: "The exam takes place on 12 February.")]
                       : [TranscriptSegment(start: 0, end: 6, text: "Heute sprechen wir über Eigenwerte, sagt Professor Maier."),
                          TranscriptSegment(start: 6, end: 14, text: "Die Klausur findet am 12. Februar statt.")],
                       engine: "Whisper large-v3"), for: rec.id)
        let note = english
            ? Summary(title: "Eigenvalues and eigenvectors",
                      markdown: "The lecture covered eigenvalues, how to compute them via the characteristic "
                          + "polynomial, and why they matter for diagonalisability.\n\n## How to compute them\n"
                          + "- Set up the characteristic polynomial\n- Find its roots\n- Work out the eigenspaces\n\n"
                          + "## Tasks\n- [ ] Work through problem sheet 4 by Friday\n- [ ] Note the exam date: 12 February",
                      taskCount: 2, provider: "Local AI")
            : Summary(title: "Eigenwerte und Eigenvektoren",
                      markdown: "In der Vorlesung ging es um Eigenwerte, ihre Berechnung über das charakteristische "
                          + "Polynom und die Bedeutung für Diagonalisierbarkeit.\n\n## Rechenweg\n- Charakteristisches "
                          + "Polynom aufstellen\n- Nullstellen bestimmen\n- Eigenräume berechnen\n\n## Aufgaben\n"
                          + "- [ ] Übungsblatt 4 bis Freitag rechnen\n- [ ] Klausurtermin am 12. Februar notieren",
                      taskCount: 2, provider: "Lokale KI")
        try? await libraryRepository.saveNote(note, for: rec.id)
        // Nur Debug: eine Audiodatei zum Anhören unterschieben (EARNOTE_DEMO_AUDIO=<Pfad>)
        if let path = ProcessInfo.processInfo.environment["EARNOTE_DEMO_AUDIO"] {
            audio.createFolder(for: rec.id)
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: audio.mixURL(for: rec.id))
        }
        try? await libraryRepository.setExports([
            ExportResult(destinationID: MarkdownDestination.id, destinationName: "Markdown", success: true,
                         message: "Exportiert", url: "file:///tmp/Analysis.md"),
        ], for: rec.id)
        try? await libraryRepository.insertGlossaryTerm(GlossaryTerm(term: "Professor Meyer", variants: ["Maier", "Mayer"]))
        try? await libraryRepository.insertGlossaryTerm(GlossaryTerm(term: "Eigenwert", variants: ["Eigen Wert"],
                                                                    categoryID: library.categories.first?.id))
        await library.load()
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
        #if DEBUG
        await addDemoLibraryIfRequested()
        #endif
        queue.resumeInterruptedWork()
    }
}
