import AVFoundation
import Foundation
import Observation

/// Was die Warteschlange von der Bibliothek braucht: Aufnahmen lesen und ändern, Einstellungen, Kategorien.
@MainActor
public protocol RecordingLibrary: AnyObject {
    var recordings: [Recording] { get }
    var settings: AppSettings { get }
    func recording(_ id: UUID) -> Recording?
    func category(_ id: UUID?) -> RecordingCategory?
    /// Ändert die Aufnahme und speichert sie (im Hintergrund)
    func update(_ id: UUID, _ change: (inout Recording) -> Void)
    /// Wie `update`, wartet aber, bis gespeichert ist
    func updateAndSave(_ id: UUID, _ change: (inout Recording) -> Void) async
    /// Wartet, bis alle angestoßenen Speichervorgänge erledigt sind
    func waitForPendingWrites() async
    /// Ändert den Fortschritt nur im Speicher (wird oft aufgerufen)
    func setProgressInMemory(_ id: UUID, _ progress: Double)
}

/// Arbeitet Aufnahmen nacheinander ab. Ein Fehler bei einer Aufnahme hält die übrigen nicht auf.
@MainActor
@Observable
public final class ProcessingQueue {
    /// Aufnahme, die gerade verarbeitet wird
    public private(set) var processingID: UUID?
    /// Fortschritt je Aufnahme (0…1), nur im Speicher; für Liste, Detail und Inspector
    public private(set) var progress: [UUID: Double] = [:]

    @ObservationIgnored public weak var library: (any RecordingLibrary)?
    @ObservationIgnored private let pipeline: ProcessingPipeline
    /// Wird aufgerufen, wenn nichts mehr zu tun ist (z. B. geladene Modelle aus dem Speicher werfen)
    @ObservationIgnored private let onDrain: @MainActor () -> Void
    @ObservationIgnored private var queue: [UUID] = []
    /// Einmalige Anweisung je Aufnahme für den nächsten Durchgang („Neu zusammenfassen …“)
    @ObservationIgnored private var instructions: [UUID: String] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?

    public init(pipeline: ProcessingPipeline, onDrain: @escaping @MainActor () -> Void = {}) {
        self.pipeline = pipeline
        self.onDrain = onDrain
    }

    /// Wartende Aufnahmen in Reihenfolge (ohne die laufende)
    public var pending: [UUID] { queue }

    public func enqueue(_ id: UUID, next: Bool = false, instruction: String = "") {
        guard let library, library.recording(id) != nil else { return }
        if !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { instructions[id] = instruction }
        // Wird die Aufnahme gerade verarbeitet (z. B. „Neu zusammenfassen“ während der Transkription),
        // den laufenden Durchgang abbrechen und mit dem neuen Stand von vorn beginnen.
        if processingID == id { task?.cancel() }
        queue.removeAll { $0 == id }
        queue.insert(id, at: next ? 0 : queue.endIndex)
        library.update(id) { $0.status = .queued; $0.errorMessage = nil; $0.progress = 0 }
        progress[id] = 0
        processNext()
    }

    /// Aufnahme wurde gelöscht: aus der Warteschlange nehmen und eine laufende Verarbeitung abbrechen –
    /// sonst wartet die restliche Warteschlange, bis die gelöschte Aufnahme fertig (oder gescheitert) ist.
    public func remove(_ id: UUID) {
        queue.removeAll { $0 == id }
        instructions[id] = nil
        progress[id] = nil
        if processingID == id { task?.cancel() }
    }

    /// Wird der KI-Anbieter gewechselt, während gerade zusammengefasst wird: mit dem neuen Anbieter neu beginnen,
    /// statt den alten (womöglich minutenlang) zu Ende laufen zu lassen.
    public func aiProviderChanged() {
        if let id = processingID, library?.recording(id)?.status == .summarizing {
            enqueue(id, next: true)
        }
    }

    /// Nach einem Absturz oder erzwungenem Beenden: unterbrochene Aufnahmen/Verarbeitungen wieder aufnehmen.
    public func resumeInterruptedWork() {
        guard let library else { return }
        for r in library.recordings where r.status == .recording || r.status.isBusy {
            if r.status == .recording {
                // Ende aus der tatsächlich aufgenommenen Länge ableiten, nicht aus dem Zeitpunkt des Neustarts
                let recorded = recordedDuration(r.id)
                library.update(r.id) {
                    if let recorded {
                        $0.endedAt = $0.startedAt.addingTimeInterval(recorded)
                        $0.pausedDuration = nil
                    } else {
                        $0.endedAt = $0.endedAt ?? Date()
                    }
                }
            }
            enqueue(r.id)
        }
    }

    /// Länge der Mikrofonaufnahme in Sekunden (ohne Pausen).
    private func recordedDuration(_ id: UUID) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: pipeline.audio.micURL(for: id)),
              file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Fortschritt nur im Speicher ändern – er wird nicht gespeichert.
    /// Läuft nur vorwärts, damit verspätet eintreffende Meldungen den Balken nicht zurückwerfen
    /// (zurückgesetzt wird er beim Einreihen).
    public func setProgress(_ id: UUID, _ progress: Double) {
        guard let library, let current = library.recording(id), progress > current.progress else { return }
        library.setProgressInMemory(id, progress)
        self.progress[id] = progress
    }

    private func processNext() {
        guard processingID == nil else { return }
        guard !queue.isEmpty else {
            didDrain()
            return
        }
        let id = queue.removeFirst()
        processingID = id
        if activity == nil {
            // Verhindert Ruhezustand und App Nap, solange verarbeitet wird
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Aufnahmen werden verarbeitet")
        }
        task = Task {
            await process(id)
            processingID = nil
            task = nil
            processNext()
        }
    }

    private func process(_ id: UUID) async {
        // Zuerst speichern, was vorher angestoßen wurde (z. B. neu angelegte Aufnahme, gelöschte Notiz)
        await library?.waitForPendingWrites()
        guard !Task.isCancelled, let library, let rec = library.recording(id) else { return }
        let settings = library.settings
        let category = library.category(rec.categoryID)
        let instruction = instructions.removeValue(forKey: id) ?? ""
        await pipeline.process(rec, settings: settings, category: category, events: events,
                               extraInstructions: instruction)
    }

    private var events: ProcessingEvents {
        ProcessingEvents(
            recording: { [weak self] id in await self?.currentRecording(id) },
            update: { [weak self] id, change in await self?.apply(id, change) },
            progress: { [weak self] id, p in Task { @MainActor in self?.setProgress(id, p) } })
    }

    private func currentRecording(_ id: UUID) -> Recording? { library?.recording(id) }
    private func apply(_ id: UUID, _ change: @Sendable (inout Recording) -> Void) async { await library?.updateAndSave(id, change) }

    private func didDrain() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        onDrain()
    }
}
