import Foundation

/// Rückmeldungen der Pipeline an den Besitzer des Aufnahme-Zustands (die Warteschlange bzw. Bibliothek).
public struct ProcessingEvents: Sendable {
    /// Aktueller Stand einer Aufnahme (nil = inzwischen gelöscht)
    public var recording: @Sendable (UUID) async -> Recording?
    /// Ändert eine Aufnahme und speichert sie
    public var update: @Sendable (UUID, @escaping @Sendable (inout Recording) -> Void) async -> Void
    /// Fortschritt des gesamten Durchgangs (0…1); nur im Speicher, läuft nur vorwärts
    public var progress: @Sendable (UUID, Double) -> Void

    public init(recording: @escaping @Sendable (UUID) async -> Recording?,
                update: @escaping @Sendable (UUID, @escaping @Sendable (inout Recording) -> Void) async -> Void,
                progress: @escaping @Sendable (UUID, Double) -> Void) {
        self.recording = recording
        self.update = update
        self.progress = progress
    }
}

/// Verarbeitet eine Aufnahme: Audio mischen, Stille prüfen, transkribieren, Sprecher zuordnen,
/// zusammenfassen, exportieren, aufräumen. Hält keinen eigenen Zustand und ist an keinen Actor gebunden.
public struct ProcessingPipeline: Sendable {
    public let repository: any RecordingRepository
    public let transcribers: any TranscriberProvider
    public let llm: LLMFactory
    public let destinations: any DestinationProvider
    /// Mitteilung an die Nutzerin / den Nutzer (Titel, Text)
    public let notify: @Sendable (String, String) -> Void

    public init(repository: any RecordingRepository, transcribers: any TranscriberProvider, llm: LLMFactory,
                destinations: any DestinationProvider, notify: @escaping @Sendable (String, String) -> Void) {
        self.repository = repository
        self.transcribers = transcribers
        self.llm = llm
        self.destinations = destinations
        self.notify = notify
    }

    /// Ein Durchgang für eine Aufnahme. Fehler landen im Status der Aufnahme; bei Abbruch wird nichts mehr gespeichert.
    public func process(_ rec: Recording, settings: AppSettings, category: RecordingCategory?,
                        events: ProcessingEvents) async {
        let id = rec.id
        var step = "Transkription"
        do {
            // 1) Transkript (falls noch nicht vorhanden)
            var transcript = repository.transcript(for: id)
            // Ein durchgehender Balken für die ganze Verarbeitung statt einem neuen pro Schritt:
            // Transkription bis 60 %, Zusammenfassung bis 95 %, der Rest ist der Export.
            let summarySpan = (transcript == nil ? 0.6 : 0.0)...0.95
            if transcript == nil {
                let fresh = try await transcribe(rec, settings: settings, span: 0...0.6, events: events)
                // Nach jedem längeren Schritt prüfen, ob die Aufnahme inzwischen gelöscht oder neu gestartet wurde,
                // damit kein veralteter Stand gespeichert wird.
                try Task.checkCancellation()
                repository.saveTranscript(fresh, for: id)
                transcript = fresh
            }
            guard let transcript else { return }
            let text = transcript.formatted(includeSpeakers: settings.speakerLabels)

            // 2) Zusammenfassung
            step = "Zusammenfassung"
            var summary = repository.summary(for: id)
            if summary == nil, let client = try llm.make(settings.ai) {
                await setStep(id, .summarizing, summarySpan.lowerBound, events)
                let summarizer = Summarizer(client: client, chunkCharacters: settings.ai.provider.chunkCharacters,
                                            providerName: settings.ai.provider.label)
                // Automatische Namen („Meeting – 15. Sept., 19:58“) sind kein Kontext – das Modell würde sie nur als Titel übernehmen
                let context = SummaryContext(category: category, titleHint: rec.hasAutoTitle ? "" : rec.title, sourceApp: rec.sourceApp,
                                             date: rec.startedAt, duration: rec.duration,
                                             hasSpeakers: settings.speakerLabels && rec.hasSystemAudio,
                                             language: settings.ai.summaryLanguage)
                let s = try await summarizer.summarize(transcript: text, context: context) { p in
                    events.progress(id, Self.map(p, to: summarySpan))
                }
                try Task.checkCancellation()
                repository.saveSummary(s, for: id)
                summary = s
            }
            if let summary {
                await events.update(id) { $0.summaryTitle = summary.title; $0.summaryPreview = summary.preview; $0.taskCount = summary.taskCount }
            }

            // 3) Export
            step = "Export"
            await setStep(id, .exporting, summarySpan.upperBound, events)
            var ids = settings.destinations.enabled
            if let c = category, !c.destinationIDs.isEmpty { ids = c.destinationIDs }
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
            if !settings.keepAudioFiles, let latest = await events.recording(id) { repository.deleteAudio(for: latest) }
            let failed = failures
            await events.update(id) {
                $0.status = failed.isEmpty ? .done : .failed
                $0.progress = 1
                $0.errorMessage = failed.isEmpty ? nil : "Export teilweise fehlgeschlagen:\n" + failed.joined(separator: "\n")
            }
            let title = summary?.title ?? rec.title
            notify(failures.isEmpty ? "Notizen fertig" : "Notizen fertig (mit Export-Fehlern)", title)
            Log.info("Fertig verarbeitet: \(title)")
        } catch let error where Task.isCancelled || error is CancellationError {
            // Gelöscht oder neu eingereiht – der Status wurde dort bereits gesetzt
            Log.info("Verarbeitung abgebrochen: \(rec.title)")
        } catch {
            let msg = "\(step) fehlgeschlagen: \(error.localizedDescription)"
            await events.update(id) { $0.status = .failed; $0.errorMessage = msg }
            notify("Verarbeitung fehlgeschlagen", "\(rec.title): \(msg)")
            Log.error("Verarbeitung \(id): \(msg)")
        }
    }

