import AppKit
import EarnoteCore
import Observation

/// Die Bibliothek: Aufnahmen, Kategorien und Einstellungen samt aller Änderungen daran.
/// Liest und schreibt ausschließlich über die Repositories.
@MainActor
@Observable
final class LibraryStore: RecordingLibrary {
    var settings: AppSettings {
        didSet {
            settingsRepository.saveSettings(settings)
            onSettingsChanged(oldValue, settings)
        }
    }
    var categories: [RecordingCategory] { didSet { settingsRepository.saveCategories(categories) } }
    private(set) var recordings: [Recording] = []
    /// Ausgewählte Aufnahme im Hauptfenster (zieht in Phase 2 in den Fensterzustand um)
    var selection: UUID?
    var lastError: String?

    @ObservationIgnored let repository: any RecordingRepository
    @ObservationIgnored private let settingsRepository: any SettingsRepository
    @ObservationIgnored private let queue: ProcessingQueue
    /// Nach jeder Änderung der Einstellungen (alt, neu)
    @ObservationIgnored var onSettingsChanged: (AppSettings, AppSettings) -> Void = { _, _ in }
    /// Vor dem Löschen einer Aufnahme (z. B. eine noch laufende Aufnahme beenden)
    @ObservationIgnored var willDelete: (UUID) -> Void = { _ in }

    init(repository: any RecordingRepository, settingsRepository: any SettingsRepository, queue: ProcessingQueue) {
        self.repository = repository
        self.settingsRepository = settingsRepository
        self.queue = queue
        settings = settingsRepository.loadSettings() ?? AppSettings()
        categories = RecordingCategory.migrated(settingsRepository.loadCategories() ?? RecordingCategory.defaults)
        settingsRepository.saveCategories(categories)
        recordings = repository.loadRecordings().sorted { $0.startedAt > $1.startedAt }
        repairCategoryAssignments()
        fillMissingPreviews()
    }

    /// Früher wurden die Standardkategorien erst beim ersten Bearbeiten gespeichert und bekamen bei jedem Start
    /// neue IDs – Aufnahmen verloren so ihre Kategorie. Zuordnung über den automatischen Namen wiederherstellen.
    private func repairCategoryAssignments() {
        for r in recordings where r.categoryID != nil && category(r.categoryID) == nil {
            if let match = categories.first(where: { r.title.hasPrefix("\($0.name) – ") }) {
                update(r.id) { $0.categoryID = match.id }
            }
        }
    }

    /// Aufnahmen aus älteren Versionen haben noch keine Vorschau für die Liste.
    private func fillMissingPreviews() {
        for r in recordings where r.summaryPreview == nil {
            if let preview = summary(r.id)?.preview { update(r.id) { $0.summaryPreview = preview } }
        }
    }

    // MARK: Lesen

    func recording(_ id: UUID) -> Recording? { recordings.first { $0.id == id } }
    func category(_ id: UUID?) -> RecordingCategory? { id.flatMap { cid in categories.first { $0.id == cid } } }
    func transcript(_ id: UUID) -> Transcript? { repository.transcript(for: id) }
    func summary(_ id: UUID) -> Summary? { repository.summary(for: id) }

    func hasAudio(_ id: UUID) -> Bool {
        guard let r = recording(id) else { return false }
        return repository.hasAudio(r)
    }

    // MARK: Ändern

    func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
        repository.update(recordings[i])
    }

    func setProgressInMemory(_ id: UUID, _ progress: Double) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].progress = progress
    }

    func insert(_ r: Recording) {
        recordings.insert(r, at: 0)
        repository.insert(r)
    }

    func rename(_ id: UUID, to title: String) { update(id) { $0.title = title } }

    func setCategory(_ id: UUID, _ categoryID: UUID?) { update(id) { $0.categoryID = categoryID } }

    /// Übernimmt eine im Fenster geänderte Notiz (z. B. abgehakte Aufgabe).
    func updateSummaryText(_ id: UUID, markdown: String) {
        guard var summary = summary(id) else { return }
        summary.markdown = markdown
        summary.taskCount = markdown.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") }.count
        repository.saveSummary(summary, for: id)
        update(id) { $0.taskCount = summary.taskCount }
    }

    /// Übernimmt ausgewählte Vorlagen und Fächer als Bereiche. Bereiche mit gleichem Namen bleiben erhalten,
    /// damit bestehende Aufnahmen ihre Zuordnung nicht verlieren.
    @discardableResult
    func addCategories(templates: Set<String>, subjects: [String]) -> [RecordingCategory] {
        let existing = Set(categories.map(\.name))
        var added: [RecordingCategory] = []
        for template in CategoryTemplate.all where templates.contains(template.id) && !existing.contains(template.name) {
            // Wer Fächer einträgt, braucht keinen zusätzlichen allgemeinen Bereich „Vorlesung“
            if template.supportsSubjects && !subjects.isEmpty { continue }
            added.append(template.makeCategory())
        }
        added += CategoryTemplate.subjectCategories(subjects.filter { !existing.contains($0) })
        categories.append(contentsOf: added)
        return added
    }

    // MARK: Import

    func importAudio(_ urls: [URL], category: RecordingCategory?) {
        for url in urls {
            var rec = Recording(title: url.deletingPathExtension().lastPathComponent, categoryID: category?.id)
            let fileName: String
            do {
                fileName = try repository.importAudio(from: url, for: rec.id)
            } catch {
                repository.delete(rec.id)
                lastError = "Import fehlgeschlagen: \(error.localizedDescription)"
                continue
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            rec.startedAt = (attrs?[.creationDate] as? Date) ?? Date()
            if let reader = try? ResamplingReader(url: repository.importedAudioURL(for: rec.id, fileName: fileName)) {
                rec.endedAt = rec.startedAt.addingTimeInterval(reader.duration)
            }
            rec.importedFileName = fileName
            rec.status = .queued
            rec.language = settings.language
            insert(rec)
            enqueue(rec.id)
        }
    }

    // MARK: Verarbeitung

    func enqueue(_ id: UUID, next: Bool = false) { queue.enqueue(id, next: next) }

    /// Alles neu: Transkription, Zusammenfassung, Export.
    func reprocess(_ id: UUID, retranscribe: Bool) {
        if retranscribe { repository.deleteTranscript(for: id) }
        repository.deleteSummary(for: id)
        update(id) { $0.exports = [] }
        enqueue(id)
    }

    func reexport(_ id: UUID) {
        update(id) { $0.exports = [] }
        enqueue(id)
    }

    // MARK: Löschen

    func deleteAudio(_ id: UUID) {
        guard let r = recording(id) else { return }
        repository.deleteAudio(for: r)
    }

    func delete(_ id: UUID) {
        willDelete(id)
        queue.remove(id)
        repository.delete(id)
        recordings.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    func revealInFinder(_ id: UUID) {
        NSWorkspace.shared.activateFileViewerSelecting([repository.folderURL(for: id)])
    }
}
