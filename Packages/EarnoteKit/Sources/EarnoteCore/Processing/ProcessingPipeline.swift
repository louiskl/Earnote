import Foundation

/// Rückmeldungen der Pipeline an den Besitzer des Aufnahme-Zustands (die Warteschlange bzw. Bibliothek).
public struct ProcessingEvents: Sendable {
    /// Aktueller Stand einer Aufnahme (nil = inzwischen gelöscht)
    public var recording: @Sendable (UUID) async -> Recording?
    /// Ändert eine Aufnahme und speichert sie
    public var update: @Sendable (UUID, @escaping @Sendable (inout Recording) -> Void) async -> Void
    /// Fortschritt des gesamten Durchgangs (0…1); nur im Speicher, läuft nur vorwärts
    public var progress: @Sendable (UUID, Double) -> Void
    /// Die Notiz, während die KI sie schreibt (roh, mit Titelzeile); nur im Speicher
    public var draft: @Sendable (UUID, String) -> Void

    public init(recording: @escaping @Sendable (UUID) async -> Recording?,
                update: @escaping @Sendable (UUID, @escaping @Sendable (inout Recording) -> Void) async -> Void,
                progress: @escaping @Sendable (UUID, Double) -> Void,
                draft: @escaping @Sendable (UUID, String) -> Void = { _, _ in }) {
        self.recording = recording
        self.update = update
        self.progress = progress
        self.draft = draft
    }
}

/// Was mit der Notiz passieren soll
public enum SummaryRequest: Sendable, Equatable {
    /// Nur schreiben, wenn es noch keine gibt (normaler Durchgang nach der Aufnahme)
    case ifMissing
    /// Neu schreiben – aus dem Transkript, und nur wenn es keins gibt und keins entstehen kann, aus der Notiz
    case again
    /// Neu schreiben aus der bisherigen Notiz (Vereinfachen): Dort steht schon alles Wichtige, und es geht viel schneller
    case fromNote
    /// Übersicht über die Notizen des Bereichs (ab `since`) – der Eintrag selbst ist nur ihr Platzhalter
    case overview(since: Date?)
}

/// Verarbeitet eine Aufnahme: Audio mischen, Stille prüfen, transkribieren, Sprecher zuordnen,
/// zusammenfassen, exportieren, aufräumen. Hält keinen eigenen Zustand und ist an keinen Actor gebunden.
public struct ProcessingPipeline: Sendable {
    public let library: any LibraryRepository
    public let audio: any AudioStore
    public let transcribers: any TranscriberProvider
    public let llm: LLMFactory
    public let destinations: any DestinationProvider
    /// Mitteilung an die Nutzerin / den Nutzer (Titel, Text)
    public let notify: @Sendable (String, String) -> Void
    /// Was während der Aufnahme schon verdichtet wurde (siehe `LiveCondenser`)
    public let precondensed: PreCondensedStore
    /// Sprechererkennung (Earnote Pro, iPhone/iPad) – nil: Transkript ohne erkannte Sprecher
    public let diarizer: (any SpeakerDiarizer)?

    public init(library: any LibraryRepository, audio: any AudioStore, transcribers: any TranscriberProvider, llm: LLMFactory,
                destinations: any DestinationProvider, precondensed: PreCondensedStore = PreCondensedStore(),
                diarizer: (any SpeakerDiarizer)? = nil,
                notify: @escaping @Sendable (String, String) -> Void) {
        self.diarizer = diarizer
        self.library = library
        self.audio = audio
        self.transcribers = transcribers
        self.llm = llm
        self.destinations = destinations
        self.precondensed = precondensed
        self.notify = notify
    }

