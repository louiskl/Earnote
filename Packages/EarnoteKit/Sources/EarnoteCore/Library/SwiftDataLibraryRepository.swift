import Foundation
import SwiftData

/// Erzeugt den Speicher der Bibliothek.
public enum LibraryContainer {
    /// Dateiname im Datenordner
    public static let fileName = "Library.store"

    /// iCloud-Container für die Bibliothek. Audio wird nie synchronisiert – nur Aufnahmedaten,
    /// Transkripte, Notizen, Bereiche und Wörterbuch.
    public static let cloudContainer = "iCloud.\(AppInfo.bundleIdentifier)"

    /// `syncsWithCloud` setzt die App aus den Einstellungen. Ohne passende Berechtigung im Signaturprofil
    /// schlägt der Start mit iCloud fehl – deshalb fällt er auf den reinen Ordner-Speicher zurück,
    /// statt die Bibliothek gar nicht zu öffnen.
    public static func make(url: URL, syncsWithCloud: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: EarnoteSchemaLatest.self)
        if syncsWithCloud {
            do {
                let cloud = ModelConfiguration(schema: schema, url: url,
                                               cloudKitDatabase: .private(cloudContainer))
                return try ModelContainer(for: schema, migrationPlan: EarnoteMigrationPlan.self, configurations: cloud)
            } catch {
                Log.error("iCloud-Sync nicht möglich, Bibliothek bleibt lokal: \(error.localizedDescription)")
            }
        }
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: EarnoteMigrationPlan.self, configurations: configuration)
    }

    /// Für Tests
    public static func makeInMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: EarnoteSchemaLatest.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: EarnoteMigrationPlan.self, configurations: configuration)
    }
}

