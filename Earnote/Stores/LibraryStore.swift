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
    /// Wörterbuch: richtige Schreibweisen von Namen und Fachbegriffen
    private(set) var glossary: [GlossaryTerm] = []
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
            glossary = (try? await library.glossaryTerms()) ?? []
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

    /// Schaltet eine Aufgabe in der Notiz um und speichert sofort (KI-Original bleibt erhalten).
    func toggleTask(_ id: UUID, in markdown: String, line: Int) {
        guard let updated = NoteMarkdown.togglingTask(in: markdown, line: line) else { return }
        updateSummaryText(id, markdown: updated)
    }

    /// IDs der Aufnahmen, die zum Suchbegriff passen (Titel, Notiz, Transkript), gesucht im Hintergrund
    func search(_ query: String) async -> Set<UUID> {
        await waitForPendingWrites()
        do { return try await library.searchRecordingIDs(matching: query) } catch {
            Log.error("Suche: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Bereiche

    /// Legt einen neuen Bereich am Ende an und gibt ihn zurück (Name kann danach direkt umbenannt werden)
    @discardableResult
    func addCategory(named name: String = "Neuer Bereich") -> RecordingCategory {
        let category = RecordingCategory(name: name, emoji: "🗂️", symbol: "folder.fill",
                                         colorHex: RecordingCategory.colorChoices[categories.count % RecordingCategory.colorChoices.count],
                                         instructions: "")
        categories.append(category)
        return category
    }

    func renameCategory(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[i].name = trimmed
    }

    /// Aufnahmen des Bereichs bleiben erhalten und verlieren nur die Zuordnung.
    func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        if settings.defaultCategoryID == id { settings.defaultCategoryID = nil }
    }

    /// Neue Reihenfolge der Bereiche (IDs in Anzeige-Reihenfolge)
    func setCategoryOrder(_ ids: [UUID]) {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = ids.compactMap { byID[$0] }
        let rest = categories.filter { !ids.contains($0.id) }
        categories = ordered + rest
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed; $0.isTitleCustom = true }
    }

    func setCategory(_ id: UUID, _ categoryID: UUID?) { update(id) { $0.categoryID = categoryID } }

    /// Übernimmt eine im Fenster geänderte Notiz (z. B. abgehakte Aufgabe). Das KI-Original bleibt erhalten.
    func updateSummaryText(_ id: UUID, markdown: String) {
        let taskCount = NoteMarkdown.openTaskCount(markdown)
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

    func enqueue(_ id: UUID, next: Bool = false, instruction: String = "") {
        queue.enqueue(id, next: next, instruction: instruction)
    }

    /// Alles neu: Transkription, Zusammenfassung, Export.
    /// `instruction` gilt nur für diesen Durchgang (z. B. „Kürzer fassen, auf Formeln achten“).
    func reprocess(_ id: UUID, retranscribe: Bool, instruction: String = "") {
        let library = self.library
        if retranscribe { write("Transkript löschen") { try await library.deleteTranscript(for: id) } }
        write("Notiz löschen") { try await library.deleteNote(for: id) }
        update(id) { $0.exports = [] }
        enqueue(id, instruction: instruction)
    }

    /// Verwirft die Änderungen des Nutzers und stellt die Fassung der KI wieder her.
    func restoreGeneratedNote(_ id: UUID) {
        let library = self.library
        write("KI-Fassung wiederherstellen") { _ = try await library.restoreGeneratedNote(for: id) }
        update(id) { $0.isNoteEdited = false }
    }

    // MARK: Namen & Begriffe

    /// Ersetzt eine falsch erkannte Schreibweise in Titel, Notiz und Transkript dieser Aufnahme.
    /// `remember` nimmt die Korrektur ins Wörterbuch auf, damit sie künftig gar nicht erst entsteht.
    func correctTerm(_ id: UUID, wrong: String, right: String, remember: Bool) {
        let wrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wrong.isEmpty, !right.isEmpty, wrong.caseInsensitiveCompare(right) != .orderedSame else { return }
        let library = self.library
        write("Begriff korrigieren") { try await library.correctTerm(wrong: wrong, right: right, for: id) }
        if let i = recordings.firstIndex(where: { $0.id == id }) {
            recordings[i].title = TermCorrection.replace(recordings[i].title, wrong: wrong, with: right)
            recordings[i].summaryTitle = recordings[i].summaryTitle.map { TermCorrection.replace($0, wrong: wrong, with: right) }
            recordings[i].isNoteEdited = true
        }
        guard remember else { return }
        let categoryID = recording(id)?.categoryID
        if var existing = glossary.first(where: { $0.term.caseInsensitiveCompare(right) == .orderedSame
                                                 && $0.categoryID == categoryID }) {
            guard !existing.variants.contains(where: { $0.caseInsensitiveCompare(wrong) == .orderedSame }) else { return }
            existing.variants.append(wrong)
            updateGlossaryTerm(existing)
        } else {
            addGlossaryTerm(GlossaryTerm(term: right, variants: [wrong], categoryID: categoryID))
        }
    }

    // MARK: Wörterbuch

    func addGlossaryTerm(_ term: GlossaryTerm) {
        glossary.append(term)
        let library = self.library
        write("Wörterbuch ergänzen") { try await library.insertGlossaryTerm(term) }
    }

    func updateGlossaryTerm(_ term: GlossaryTerm) {
        guard let i = glossary.firstIndex(where: { $0.id == term.id }) else { return }
        glossary[i] = term
        let library = self.library
        write("Wörterbuch ändern") { try await library.updateGlossaryTerm(term) }
    }

    func deleteGlossaryTerm(_ id: UUID) {
        glossary.removeAll { $0.id == id }
        let library = self.library
        write("Wörterbuch löschen") { try await library.deleteGlossaryTerm(id) }
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