    /// Ein Durchgang für eine Aufnahme. Fehler landen im Status der Aufnahme; bei Abbruch wird nichts mehr gespeichert.
    /// `extraInstructions` gilt nur für diesen Durchgang (aus „Neu zusammenfassen …“).
    /// Gibt `true` zurück, wenn er an einem vorübergehenden Fehler scheiterte (Netz weg, Anbieter überlastet).
    @discardableResult
    public func process(_ rec: Recording, settings: AppSettings, category: RecordingCategory?,
                        events: ProcessingEvents, extraInstructions: String = "",
                        request: SummaryRequest = .ifMissing) async -> Bool {
        let id = rec.id
        var step = "Transkription"
        do {
            if case .overview(let since) = request {
                step = "Übersicht"
                try await makeOverview(rec, since: since, settings: settings, category: category, events: events,
                                       instruction: extraInstructions)
                return false
            }
            // Wörterbuch: hilft der Spracherkennung und der KI, Namen und Fachbegriffe richtig zu schreiben
            let glossary = Glossary.forCategory(category?.id, in: (try? await library.glossaryTerms()) ?? [])
            // 1) Transkript (falls noch nicht vorhanden)
            var transcript = try await library.transcript(for: id)
            let existing = try await library.note(for: id)
            // Aus der Notiz statt aus dem Transkript: beim Vereinfachen immer, sonst nur, wenn es weder Transkript
            // noch Ton gibt (Übersicht eines Bereichs, Aufnahme mit gelöschtem Ton). Vorher schlug das fehl – und weil
            // die Notiz schon gelöscht war, war sie danach weg.
            let hasAudio = audio.hasAudio(rec)
            let fromNote = existing.flatMap { note in
                request == .fromNote || (transcript == nil && !hasAudio) ? note : nil
            }
            // Übersicht eines Bereichs (oder Aufnahme ohne Ton und Transkript): wird nie exportiert – auch nicht,
            // wenn man sie neu schreibt. Sonst landete sie plötzlich in Notion & Co.
            let notFromAudio = transcript == nil && !hasAudio
            // Eine Übersicht, deren Erstellung unterbrochen wurde (App beendet): Der Platzhalter hat weder Ton noch
            // Transkript noch Notiz. Neu erstellen – mit dem üblichen Zeitraum, der gewählte ist nicht gespeichert.
            if transcript == nil, existing == nil, !hasAudio, rec.categoryID != nil, rec.duration < 1 {
                step = "Übersicht"
                try await makeOverview(rec, since: Calendar.current.date(byAdding: .month, value: -6, to: Date()),
                                       settings: settings, category: category, events: events, instruction: extraInstructions)
                return false
            }
            if transcript == nil, fromNote == nil, !hasAudio {
                throw LLMError(message: t("Für diese Aufnahme gibt es weder Ton noch Transkript oder Notiz – daraus kann keine Notiz entstehen."))
            }
            // Ein durchgehender Balken für die ganze Verarbeitung statt einem neuen pro Schritt:
            // Transkription bis 60 %, Zusammenfassung bis 95 %, der Rest ist der Export.
            let summarySpan = (transcript == nil && fromNote == nil ? 0.6 : 0.0)...0.95
            if transcript == nil, fromNote == nil {
                let started = Date()
                var fresh = try await transcribe(rec, settings: settings, hints: Glossary.speechHints(glossary),
                                                 span: 0...0.6, events: events)
                Self.logDuration("Transkription", since: started, audioSeconds: fresh.segments.last?.end)
                if settings.detectSpeakers, let diarizer, let url = audio.playbackURL(for: rec) {
                    fresh = await Self.withSpeakers(fresh, audio: url, diarizer: diarizer)
                }
                // Nach jedem längeren Schritt prüfen, ob die Aufnahme inzwischen gelöscht oder neu gestartet wurde,
                // damit kein veralteter Stand gespeichert wird.
                try Task.checkCancellation()
                try await library.saveTranscript(fresh, for: id)
                transcript = fresh
            } else if settings.detectSpeakers, existing == nil, fromNote == nil, let current = transcript,
                      let diarizer, let url = audio.playbackURL(for: rec) {
                // Am Mac entsteht das Transkript meist schon während der Aufnahme – dann erst hier die Stimmen erkennen.
                // Nur beim ersten Durchgang (noch keine Notiz), damit „Neu schreiben“ keine Namen überschreibt.
                let named = await Self.withSpeakers(current, audio: url, diarizer: diarizer)
                if Speakers.names(in: named) != Speakers.names(in: current) {
                    try Task.checkCancellation()
                    try await library.saveTranscript(named, for: id)
                    transcript = named
                }
            }
            // Erkannte Sprecher zählen auch, wenn „Ich/Andere“ (Mac) ausgeschaltet ist
            let withSpeakers = settings.speakerLabels || settings.detectSpeakers
            let text = transcript?.formatted(includeSpeakers: withSpeakers) ?? ""
            // „Wichtig!“-Markierungen aus der Aufnahme (Earnote Pro) – nur, wenn die Notiz aus dem Transkript entsteht
            let marks = fromNote == nil ? ImportantMarks.load(in: audio.folderURL(for: id)) : []
            let instructions = [extraInstructions, ImportantMarks.instruction(marks: marks, transcript: transcript)]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")

            // 2) Zusammenfassung – eine vorhandene Notiz wird erst ersetzt, wenn die neue fertig ist
            step = "Zusammenfassung"
            var summary = existing
            if existing == nil || request != .ifMissing, let client = try llm.make(settings.ai) {
                await setStep(id, .summarizing, summarySpan.lowerBound, events)
                let summarizer = Summarizer(client: client, chunkCharacters: settings.ai.provider.chunkCharacters,
                                            providerName: settings.ai.provider.label)
                // Automatische Namen („Meeting – 15. Sept., 19:58“) sind kein Kontext – das Modell würde sie nur als Titel übernehmen
                let context = SummaryContext(category: category, titleHint: rec.hasAutoTitle ? "" : rec.title, sourceApp: rec.sourceApp,
                                             date: rec.startedAt, duration: rec.duration,
                                             hasSpeakers: withSpeakers && transcript?.segments.contains { $0.speaker != nil } == true,
                                             language: settings.ai.summaryLanguage,
                                             glossary: glossary, extraInstructions: instructions,
                                             simpleLanguage: settings.ai.simpleNotes)
                let started = Date()
                var s: Summary
                if let fromNote {
                    s = try await summarizer.rewrite(Self.withoutFlashcards(fromNote.markdown), context: context,
                                                     draft: { events.draft(id, $0) }) { p in
                        events.progress(id, Self.map(p, to: summarySpan))
                    }
                    Self.logDuration("Notiz aus der bisherigen Notiz (\(settings.ai.provider.label), \(fromNote.markdown.count) Zeichen)",
                                     since: started)
                } else {
                    // Nur beim ersten Durchgang: „Neu zusammenfassen“ soll frisch rechnen.
                    let ready = request == .ifMissing && extraInstructions.isEmpty ? await precondensed.take(id) : nil
                    s = try await summarizer.summarize(transcript: text, context: context, precondensed: ready,
                                                       draft: { events.draft(id, $0) }) { p in
                        events.progress(id, Self.map(p, to: summarySpan))
                    }
                    Self.logDuration("Notiz (\(settings.ai.provider.label), \(text.count) Zeichen Transkript)", since: started)
                }
                // Karteikarten gehören zur Aufnahme, nicht zu einer Fassung der Notiz: Sie bleiben beim Neuschreiben erhalten
                if let existing { s.markdown = Self.keepingFlashcards(of: existing.markdown, in: s.markdown) }
                try Task.checkCancellation()
                try await library.saveNote(s, for: id)
                summary = s
                // Die neue Fassung ist unbearbeitet – „Auf KI-Fassung zurücksetzen“ hat nichts mehr zu tun
                await events.update(id) { $0.isNoteEdited = false }
            }
            if let summary {
                await events.update(id) { $0.summaryTitle = summary.title; $0.summaryPreview = summary.preview; $0.taskCount = summary.taskCount }
            }

            // 3) Export
            step = "Export"
            await setStep(id, .exporting, summarySpan.upperBound, events)
            var ids = settings.destinations.enabled
            if let c = category, !c.destinationIDs.isEmpty { ids = c.destinationIDs }
            if notFromAudio { ids = [] }
            let current = await events.recording(id)
            let already = Set((current?.exports ?? []).filter(\.success).map(\.destinationID))
            let payload = ExportPayload(recording: current ?? rec, category: category, summary: summary,
                                        transcript: text, settings: settings.destinations)
            var failures: [String] = []
            for destID in ids.sorted() where !already.contains(destID) {
                try Task.checkCancellation()
                guard let dest = destinations.make(destID), let info = destinations.info(destID) else { continue }
                var result = ExportResult(destinationID: destID, destinationName: info.name, success: false, message: "")
                do {
                    result.url = try await dest.export(payload)
                    result.success = true
                    result.message = "Exportiert"
                } catch let error as DestinationNotConfigured {
                    // Nicht eingerichtet ist kein Fehler: Die Notizen bleiben fertig, das Ziel wird übersprungen.
                    result.message = error.hint
                    result.skipped = true
                    Log.info("Export \(info.name) übersprungen: \(error.hint)")
                } catch {
                    result.message = error.localizedDescription
                    failures.append("\(info.name): \(error.localizedDescription)")
                    Log.error("Export \(info.name): \(error.localizedDescription)")
                }
                let exported = result
                await events.update(id) { r in
                    r.exports.removeAll { $0.destinationID == destID }
                    r.exports.append(exported)
                }
            }

            // 4) Aufräumen
            if !settings.keepAudioFiles, let latest = await events.recording(id) { audio.deleteAudio(for: latest) }
            let failed = failures
            await events.update(id) {
                $0.status = failed.isEmpty ? .done : .failed
                $0.progress = 1
                $0.errorMessage = failed.isEmpty ? nil : t("Export teilweise fehlgeschlagen:") + "\n" + failed.joined(separator: "\n")
            }
            let title = summary?.title ?? rec.title
            notify(failures.isEmpty ? t("Notizen fertig") : t("Notizen fertig (mit Export-Fehlern)"), title)
            Log.info("Fertig verarbeitet: \(title)")
        } catch let error where Task.isCancelled || error is CancellationError {
            // Gelöscht oder neu eingereiht – der Status wurde dort bereits gesetzt
            Log.info("Verarbeitung abgebrochen: \(rec.title)")
        } catch {
            let msg = Self.failure(step, error)
            await events.update(id) { $0.status = .failed; $0.errorMessage = msg }
            notify(t("Verarbeitung fehlgeschlagen"), "\(rec.title): \(msg)")
            Log.error("Verarbeitung \(id): \(msg)")
            return Self.isTemporary(error)
        }
        return false
    }

