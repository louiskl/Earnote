import AVFoundation
import Foundation

/// Übernimmt einmalig die Bibliothek aus dem alten Dateiformat (meta.json usw.) und die Bereiche aus UserDefaults.
/// Liest die alten Dateien nur – sie bleiben als Rückfallmöglichkeit unverändert liegen, Audio bleibt, wo es ist.
/// Wiederholbar: schon übernommene IDs werden übersprungen, das Flag wird erst nach fehlerfreiem Lauf gesetzt.
public struct FileLibraryImporter: @unchecked Sendable {
    public static let versionKey = "libraryImportVersion"
    /// So viele Aufnahmen werden je Etappe gespeichert
    static let batchSize = 20

    public struct Report: Sendable, Equatable {
        public var categories = 0
        public var recordings = 0
        public var transcripts = 0
        public var notes = 0
        /// Zuordnungen zu Bereichen, die es nicht mehr gibt (auf „ohne Bereich“ gesetzt)
        public var orphanedCategories = 0
        /// Über den Namen wiederhergestellte Zuordnungen
        public var repairedCategories = 0
        /// Schon vorher übernommen
        public var skipped = 0
        public var errors: [String] = []
        /// Übernahme war schon erledigt; nichts gelesen
        public var alreadyDone = false

        public var summary: String {
            if alreadyDone { return "Bibliothek bereits übernommen" }
            return "Übernahme der Bibliothek: \(categories) Bereiche, \(recordings) Aufnahmen, \(transcripts) Transkripte, "
                + "\(notes) Notizen, \(orphanedCategories) verwaiste Zuordnungen, \(repairedCategories) reparierte Zuordnungen, "
                + "\(skipped) schon vorhanden, \(errors.count) Fehler"
        }
    }

    private let reader: LegacyFileLibraryReader
    private let library: any LibraryRepository
    private let audio: any AudioStore
    private let defaults: UserDefaults

    public init(reader: LegacyFileLibraryReader, library: any LibraryRepository, audio: any AudioStore,
                defaults: UserDefaults = .standard) {
        self.reader = reader
        self.library = library
        self.audio = audio
        self.defaults = defaults
    }

    /// Läuft außerhalb des Hauptthreads; das Speichern übernimmt der Actor des Repositorys.
    public func runIfNeeded() async -> Report {
        guard defaults.integer(forKey: Self.versionKey) < 1 else { return Report(alreadyDone: true) }
        var report = Report()
        do {
            let categories = try await importCategories(&report)
            try await importRecordings(categories: categories, report: &report)
        } catch {
            report.errors.append("Übernahme abgebrochen: \(error.localizedDescription)")
        }
        if report.errors.isEmpty { defaults.set(1, forKey: Self.versionKey) }
        Log.info(report.summary)
        for error in report.errors { Log.error("Übernahme: \(error)") }
        return report
    }

    /// Bereiche zuerst: IDs und Reihenfolge bleiben erhalten. Ohne gespeicherte Bereiche die Standardbereiche anlegen,
    /// wie es die App bisher beim ersten Start getan hat.
    private func importCategories(_ report: inout Report) async throws -> [RecordingCategory] {
        let legacy = defaults.data(forKey: "categories").flatMap { try? JSONDecoder().decode([RecordingCategory].self, from: $0) }
        if defaults.data(forKey: "categories") != nil, legacy == nil {
            Log.error("Übernahme: gespeicherte Bereiche nicht lesbar, verwende Standardbereiche")
        }
        let wanted = RecordingCategory.migrated(legacy ?? RecordingCategory.defaults)
        let existing = Set(try await library.categories().map(\.id))
        for (index, category) in wanted.enumerated() where !existing.contains(category.id) {
            try await library.insertCategory(category, sortIndex: index)
            report.categories += 1
        }
        return try await library.categories()
    }

    private func importRecordings(categories: [RecordingCategory], report: inout Report) async throws {
        let known = Set(categories.map(\.id))
        let existing = try await library.recordingIDs()
        var batch: [LibraryImportItem] = []

        func flush() async throws {
            guard !batch.isEmpty else { return }
            let inserted = try await library.importItems(batch)
            report.skipped += batch.count - inserted
            batch.removeAll()
        }

        for folder in reader.recordingFolders() {
            do {
                var recording = try reader.readRecording(in: folder)
                if existing.contains(recording.id) {
                    report.skipped += 1
                    continue
                }
                let entry = try reader.readEntry(in: folder, recording: recording)

                // Frühere Namens-Reparatur einmal anwenden, danach verwaiste Zuordnungen lösen
                if let id = recording.categoryID, !known.contains(id) {
                    if let match = categories.first(where: { recording.title.hasPrefix("\($0.name) – ") }) {
                        recording.categoryID = match.id
                        report.repairedCategories += 1
                    } else {
                        recording.categoryID = nil
                        report.orphanedCategories += 1
                    }
                }
                recording.isTitleCustom = !Recording.looksAutomatic(recording.title)
                normalizeStatus(&recording)
                recording.progress = 0
                if recording.summaryPreview == nil { recording.summaryPreview = entry.summary?.preview }

                batch.append(LibraryImportItem(recording: recording, transcript: entry.transcript, note: entry.summary))
                report.recordings += 1
                if entry.transcript != nil { report.transcripts += 1 }
                if entry.summary != nil { report.notes += 1 }
                if batch.count >= Self.batchSize { try await flush() }
            } catch {
                report.errors.append(error.localizedDescription)
            }
        }
        try await flush()
    }

    /// Unterbrochene Aufnahmen und Verarbeitungen werden beim Start wieder eingereiht.
    private func normalizeStatus(_ recording: inout Recording) {
        if recording.status == .recording {
            // Ende aus der tatsächlich aufgenommenen Länge ableiten, nicht aus dem Zeitpunkt der Übernahme
            if let file = try? AVAudioFile(forReading: audio.micURL(for: recording.id)), file.processingFormat.sampleRate > 0 {
                recording.endedAt = recording.startedAt.addingTimeInterval(Double(file.length) / file.processingFormat.sampleRate)
                recording.pausedDuration = nil
            } else {
                recording.endedAt = recording.endedAt ?? Date()
            }
        }
        if recording.status == .recording || recording.status.isBusy { recording.status = .queued }
    }
}