    private func transcribe(_ rec: Recording, settings: AppSettings, span: ClosedRange<Double>,
                            events: ProcessingEvents) async throws -> Transcript {
        let id = rec.id
        await setStep(id, .transcribing, span.lowerBound, events)
        let transcriber = try await transcribers.makeTranscriber(for: settings)

        // Audio vorbereiten (mischen, 16 kHz)
        let source: URL
        var envelope: EnergyEnvelope?
        if let imported = rec.importedFileName {
            source = repository.importedAudioURL(for: id, fileName: imported)
        } else {
            let mic = repository.micURL(for: id)
            let system: URL? = rec.hasSystemAudio ? repository.systemURL(for: id) : nil
            let out = repository.mixURL(for: id)
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
                "Die Aufnahme ist stumm (Pegel \(Int(max(peak, -160))) dB). Prüfe in den Systemeinstellungen, ob \(AppInfo.name) das Mikrofon verwenden darf und das richtige Eingabegerät ausgewählt ist.")
        }

        let offset = envelope == nil ? 0.0 : 0.1
        var segments = try await transcriber.transcribe(audio: source, language: rec.language) { p in
            events.progress(id, Self.map(offset + p * (1 - offset), to: span))
        }
        guard !segments.isEmpty else { throw TranscriptionError.noSpeech }

        if let envelope, rec.hasSystemAudio {
            for i in segments.indices {
                segments[i].speaker = envelope.speaker(from: segments[i].start, to: segments[i].end)
            }
        }
        return Transcript(segments: segments, engine: transcriber.engineName)
    }

    private func setStep(_ id: UUID, _ status: RecordingStatus, _ progress: Double, _ events: ProcessingEvents) async {
        await events.update(id) { $0.status = status; $0.progress = progress }
    }

    /// Fortschritt eines Schritts (0…1) auf seinen Abschnitt des Gesamtbalkens abbilden.
    static func map(_ progress: Double, to span: ClosedRange<Double>) -> Double {
        span.lowerBound + (span.upperBound - span.lowerBound) * min(max(progress, 0), 1)
    }
}