/// `LibraryRepository` mit SwiftData. Alle Zugriffe laufen seriell auf diesem Actor.
@ModelActor
public actor SwiftDataLibraryRepository: LibraryRepository {

    // MARK: Hilfen

    private func recordingModel(_ id: UUID) throws -> LibraryRecording? {
        var descriptor = FetchDescriptor<LibraryRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func categoryModel(_ id: UUID?) throws -> LibraryCategory? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<LibraryCategory>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func glossaryModel(_ id: UUID) throws -> LibraryGlossaryTerm? {
        var descriptor = FetchDescriptor<LibraryGlossaryTerm>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func sortedCategoryModels() throws -> [LibraryCategory] {
        try modelContext.fetch(FetchDescriptor<LibraryCategory>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))
    }

    private func replaceExports(of model: LibraryRecording, with results: [ExportResult]) {
        for old in model.exports ?? [] { modelContext.delete(old) }
        model.exports = results.map { result in
            let export = LibraryExport()
            export.apply(result)
            modelContext.insert(export)
            return export
        }
    }

    /// Bereich, Exporte und eigene Felder aus einem Snapshot übernehmen
    private func apply(_ snapshot: Recording, to model: LibraryRecording, previous: Recording?) throws {
        model.apply(snapshot)
        if previous?.categoryID != snapshot.categoryID || previous == nil {
            model.category = try categoryModel(snapshot.categoryID)
        }
        if previous?.exports != snapshot.exports {
            replaceExports(of: model, with: snapshot.exports)
        }
        model.modifiedAt = Date()
    }

    // MARK: Aufnahmen

    public func recordings() throws -> [Recording] {
        var descriptor = FetchDescriptor<LibraryRecording>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        // Notiz, Exporte und Bereich in einem Rutsch laden; das Transkript bleibt ungeladen.
        descriptor.relationshipKeyPathsForPrefetching = [\.note, \.exports, \.category]
        return try modelContext.fetch(descriptor).map { $0.snapshot() }
    }

    public func recording(_ id: UUID) throws -> Recording? {
        try recordingModel(id)?.snapshot()
    }

    public func recordingIDs() throws -> Set<UUID> {
        var descriptor = FetchDescriptor<LibraryRecording>()
        descriptor.propertiesToFetch = [\.id]
        return Set(try modelContext.fetch(descriptor).map(\.id))
    }

    public func insertRecording(_ recording: Recording) throws {
        guard try recordingModel(recording.id) == nil else { return }
        let model = LibraryRecording(id: recording.id)
        modelContext.insert(model)
        try apply(recording, to: model, previous: nil)
        try modelContext.save()
    }

    public func updateRecording(_ id: UUID, _ change: @escaping @Sendable (inout Recording) -> Void) throws {
        guard let model = try recordingModel(id) else { return }
        let previous = model.snapshot()
        var updated = previous
        change(&updated)
        try apply(updated, to: model, previous: previous)
        try modelContext.save()
    }

    public func deleteRecording(_ id: UUID) throws {
        guard let model = try recordingModel(id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: Transkript

    public func transcript(for id: UUID) throws -> Transcript? {
        try recordingModel(id)?.transcript?.snapshot()
    }

    public func saveTranscript(_ transcript: Transcript, for id: UUID) throws {
        // Inzwischen gelöschte Aufnahmen bekommen kein verwaistes Transkript
        guard let model = try recordingModel(id) else { return }
        if let stored = model.transcript {
            try stored.apply(transcript)
        } else {
            let stored = LibraryTranscript()
            modelContext.insert(stored)
            try stored.apply(transcript)
            model.transcript = stored
        }
        try modelContext.save()
    }

    public func deleteTranscript(for id: UUID) throws {
        guard let model = try recordingModel(id), let stored = model.transcript else { return }
        model.transcript = nil
        modelContext.delete(stored)
        try modelContext.save()
    }

    // MARK: Notiz

    public func note(for id: UUID) throws -> Summary? {
        try recordingModel(id)?.note?.snapshot()
    }

    public func saveNote(_ note: Summary, for id: UUID) throws {
        guard let model = try recordingModel(id) else { return }
        if let stored = model.note {
            stored.applyGenerated(note)
        } else {
            let stored = LibraryNote()
            modelContext.insert(stored)
            stored.applyGenerated(note)
            model.note = stored
        }
        try modelContext.save()
    }

    public func updateNoteText(_ markdown: String, taskCount: Int, for id: UUID) throws {
        guard let stored = try recordingModel(id)?.note else { return }
        stored.markdown = markdown
        stored.taskCount = taskCount
        stored.editedAt = Date()
        try modelContext.save()
    }

    public func restoreGeneratedNote(for id: UUID) throws -> Summary? {
        guard let stored = try recordingModel(id)?.note, !stored.generatedMarkdown.isEmpty else { return nil }
        stored.title = stored.generatedTitle
        stored.markdown = stored.generatedMarkdown
        stored.taskCount = NoteMarkdown.openTaskCount(stored.generatedMarkdown)
        stored.editedAt = nil
        try modelContext.save()
        return stored.snapshot()
    }

    public func deleteNote(for id: UUID) throws {
        guard let model = try recordingModel(id), let stored = model.note else { return }
        model.note = nil
        modelContext.delete(stored)
        try modelContext.save()
    }

    /// Namen und Begriffe korrigieren: gilt für Titel, Notiz und Transkript, damit nirgends die falsche
    /// Schreibweise stehen bleibt. Das KI-Original der Notiz bleibt unangetastet.
    public func correctTerm(wrong: String, right: String, for id: UUID) throws {
        guard let model = try recordingModel(id) else { return }
        func fixed(_ text: String) -> String { TermCorrection.replace(text, wrong: wrong, with: right) }

        model.title = fixed(model.title)
        if let note = model.note {
            let before = note.markdown + note.title
            note.title = fixed(note.title)
            note.markdown = fixed(note.markdown)
            note.preview = note.preview.map(fixed)
            if before != note.markdown + note.title { note.editedAt = Date() }
        }
        if let stored = model.transcript, var transcript = stored.snapshot() {
            for i in transcript.segments.indices { transcript.segments[i].text = fixed(transcript.segments[i].text) }
            try stored.apply(transcript)
        }
        model.modifiedAt = Date()
        try modelContext.save()
    }

    // MARK: Export

    public func setExports(_ exports: [ExportResult], for id: UUID) throws {
        guard let model = try recordingModel(id) else { return }
        replaceExports(of: model, with: exports)
        model.modifiedAt = Date()
        try modelContext.save()
    }

    // MARK: Bereiche

    public func categories() throws -> [RecordingCategory] {
        try sortedCategoryModels().map { $0.snapshot() }
    }

    public func insertCategory(_ category: RecordingCategory, sortIndex: Int?) throws {
        if let existing = try categoryModel(category.id) {
            existing.apply(category)
        } else {
            let model = LibraryCategory(id: category.id)
            model.apply(category)
            model.sortIndex = try sortIndex ?? ((sortedCategoryModels().map(\.sortIndex).max() ?? -1) + 1)
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    public func updateCategory(_ category: RecordingCategory) throws {
        guard let model = try categoryModel(category.id) else { return }
        model.apply(category)
        try modelContext.save()
    }

    public func deleteCategory(_ id: UUID) throws {
        guard let model = try categoryModel(id) else { return }
        // Zuordnungen ausdrücklich lösen, bevor gelöscht wird: Die Aufnahmen bleiben erhalten.
        for recording in model.recordings ?? [] { recording.category = nil }
        modelContext.delete(model)
        try modelContext.save()
    }

    public func reorderCategories(_ ids: [UUID]) throws {
        let models = try sortedCategoryModels()
        for (index, id) in ids.enumerated() {
            models.first { $0.id == id }?.sortIndex = index
        }
        try modelContext.save()
    }

    // MARK: Doppelte nach dem Abgleich

    public func mergeDuplicates() throws -> LibraryMergeReport {
        var report = LibraryMergeReport()
        let categories = try modelContext.fetch(FetchDescriptor<LibraryCategory>())
        var obsolete: [LibraryCategory] = []
        for group in LibraryMerge.groups(categories, id: \.id, name: \.name) {
            guard let keep = LibraryMerge.survivor(group, createdAt: \.createdAt, id: \.id) else { continue }
            for duplicate in group where duplicate !== keep {
                for recording in duplicate.recordings ?? [] { recording.category = keep }
                for term in duplicate.glossary ?? [] { term.category = keep }
                if keep.instructions.isEmpty { keep.instructions = duplicate.instructions }
                if duplicate.id != keep.id { report.categoryReplacements[duplicate.id] = keep.id }
                obsolete.append(duplicate)
            }
        }
        if !obsolete.isEmpty {
            // Erst das Umhängen speichern, dann löschen: Das Wörterbuch hängt mit „cascade“ am Bereich
            try modelContext.save()
            for duplicate in obsolete { modelContext.delete(duplicate) }
            try modelContext.save()
        }

        // Wörterbuch: derselbe Begriff im selben Bereich (auch erst durch das Zusammenlegen oben)
        let terms = try modelContext.fetch(FetchDescriptor<LibraryGlossaryTerm>())
        let termGroups = LibraryMerge.groups(terms, id: \.id) { term in
            term.term.isEmpty ? "" : "\(term.category?.id.uuidString ?? "-")|\(term.term)"
        }
        for group in termGroups {
            // Einträge haben kein Anlagedatum – die kleinste ID entscheidet, auf jedem Gerät gleich
            guard let keep = LibraryMerge.survivor(group, createdAt: { _ in .distantPast }, id: \.id) else { continue }
            // Feste Reihenfolge, damit jedes Gerät dieselben Schreibweisen behält
            let others = group.filter { $0 !== keep }.sorted { $0.id.uuidString < $1.id.uuidString }
            keep.variants = LibraryMerge.union(([keep] + others).map(\.variants))
            if keep.note?.isEmpty ?? true { keep.note = others.lazy.compactMap(\.note).first { !$0.isEmpty } }
            for duplicate in others {
                modelContext.delete(duplicate)
                report.removedGlossaryTerms += 1
            }
        }

        if modelContext.hasChanges { try modelContext.save() }
        return report
    }

    // MARK: Wörterbuch

    public func glossaryTerms() throws -> [GlossaryTerm] {
        try modelContext.fetch(FetchDescriptor<LibraryGlossaryTerm>(sortBy: [SortDescriptor(\.term)])).map { $0.snapshot() }
    }

    public func insertGlossaryTerm(_ term: GlossaryTerm) throws {
        guard try glossaryModel(term.id) == nil else { return try updateGlossaryTerm(term) }
        let model = LibraryGlossaryTerm(id: term.id)
        model.apply(term)
        modelContext.insert(model)
        model.category = try categoryModel(term.categoryID)
        try modelContext.save()
    }

    public func updateGlossaryTerm(_ term: GlossaryTerm) throws {
        guard let model = try glossaryModel(term.id) else { return }
        model.apply(term)
        model.category = try categoryModel(term.categoryID)
        try modelContext.save()
    }

    public func deleteGlossaryTerm(_ id: UUID) throws {
        guard let model = try glossaryModel(id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: Suche

    /// Sucht in der Datenbank (SQLite), statt Transkripte in den Speicher zu laden.
    public func searchRecordingIDs(matching query: String) throws -> Set<UUID> {
        var ids = Set<UUID>()
        for variant in SearchText.variants(query) {
            let titles = FetchDescriptor<LibraryRecording>(predicate: #Predicate { $0.title.localizedStandardContains(variant) })
            ids.formUnion(try modelContext.fetch(titles).map(\.id))

            var notes = FetchDescriptor<LibraryNote>(predicate: #Predicate {
                $0.markdown.localizedStandardContains(variant) || $0.title.localizedStandardContains(variant)
            })
            notes.relationshipKeyPathsForPrefetching = [\.recording]
            ids.formUnion(try modelContext.fetch(notes).compactMap { $0.recording?.id })

            var transcripts = FetchDescriptor<LibraryTranscript>(predicate: #Predicate { $0.plainText.localizedStandardContains(variant) })
            transcripts.relationshipKeyPathsForPrefetching = [\.recording]
            ids.formUnion(try modelContext.fetch(transcripts).compactMap { $0.recording?.id })
        }
        return ids
    }

    // MARK: Übernahme

    public func importItems(_ items: [LibraryImportItem]) throws -> Int {
        let existing = try recordingIDs()
        var inserted = 0
        for item in items where !existing.contains(item.recording.id) {
            let model = LibraryRecording(id: item.recording.id)
            modelContext.insert(model)
            try apply(item.recording, to: model, previous: nil)
            if let transcript = item.transcript {
                let t = LibraryTranscript()
                modelContext.insert(t)
                try t.apply(transcript)
                model.transcript = t
            }
            if let note = item.note {
                let n = LibraryNote()
                modelContext.insert(n)
                n.applyGenerated(note, preview: item.recording.summaryPreview)
                model.note = n
            }
            inserted += 1
        }
        try modelContext.save()
        return inserted
    }
}
