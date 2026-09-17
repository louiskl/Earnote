import AppKit
import EarnoteCore
import Observation

/// Die Bibliothek: Aufnahmen, Bereiche und Einstellungen samt aller Änderungen daran.
/// Hält den aktuellen Stand im Speicher (für die Oberfläche) und schreibt jede Änderung der Reihe nach
/// in die Bibliothek (`LibraryRepository`). Audio liegt im `AudioStore`.
@MainActor
@Observable
final class LibraryStore: RecordingLibrary {
    var settings: AppSettings {
        didSet {
            settingsRepository.saveSettings(settings)
            onSettingsChanged(oldValue, settings)
        }
    }
    var categories: [RecordingCategory] = [] {
        didSet { if !isApplyingLoad { persistCategoryChanges(from: oldValue) } }
    }
    private(set) var recordings: [Recording] = []
    /// Bibliothek ist geladen (vorher sind Aufnahmen und Bereiche noch leer)
    private(set) var isLoaded = false
    /// Ausgewählte Aufnahme im Hauptfenster (zieht in Phase 2 in den Fensterzustand um)
    var selection: UUID?
    var lastError: String?

    @ObservationIgnored let library: any LibraryRepository
    @ObservationIgnored let audio: any AudioStore
    @ObservationIgnored private let settingsRepository: any SettingsRepository
    @ObservationIgnored private let queue: ProcessingQueue
    /// Nach jeder Änderung der Einstellungen (alt, neu)
    @ObservationIgnored var onSettingsChanged: (AppSettings, AppSettings) -> Void = { _, _ in }
    /// Vor dem Löschen einer Aufnahme (z. B. eine noch laufende Aufnahme beenden)
    @ObservationIgnored var willDelete: (UUID) -> Void = { _ in }
    @ObservationIgnored private var isApplyingLoad = false
    /// Letzter angestoßener Schreibvorgang; jeder neue wartet auf den vorherigen
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    init(library: any LibraryRepository, audio: any AudioStore, settingsRepository: any SettingsRepository,
         queue: ProcessingQueue) {
        self.library = library
        self.audio = audio
        self.settingsRepository = settingsRepository
        self.queue = queue
        settings = settingsRepository.loadSettings() ?? AppSettings()
    }

    /// Lädt Bereiche und Aufnahmen aus der Bibliothek (nach der Übernahme alter Daten).
    func load() async {
        do {
            let loadedCategories = try await library.categories()
            let loadedRecordings = try await library.recordings()
            isApplyingLoad = true
            categories = loadedCategories
            isApplyingLoad = false
            // Was während des Ladens schon neu angelegt wurde (z. B. eine gerade gestartete Aufnahme), bleibt erhalten
            let loadedIDs = Set(loadedRecordings.map(\.id))
            recordings = (recordings.filter { !loadedIDs.contains($0.id) } + loadedRecordings)
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            Log.error("Bibliothek laden: \(error.localizedDescription)")
            lastError = "Die Bibliothek konnte nicht geladen werden: \(error.localizedDescription)"
        }
        isLoaded = true
    }

    // MARK: Speichern

