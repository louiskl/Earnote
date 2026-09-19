import Foundation

/// Transkribiert schon **während** der Aufnahme, Abschnitt für Abschnitt.
///
/// Warum: Eine 90-Minuten-Vorlesung braucht danach sonst erst einmal eine halbe Stunde Rechenzeit,
/// bevor die Notiz entsteht. Hier wird alle paar Minuten der bereits aufgenommene Ton gemischt und
/// transkribiert; nach dem Stopp bleibt nur der letzte Abschnitt übrig.
///
/// Geschnitten wird nicht auf die Sekunde, sondern am letzten fertigen Abschnitt des Transkripts:
/// Der letzte Satz eines Stücks kann mitten im Wort abgeschnitten sein und wird deshalb verworfen –
/// das nächste Stück beginnt genau dort, wo der letzte behaltene Satz endete.
public actor LiveTranscription {
    private let recordingID: UUID
    private let hasSystemAudio: Bool
    private let language: String
    private let hints: [String]
    private let audio: any AudioStore
    private let transcriber: any Transcriber
    /// So viel neuer Ton muss da sein, damit sich ein Durchgang lohnt
    private let chunkSeconds: Double

    private var segments: [TranscriptSegment] = []
    /// Bis hierhin ist das Transkript fertig (Sekunden seit Aufnahmebeginn)
    private var covered: Double = 0
    private var failed = false
    private var running = false

    public init(recordingID: UUID, hasSystemAudio: Bool, language: String, hints: [String],
                audio: any AudioStore, transcriber: any Transcriber, chunkSeconds: Double = 240) {
        self.recordingID = recordingID
        self.hasSystemAudio = hasSystemAudio
        self.language = language
        self.hints = hints
        self.audio = audio
        self.transcriber = transcriber
        self.chunkSeconds = chunkSeconds
    }

    /// Fertige Sekunden – für die Fortschrittsanzeige
    public var coveredSeconds: Double { covered }

    /// Ist unterwegs etwas schiefgegangen, wird nach dem Stopp normal von vorn transkribiert.
    public var hasFailed: Bool { failed }

    /// Transkribiert den nächsten Abschnitt, wenn genug neuer Ton da ist. Sonst passiert nichts.
    public func advance() async {
        guard !failed, !running else { return }
        let available = AudioMixer.availableSeconds(mic: audio.micURL(for: recordingID),
                                                    system: hasSystemAudio ? audio.systemURL(for: recordingID) : nil)
        guard available - covered >= chunkSeconds else { return }
        await run(until: available, isLast: false)
    }

    /// Nach dem Stopp: den Rest transkribieren und das ganze Transkript liefern.
    /// `nil` heißt: bitte normal (komplett) transkribieren.
    public func finish() async -> Transcript? {
        guard !failed else { return nil }
        let available = AudioMixer.availableSeconds(mic: audio.micURL(for: recordingID),
                                                    system: hasSystemAudio ? audio.systemURL(for: recordingID) : nil)
        if available - covered > 0.5 { await run(until: available, isLast: true) }
        guard !failed, !segments.isEmpty else { return nil }
        return Transcript(segments: segments, engine: transcriber.engineName)
    }

    /// Ein Abschnitt: mischen, transkribieren, Sprecher zuordnen, anhängen.
    private func run(until end: Double, isLast: Bool) async {
        running = true
        defer { running = false }
        let start = covered
        let chunkURL = audio.folderURL(for: recordingID).appendingPathComponent("live-chunk.wav")
        let mic = audio.micURL(for: recordingID)
        let system = hasSystemAudio ? audio.systemURL(for: recordingID) : nil
        do {
            let envelope = try AudioMixer.mix(mic: mic, system: system, output: chunkURL,
                                              from: start, to: end, progress: { _ in })
            var fresh = try await transcriber.transcribe(audio: chunkURL, language: language, hints: hints, progress: { _ in })
            try? FileManager.default.removeItem(at: chunkURL)
            fresh = TranscriptCleanup.clean(fresh)
            // Der letzte Satz eines Zwischenstücks kann abgeschnitten sein – ihn macht der nächste Durchgang neu.
            if !isLast, fresh.count > 1 { fresh.removeLast() }
            guard !fresh.isEmpty else {
                // Nichts Verwertbares (z. B. eine stille Pause): Abschnitt überspringen, aber weiterlaufen.
                covered = end
                return
            }
            for i in fresh.indices {
                fresh[i].start += start
                fresh[i].end += start
                if hasSystemAudio {
                    fresh[i].speaker = envelope.speaker(from: fresh[i].start - start, to: fresh[i].end - start)
                }
            }
            segments += fresh
            covered = isLast ? end : (fresh.last?.end ?? end)
            Log.info("Live-Transkript: \(Int(covered)) von \(Int(end)) Sekunden fertig")
        } catch {
            try? FileManager.default.removeItem(at: chunkURL)
            failed = true
            Log.error("Live-Transkript abgebrochen, es wird nach der Aufnahme komplett transkribiert: \(error.localizedDescription)")
        }
    }
}
