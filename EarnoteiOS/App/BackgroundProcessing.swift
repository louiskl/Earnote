import BackgroundTasks
import EarnoteCore
import Foundation

/// Schreibt die Notiz im Hintergrund fertig, wenn man die App nach dem Stopp verlässt (iOS 26:
/// `BGContinuedProcessingTask`). iOS zeigt dazu selbst einen Fortschritt an. Bricht das System ab, geht
/// die Warteschlange beim nächsten Öffnen dort weiter (`ProcessingQueue.resumeInterruptedWork`).
@MainActor
final class BackgroundProcessing {
    private let queue: ProcessingQueue
    private weak var library: LibraryStore?
    private var active: BGContinuedProcessingTask?
    private var charging: BGTask?
    private static let prefix = "app.earnote.Earnote.process"
    /// „Erst am Ladekabel“: iOS weckt die App am Strom (oft nachts) – steht im Info.plist
    private static let chargingIdentifier = "app.earnote.Earnote.charging"

    init(queue: ProcessingQueue, library: LibraryStore) {
        self.queue = queue
        self.library = library
    }

    /// Nach dem Einreihen aufrufen – solange noch etwas zu tun ist, hält eine Hintergrund-Aufgabe die App wach.
    func begin() {
        guard active == nil else { return }
        let identifier = "\(Self.prefix).\(UUID().uuidString)"
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else { return task.setTaskCompleted(success: false) }
            MainActor.assumeIsolated { self?.run(task) }
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                       title: String(localized: "Notiz wird geschrieben"),
                                                       subtitle: String(localized: "Earnote arbeitet weiter, auch wenn du die App verlässt."))
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Z. B. im Simulator oder wenn iOS gerade nichts zulässt: Die Arbeit läuft dann im Vordergrund weiter.
            Log.info("Hintergrund-Aufgabe nicht möglich: \(error.localizedDescription)")
        }
    }

    private func run(_ task: BGContinuedProcessingTask) {
        active = task
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak self] in
            MainActor.assumeIsolated { self?.active = nil }
        }
        Task { [weak self] in
            while let self, self.active === task, self.isWorking {
                self.report(to: task)
                try? await Task.sleep(for: .seconds(1))
            }
            task.progress.completedUnitCount = 100
            task.setTaskCompleted(success: true)
            self?.active = nil
        }
    }

    /// Muss beim Start registriert sein, bevor iOS die Aufgabe ausliefert
    func registerChargingTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.chargingIdentifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated { self?.runCharging(task) }
        }
    }

    /// Aufnahmen warten aufs Ladekabel: iOS bitten, die App am Strom zu wecken. Ein neuer Auftrag ersetzt den alten.
    func scheduleCharging() {
        let request = BGProcessingTaskRequest(identifier: Self.chargingIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Dann geht es weiter, sobald die App am Ladekabel geöffnet ist
            Log.info("Verarbeitung am Ladekabel nicht angemeldet: \(error.localizedDescription)")
        }
    }

    /// Am Strom geweckt: Beim Start hat `resumeInterruptedWork` die wartenden Aufnahmen schon eingereiht,
    /// jetzt hält nichts mehr zurück. Läuft die Zeit ab, geht es beim nächsten Öffnen weiter.
    private func runCharging(_ task: BGTask) {
        charging = task
        task.expirationHandler = { [weak self] in
            MainActor.assumeIsolated { self?.charging = nil }
        }
        queue.resume()
        Task { [weak self] in
            // Die Bibliothek lädt beim Start im Hintergrund; erst danach steht die Warteschlange
            try? await Task.sleep(for: .seconds(5))
            while let self, self.charging === task, self.isWorking {
                try? await Task.sleep(for: .seconds(2))
            }
            task.setTaskCompleted(success: true)
            self?.charging = nil
        }
    }

    private var isWorking: Bool { queue.processingID != nil || !queue.pending.isEmpty }

    private func report(to task: BGContinuedProcessingTask) {
        guard let id = queue.processingID else { return }
        task.progress.completedUnitCount = Int64((queue.progress[id] ?? 0) * 100)
        if let title = library?.recording(id)?.displayTitle {
            task.updateTitle(String(localized: "Notiz wird geschrieben"), subtitle: title)
        }
    }
}