    /// Schreibt der Reihe nach; Fehler landen im Protokoll.
    private func write(_ what: String, _ operation: @escaping @Sendable () async throws -> Void) {
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            do { try await operation() } catch { Log.error("Speichern (\(what)): \(error.localizedDescription)") }
        }
    }

    func waitForPendingWrites() async {
        // Solange weitere Schreibvorgänge dazukommen, auch auf diese warten
        while let task = lastWrite {
            await task.value
            if lastWrite == task { return }
        }
    }

    /// Bereiche werden in der Oberfläche als Liste geändert; hier werden daraus einzelne Speicheroperationen.
    private func persistCategoryChanges(from old: [RecordingCategory]) {
        let library = self.library
        let new = categories
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newIDs = Set(new.map(\.id))
        let removed = old.map(\.id).filter { !newIDs.contains($0) }
        for id in removed {
            write("Bereich löschen") { try await library.deleteCategory(id) }
        }
        if !removed.isEmpty {
            // Aufnahmen bleiben erhalten und verlieren nur die Zuordnung – wie in der Bibliothek
            let gone = Set(removed)
            for i in recordings.indices where recordings[i].categoryID.map(gone.contains) == true {
                recordings[i].categoryID = nil
            }
        }
        for (index, category) in new.enumerated() {
            if let previous = oldByID[category.id] {
                if previous != category { write("Bereich ändern") { try await library.updateCategory(category) } }
            } else {
                write("Bereich anlegen") { try await library.insertCategory(category, sortIndex: index) }
            }
        }
        if new.map(\.id) != old.map(\.id).filter(newIDs.contains) {
            let ids = new.map(\.id)
            write("Bereiche sortieren") { try await library.reorderCategories(ids) }
        }
    }

    // MARK: Lesen

    func recording(_ id: UUID) -> Recording? { recordings.first { $0.id == id } }
    func category(_ id: UUID?) -> RecordingCategory? { id.flatMap { cid in categories.first { $0.id == cid } } }

    func transcript(_ id: UUID) async -> Transcript? {
        await waitForPendingWrites()
        return try? await library.transcript(for: id)
    }

    func summary(_ id: UUID) async -> Summary? {
        await waitForPendingWrites()
        return try? await library.note(for: id)
    }

    func hasAudio(_ id: UUID) -> Bool {
        guard let r = recording(id) else { return false }
        return audio.hasAudio(r)
    }

    // MARK: Ändern

    func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
        let updated = recordings[i]
        let library = self.library
        write("Aufnahme ändern") { try await library.updateRecording(id) { $0 = updated } }
    }

    func updateAndSave(_ id: UUID, _ change: (inout Recording) -> Void) async {
        update(id, change)
        await waitForPendingWrites()
    }

    func setProgressInMemory(_ id: UUID, _ progress: Double) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].progress = progress
    }

    func insert(_ r: Recording) {
        recordings.insert(r, at: 0)
        let library = self.library
        write("Aufnahme anlegen") { try await library.insertRecording(r) }
    }

    func rename(_ id: UUID, to title: String) { update(id) { $0.title = title; $0.isTitleCustom = true } }

    func setCategory(_ id: UUID, _ categoryID: UUID?) { update(id) { $0.categoryID = categoryID } }

    /// Übernimmt eine im Fenster geänderte Notiz (z. B. abgehakte Aufgabe). Das KI-Original bleibt erhalten.
    func updateSummaryText(_ id: UUID, markdown: String) {
        let taskCount = markdown.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") }.count
        let library = self.library
        write("Notiz ändern") { try await library.updateNoteText(markdown, taskCount: taskCount, for: id) }
        if let i = recordings.firstIndex(where: { $0.id == id }) { recordings[i].taskCount = taskCount }
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
                fileName = try audio.importAudio(from: url, for: rec.id)
            } catch {
                audio.deleteFolder(for: rec.id)
                lastError = "Import fehlgeschlagen: \(error.localizedDescription)"
                continue
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            rec.startedAt = (attrs?[.creationDate] as? Date) ?? Date()
            if let reader = try? ResamplingReader(url: audio.importedAudioURL(for: rec.id, fileName: fileName)) {
                rec.endedAt = rec.startedAt.addingTimeInterval(reader.duration)
            }
            rec.importedFileName = fileName
            rec.isTitleCustom = !Recording.looksAutomatic(rec.title)
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
        let library = self.library
        if retranscribe { write("Transkript löschen") { try await library.deleteTranscript(for: id) } }
        write("Notiz löschen") { try await library.deleteNote(for: id) }
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
        audio.deleteAudio(for: r)
    }

    func delete(_ id: UUID) {
        willDelete(id)
        queue.remove(id)
        audio.deleteFolder(for: id)
        recordings.removeAll { $0.id == id }
        if selection == id { selection = nil }
        let library = self.library
        write("Aufnahme löschen") { try await library.deleteRecording(id) }
    }

    func revealInFinder(_ id: UUID) {
        NSWorkspace.shared.activateFileViewerSelecting([audio.folderURL(for: id)])
    }
}
