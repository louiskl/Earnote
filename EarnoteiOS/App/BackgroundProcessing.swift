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
    private static let prefix = "app.earnote.Earnote.process"

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

    private var isWorking: Bool { queue.processingID != nil || !queue.pending.isEmpty }

    private func report(to task: BGContinuedProcessingTask) {
        guard let id = queue.processingID else { return }
        task.progress.completedUnitCount = Int64((queue.progress[id] ?? 0) * 100)
        if let title = library?.recording(id)?.displayTitle {
            task.updateTitle(String(localized: "Notiz wird geschrieben"), subtitle: title)
        }
    }
}
