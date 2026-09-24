import EarnoteCore
import Foundation
import WidgetKit

/// Hält die Widgets aktuell: Nach jeder Änderung der Bibliothek oder der Aufnahme (gebündelt, höchstens einmal pro
/// Sekunde) schreibt sie den `WidgetSnapshot` neu und bittet WidgetKit, neu zu zeichnen.
@MainActor
final class WidgetPublisher {
    private let library: LibraryStore
    private let recorder: PhoneRecorder
    private var pending: Task<Void, Never>?

    init(library: LibraryStore, recorder: PhoneRecorder) {
        self.library = library
        self.recorder = recorder
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = library.recordings
            _ = library.categories
            _ = recorder.isRecording
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.schedule()
                self?.observe()
            }
        }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.publish()
        }
    }

    func publish() async {
        var snapshot = WidgetSnapshot()
        snapshot.isRecording = recorder.isRecording
        let done = library.recordings.filter { $0.status == .done }
        snapshot.notes = done.prefix(5).map { r in
            let area = library.category(r.categoryID)
            return WidgetSnapshot.Note(id: r.id, title: r.displayTitle, area: area?.name, emoji: area?.displayEmoji,
                                       colorHex: area?.colorHex, preview: r.summaryPreview, date: r.startedAt,
                                       openTasks: r.taskCount)
        }
        snapshot.openTaskCount = library.recordings.reduce(0) { $0 + $1.taskCount }
        // Die ersten offenen Aufgaben im Wortlaut – aus den neuesten Notizen
        for r in done where r.taskCount > 0 {
            guard snapshot.tasks.count < 6, let note = await library.summary(r.id) else { continue }
            for block in NoteMarkdown.blocks(note.markdown) {
                if case .task(_, let text, false, let line) = block, snapshot.tasks.count < 6,
                   !snapshot.tasks.contains(where: { $0.text == text }) {
                    snapshot.tasks.append(.init(id: "\(r.id)-\(line)", recordingID: r.id, text: text))
                }
            }
        }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