    /// Fehler, bei denen ein späterer Versuch wahrscheinlich klappt – alles andere (falscher Schlüssel, kein Audio) nicht
    static func isTemporary(_ error: Error) -> Bool {
        if let error = error as? LLMError { return error.isTemporary }
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .dnsLookupFailed,
                    .dataNotAllowed, .internationalRoamingOff].contains(error.code)
        }
        return false
    }

    /// Sprecher erkennen und eintragen. Klappt das nicht, bleibt das Transkript ohne Sprecher – die Notiz entsteht trotzdem.
    public static func withSpeakers(_ transcript: Transcript, audio: URL, diarizer: any SpeakerDiarizer) async -> Transcript {
        let started = Date()
        do {
            guard let turns = try await diarizer.diarize(audio, progress: { _ in }) else { return transcript }
            logDuration("Sprechererkennung", since: started, audioSeconds: transcript.segments.last?.end)
            return Speakers.assign(turns, to: transcript)
        } catch {
            Log.error("Sprechererkennung: \(error)")
            return transcript
        }
    }

    private func transcribe(_ rec: Recording, settings: AppSettings, hints: [String], span: ClosedRange<Double>,
                            events: ProcessingEvents) async throws -> Transcript {
        let id = rec.id
        await setStep(id, .transcribing, span.lowerBound, events)
        let transcriber = try await transcribers.makeTranscriber(for: settings)

        // Audio vorbereiten (mischen, 16 kHz)
        let source: URL
        var envelope: EnergyEnvelope?
        if let imported = rec.importedFileName {
            source = audio.importedAudioURL(for: id, fileName: imported)
        } else {
            let mic = audio.micURL(for: id)
            let system: URL? = rec.hasSystemAudio ? audio.systemURL(for: id) : nil
            let out = audio.mixURL(for: id)
            envelope = try await Task.detached(priority: .userInitiated) {
                try AudioMixer.mix(mic: mic, system: system, output: out) { p in
                    events.progress(id, Self.map(p * 0.1, to: span))
                }
            }.value
            source = out
        }

        let peak = await Task.detached { AudioMixer.peakDecibels(of: source) }.value
        Log.info("Pegel der Aufnahme: \(peak) dB")
        if peak < -50 {
            // Völlige Stille ergibt -∞ dB; die Umwandlung in Int würde abstürzen
            throw TranscriptionError.unavailable(
                t("Die Aufnahme ist stumm (Pegel \(Int(max(peak, -160))) dB). Prüfe in den Systemeinstellungen, ob \(AppInfo.name) das Mikrofon verwenden darf und das richtige Eingabegerät ausgewählt ist."))
        }

        // Fast nur Stille: Whisper würde daraus Sätze erfinden – lieber gleich sagen, dass nichts zu hören war.
        if let envelope, envelope.loudShare < 0.005 {
            throw TranscriptionError.noSpeech
        }

        let offset = envelope == nil ? 0.0 : 0.1
        var segments = try await transcriber.transcribe(audio: source, language: rec.language, hints: hints) { p in
            events.progress(id, Self.map(offset + p * (1 - offset), to: span))
        }
        // Schleifen und die Sätze, die Whisper aus Stille erfindet, gehören nicht ins Transkript –
        // sonst entsteht daraus eine Notiz über ein Gespräch, das nie stattgefunden hat.
        let raw = segments.count
        segments = TranscriptCleanup.clean(segments, hints: hints)
        if segments.count < raw { Log.info("Transkript bereinigt: \(raw - segments.count) von \(raw) Abschnitten entfernt") }
        guard TranscriptCleanup.spokenWords(segments) >= 3 else { throw TranscriptionError.noSpeech }

        // „Ich“/„Andere“ nur, wenn beide Spuren etwas beigetragen haben. Sonst (typische Vorlesung:
        // alles kommt aus dem Mikrofon) wäre die Zuordnung geraten und stünde nur im Weg.
        if let envelope, rec.hasSystemAudio, envelope.hasTwoSources {
            for i in segments.indices {
                segments[i].speaker = envelope.speaker(from: segments[i].start, to: segments[i].end)
            }
        } else if let envelope, rec.hasSystemAudio {
            Log.info(String(format: "Keine Sprecher-Zuordnung: Mikrofon %.0f %%, Systemton %.0f %% der Zeit aktiv",
                            envelope.micLoudShare * 100, envelope.systemLoudShare * 100))
        }
        return Transcript(segments: segments, engine: transcriber.engineName)
    }

    /// Übersicht über mehrere Aufnahmen eines Bereichs. Läuft wie jede Verarbeitung in der Warteschlange:
    /// Das Fenster ist sofort wieder frei, Fortschritt und entstehender Text stehen am Eintrag selbst.
    private func makeOverview(_ rec: Recording, since: Date?, settings: AppSettings, category: RecordingCategory?,
                              events: ProcessingEvents, instruction: String) async throws {
        let id = rec.id
        guard let category else { throw LLMError(message: t("Diese Übersicht gehört zu keinem Bereich mehr.")) }
        await setStep(id, .summarizing, 0, events)
        // Übersichten selbst haben keine Laufzeit – so fließt eine frühere Übersicht nicht in die nächste ein
        let candidates = try await library.recordings().filter { r in
            r.id != id && r.categoryID == category.id && r.status == .done && r.duration >= 1
                && (since.map { r.startedAt >= $0 } ?? true)
        }
        var sources: [PeriodSummary.Source] = []
        for r in candidates {
            if let note = try await library.note(for: r.id) {
                sources.append(PeriodSummary.Source(title: r.displayTitle, date: r.startedAt, markdown: note.markdown))
            }
        }
        guard sources.count >= 2 else {
            throw LLMError(message: t("Für eine Übersicht braucht es mindestens zwei fertige Aufnahmen mit Notiz in diesem Bereich."))
        }
        guard let client = try llm.make(settings.ai) else {
            throw LLMError(message: t("Für eine Übersicht braucht es eine KI. Wähle in den Einstellungen unter „KI“ eine aus."))
        }
        let limit = settings.ai.provider.chunkCharacters
        let material = PeriodSummary.material(sources, limit: limit)
        let tracker = MonotonicProgress { events.progress(id, $0) }
        let estimate = tracker.creep(to: 0.95, typicalSeconds: 30 + Double(material.count) / 250)
        defer { estimate.cancel() }
        let started = Date()
        guard var overview = try await PeriodSummary.generate(
            client: client, sources: sources, subject: category.name, language: settings.ai.summaryLanguage,
            simple: settings.ai.simpleNotes, extra: instruction, limit: limit,
            providerName: settings.ai.provider.label, partial: { events.draft(id, $0) }) else {
            throw LLMError(message: t("Die KI hat keine Übersicht geliefert. Versuch es noch einmal."))
        }
        // Aufgaben nur, wenn sie in den Notizen stehen oder dort jemand etwas aufgetragen hat
        overview.markdown = TaskCheck.clean(overview.markdown, transcript: material)
        overview.taskCount = NoteMarkdown.openTaskCount(overview.markdown)
        try Task.checkCancellation()
        try await library.saveNote(overview, for: id)
        let done = overview
        await events.update(id) {
            $0.title = done.title
            $0.isTitleCustom = true
            $0.summaryTitle = done.title
            $0.summaryPreview = done.preview
            $0.taskCount = done.taskCount
            $0.isNoteEdited = false
            $0.status = .done
            $0.progress = 1
            $0.errorMessage = nil
        }
        Self.logDuration("Übersicht „\(category.name)“ aus \(PeriodSummary.fittingCount(sources, limit: limit)) von \(sources.count) Notizen",
                         since: started)
        notify(t("Übersicht fertig"), done.title)
    }

    /// Die Notiz ohne ihren Karteikarten-Abschnitt – als Material zum Umschreiben
    static func withoutFlashcards(_ markdown: String) -> String {
        ["Karteikarten", "Flashcards"].reduce(markdown) { NoteMarkdown.removingSection(named: $1, from: $0) }
    }

    /// Hängt die Karteikarten der alten Notiz an die neue, wenn diese selbst keine hat
    static func keepingFlashcards(of old: String, in new: String) -> String {
        let cards = Flashcards.parse(old)
        guard !cards.isEmpty, Flashcards.parse(new).isEmpty else { return new }
        let heading = old.contains("## Flashcards") ? "Flashcards" : "Karteikarten"
        return new.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + Flashcards.markdownSection(cards, heading: heading)
    }

    private func setStep(_ id: UUID, _ status: RecordingStatus, _ progress: Double, _ events: ProcessingEvents) async {
        await events.update(id) { $0.status = status; $0.progress = progress }
    }

    /// Wie lange ein Schritt gebraucht hat – die Grundlage für alle Geschwindigkeitsfragen.
    /// Mit `audioSeconds` steht auch das Verhältnis zur Aufnahmedauer im Protokoll („12× Echtzeit“).
    /// „Transkription fehlgeschlagen: …“ – `step` bleibt fürs Protokoll deutsch, die Meldung folgt der Sprache der App.
    static func failure(_ step: String, _ error: Error) -> String {
        t("\(t(String.LocalizationValue(step))) fehlgeschlagen: \(error.localizedDescription)")
    }

    static func logDuration(_ step: String, since start: Date, audioSeconds: Double? = nil) {
        let seconds = Date().timeIntervalSince(start)
        var line = String(format: "%@ fertig in %.0f s", step, seconds)
        if let audioSeconds, audioSeconds > 0, seconds > 0 {
            line += String(format: " (%.0f s Audio, %.1f× Echtzeit)", audioSeconds, audioSeconds / seconds)
        }
        Log.info(line)
    }

    /// Fortschritt eines Schritts (0…1) auf seinen Abschnitt des Gesamtbalkens abbilden.
    static func map(_ progress: Double, to span: ClosedRange<Double>) -> Double {
        span.lowerBound + (span.upperBound - span.lowerBound) * min(max(progress, 0), 1)
    }
}
