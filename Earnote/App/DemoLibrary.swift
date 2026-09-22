#if DEBUG
import EarnoteCore
import Foundation

/// Beispieldaten für Bildschirmfotos, das Demo-Video und den Design-Review.
///
/// Wird mit `EARNOTE_DEMO_LIBRARY=1` zusammen mit `EARNOTE_SANDBOX=<Ordner>` eingeschaltet – die
/// echte Bibliothek wird dabei nie angefasst. Die Daten sind so gewählt, dass ein Bild davon die App
/// zeigt, wie sie nach ein paar Wochen Semester aussieht: mehrere Bereiche, Aufnahmen über mehrere
/// Tage, Aufgaben, Karteikarten, ein Meeting und eine Semester-Übersicht.
///
/// Mit `EARNOTE_DEMO_AUDIO=<Pfad>` bekommt die oberste Aufnahme eine echte Tonspur – nötig, wenn im
/// Video eine Zeitmarke angeklickt werden soll.
@MainActor
enum DemoLibrary {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["EARNOTE_DEMO_LIBRARY"] != nil }

    /// Auf Englisch gestartet? Dann auch englische Beispieldaten – sonst passen die Bilder nicht.
    private static var english: Bool { Locale.preferredLanguages.first?.hasPrefix("en") == true }

    static func fill(library: LibraryStore, repository: any LibraryRepository, audio: any AudioStore) async {
        guard isRequested, (try? await repository.recordings())?.isEmpty == true else { return }
        let areas = areas(english: english)
        if library.categories.count < areas.count { library.categories = areas }
        // Erst weitermachen, wenn die Bereiche wirklich in der Datenbank stehen – sonst findet die
        // erste Aufnahme ihren Bereich nicht und steht als „Ohne Bereich“ da.
        await library.waitForPendingWrites()
        let byName = Dictionary(uniqueKeysWithValues: library.categories.map { ($0.name, $0.id) })

        for entry in entries(english: english) {
            var rec = Recording(title: entry.title, categoryID: byName[entry.area],
                                sourceApp: entry.sourceApp,
                                startedAt: Date().addingTimeInterval(entry.ago))
            rec.endedAt = rec.startedAt.addingTimeInterval(entry.length)
            rec.status = .done
            rec.language = english ? "en" : "de"
            rec.hasSystemAudio = entry.sourceApp != nil
            rec.isTitleCustom = entry.isOverview
            let note = Summary(title: entry.noteTitle, markdown: entry.markdown,
                               taskCount: entry.markdown.components(separatedBy: "- [ ]").count - 1,
                               provider: english ? "Local AI" : "Lokale KI")
            rec.summaryTitle = note.title
            rec.summaryPreview = note.preview
            rec.taskCount = note.taskCount

            try? await repository.insertRecording(rec)
            try? await repository.saveNote(note, for: rec.id)
            if !entry.transcript.isEmpty {
                try? await repository.saveTranscript(
                    Transcript(segments: entry.transcript, engine: "Whisper large-v3-turbo"), for: rec.id)
            }
            if entry.isExported {
                try? await repository.setExports([
                    ExportResult(destinationID: MarkdownDestination.id, destinationName: "Markdown",
                                 success: true, message: english ? "Exported" : "Exportiert",
                                 url: "file:///Users/demo/Documents/Earnote/\(entry.title).md"),
                ], for: rec.id)
            }
            // Nur die oberste Aufnahme bekommt Ton – für den Klick auf eine Zeitmarke im Video
            if entry.withAudio, let path = ProcessInfo.processInfo.environment["EARNOTE_DEMO_AUDIO"] {
                audio.createFolder(for: rec.id)
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: audio.mixURL(for: rec.id))
            }
        }

        for term in glossary(english: english) {
            try? await repository.insertGlossaryTerm(term)
        }
        await library.load()
    }

    // MARK: Bereiche

    private static func areas(english: Bool) -> [RecordingCategory] {
        let lecture = RecordingCategory.defaults.first?.instructions ?? ""
        return [
            RecordingCategory(name: english ? "Linear Algebra" : "Analysis II", emoji: "📐",
                              symbol: "graduationcap.fill", colorHex: "#E8453B", instructions: lecture),
            RecordingCategory(name: english ? "Operating Systems" : "Betriebssysteme", emoji: "🖥️",
                              symbol: "book.fill", colorHex: "#2563EB", instructions: lecture),
            RecordingCategory(name: english ? "Study group" : "Lerngruppe", emoji: "👥",
                              symbol: "person.3.fill", colorHex: "#10B981", instructions: lecture),
            RecordingCategory(name: english ? "Project meeting" : "Projektmeeting", emoji: "💼",
                              symbol: "person.3.fill", colorHex: "#F59E0B",
                              instructions: english
                                ? "Note decisions, open questions and who agreed to do what by when."
                                : "Halte Beschlüsse, offene Fragen und Aufgaben mit Verantwortlichen und Fristen fest."),
        ]
    }

    // MARK: Aufnahmen

    private struct Entry {
        let title: String
        let area: String
        let noteTitle: String
        let markdown: String
        var transcript: [TranscriptSegment] = []
        var ago: TimeInterval
        var length: TimeInterval
        var sourceApp: String?
        var isExported = false
        var withAudio = false
        var isOverview = false
    }

    private static func entries(english: Bool) -> [Entry] {
        english ? englishEntries : germanEntries
    }

    private static var germanEntries: [Entry] {
        [
            Entry(title: "Analysis II – Eigenwerte",
                  area: "Analysis II",
                  noteTitle: "Eigenwerte und Eigenvektoren",
                  markdown: """
                  In der Vorlesung ging es um Eigenwerte, ihre Berechnung über das charakteristische Polynom \
                  und darum, warum sie für die Diagonalisierbarkeit einer Matrix entscheidend sind.

                  ## Rechenweg
                  - Charakteristisches Polynom aufstellen: det(A − λE) = 0
                  - Nullstellen bestimmen – das sind die Eigenwerte
                  - Für jeden Eigenwert den Eigenraum berechnen

                  ## Wichtig für die Klausur
                  - Eine Matrix ist genau dann diagonalisierbar, wenn die Summe der geometrischen \
                  Vielfachheiten der Dimension entspricht
                  - Bei doppelten Nullstellen immer beide Vielfachheiten prüfen

                  ## Aufgaben
                  - [ ] Übungsblatt 4 bis Freitag rechnen
                  - [ ] Klausurtermin am 12. Februar notieren

                  ## Karteikarten
                  - Was ist ein Eigenwert? :: Der Faktor, um den ein Eigenvektor durch die Abbildung gestreckt wird.
                  - Wie berechnet man Eigenwerte? :: Über die Nullstellen des charakteristischen Polynoms det(A − λE) = 0.
                  - Wann ist eine Matrix diagonalisierbar? :: Wenn die Summe der geometrischen Vielfachheiten \
                  gleich der Dimension des Raums ist.
                  - Was ist der Eigenraum? :: Der Kern von (A − λE), also alle Eigenvektoren zu einem Eigenwert.
                  """,
                  transcript: [
                    TranscriptSegment(start: 0, end: 7, text: "Guten Morgen. Heute sprechen wir über Eigenwerte und Eigenvektoren."),
                    TranscriptSegment(start: 7, end: 21, text: "Ein Eigenwert ist der Faktor, um den ein Eigenvektor durch die Abbildung gestreckt wird."),
                    TranscriptSegment(start: 21, end: 39, text: "Berechnet wird er über das charakteristische Polynom, also die Determinante von A minus Lambda mal der Einheitsmatrix."),
                    TranscriptSegment(start: 39, end: 58, text: "Vorsicht bei doppelten Nullstellen: Da müssen Sie die algebraische und die geometrische Vielfachheit getrennt betrachten."),
                    TranscriptSegment(start: 58, end: 72, text: "Das ist erfahrungsgemäß die häufigste Fehlerquelle in der Klausur."),
                    TranscriptSegment(start: 72, end: 84, text: "Die Klausur findet übrigens am zwölften Februar statt, Übungsblatt vier bitte bis Freitag."),
                  ],
                  ago: -5_400, length: 5_100, isExported: true, withAudio: true),

            Entry(title: "Betriebssysteme – Scheduling",
                  area: "Betriebssysteme",
                  noteTitle: "Scheduling-Verfahren im Vergleich",
                  markdown: """
                  Round Robin, prioritätsbasiertes Scheduling und der Unterschied zwischen präemptiv und \
                  nicht präemptiv. Zum Schluss ging es um Starvation und wie Aging sie verhindert.

                  ## Verfahren
                  - **Round Robin**: feste Zeitscheibe, fair, aber viele Kontextwechsel
                  - **Prioritäten**: wichtige Prozesse zuerst, Gefahr der Starvation
                  - **Shortest Job First**: kürzeste Wartezeit im Mittel, setzt Vorwissen voraus

                  ## Aufgaben
                  - [ ] Gantt-Diagramme aus der Übung nachrechnen

                  ## Karteikarten
                  - Was ist Starvation? :: Ein Prozess kommt dauerhaft nicht an die CPU, weil immer \
                  höher priorisierte Prozesse bereitstehen.
                  - Was bewirkt Aging? :: Die Priorität wartender Prozesse steigt mit der Wartezeit – \
                  damit kommen auch sie irgendwann dran.
                  - Präemptiv oder nicht? :: Präemptiv heißt, das Betriebssystem kann einem Prozess die \
                  CPU wieder entziehen.
                  """,
                  transcript: [
                    TranscriptSegment(start: 0, end: 9, text: "Wir vergleichen heute drei Scheduling-Verfahren."),
                    TranscriptSegment(start: 9, end: 24, text: "Round Robin arbeitet mit einer festen Zeitscheibe und ist fair, erzeugt aber viele Kontextwechsel."),
                  ],
                  ago: -93_600, length: 5_280),

            Entry(title: "Sprint-Planung",
                  area: "Projektmeeting",
                  noteTitle: "Sprint-Planung Kalenderwoche 39",
                  markdown: """
                  Besprochen wurden der Stand der Anmeldung, die offene Frage zur Datenbankmigration und \
                  die Verteilung der Aufgaben für den kommenden Sprint.

                  ## Beschlüsse
                  - Die Migration wird auf den nächsten Sprint verschoben
                  - Die Anmeldung geht am Donnerstag auf die Testumgebung
                  - Wöchentlicher Jour fixe bleibt dienstags um zehn

                  ## Offene Fragen
                  - Wer übernimmt die Freigabe der Testumgebung während des Urlaubs?

                  ## Aufgaben
                  - [ ] Anmeldung auf die Testumgebung bringen – Lena, bis Donnerstag
                  - [ ] Migrationsplan schreiben – Tim, bis zum nächsten Jour fixe
                  - [ ] Urlaubsvertretung klären – Sarah, diese Woche
                  """,
                  transcript: [
                    TranscriptSegment(start: 0, end: 8, text: "Fangen wir mit dem Stand der Anmeldung an."),
                    TranscriptSegment(start: 8, end: 22, text: "Die Migration schieben wir in den nächsten Sprint, dafür ist diese Woche keine Zeit."),
                  ],
                  ago: -180_000, length: 2_760, sourceApp: "Microsoft Teams"),

            Entry(title: "Lerngruppe – Klausurvorbereitung",
                  area: "Lerngruppe",
                  noteTitle: "Klausurvorbereitung: Aufteilung",
                  markdown: """
                  Wir haben die Altklausuren aufgeteilt und einen Termin für die gemeinsame Besprechung \
                  gefunden.

                  ## Aufteilung
                  - Altklausur 2023: Jonas
                  - Altklausur 2024: ich
                  - Übungsblätter 1–3: Mira

                  ## Aufgaben
                  - [ ] Altklausur 2024 bis Mittwoch rechnen
                  - [ ] Ergebnisse in den geteilten Ordner legen
                  """,
                  ago: -266_400, length: 3_720),

            Entry(title: "Analysis II – Diagonalisierbarkeit",
                  area: "Analysis II",
                  noteTitle: "Diagonalisierbarkeit",
                  markdown: """
                  Fortsetzung zu den Eigenwerten: Wann lässt sich eine Matrix diagonalisieren und was \
                  bringt das beim Rechnen mit Potenzen.

                  ## Kernaussagen
                  - Diagonalisierbar heißt: Es gibt eine Basis aus Eigenvektoren
                  - Dann wird A = S · D · S⁻¹, und A^n ist plötzlich einfach zu berechnen

                  ## Aufgaben
                  - [ ] Beispiel aus der Vorlesung selbst nachrechnen

                  ## Karteikarten
                  - Wozu dient die Diagonalisierung? :: Potenzen und Exponentialfunktionen von Matrizen \
                  lassen sich damit leicht berechnen.
                  """,
                  ago: -612_000, length: 5_040),

            Entry(title: "Analysis II – Überblick über sechs Wochen",
                  area: "Analysis II",
                  noteTitle: "Analysis II – Überblick über sechs Wochen",
                  markdown: """
                  Sechs Vorlesungen, ein roter Faden: von linearen Abbildungen über Eigenwerte bis zur \
                  Diagonalisierbarkeit. Alles baut darauf auf, eine Abbildung in einer Basis zu \
                  beschreiben, in der sie möglichst einfach aussieht.

                  ## Themen der Wochen
                  - Woche 1–2: Lineare Abbildungen und Basiswechsel
                  - Woche 3–4: Determinanten und das charakteristische Polynom
                  - Woche 5–6: Eigenwerte, Eigenräume, Diagonalisierbarkeit

                  ## Roter Faden
                  Die Determinante liefert das charakteristische Polynom, dessen Nullstellen die \
                  Eigenwerte sind – und genügend unabhängige Eigenvektoren machen die Matrix \
                  diagonalisierbar.

                  ## Prüfungshinweise
                  - Mehrfach genannt: doppelte Nullstellen und die beiden Vielfachheiten
                  - Der Dozent betont die Rechenwege, nicht die Beweise

                  ## Offene Aufgaben aus dem Zeitraum
                  - [ ] Übungsblatt 4 bis Freitag rechnen
                  - [ ] Klausurtermin am 12. Februar notieren
                  - [ ] Beispiel zur Diagonalisierung nachrechnen
                  """,
                  ago: -9_000, length: 0, isOverview: true),
        ]
    }

    private static var englishEntries: [Entry] {
        [
            Entry(title: "Linear Algebra – Eigenvalues",
                  area: "Linear Algebra",
                  noteTitle: "Eigenvalues and eigenvectors",
                  markdown: """
                  The lecture covered eigenvalues, how to compute them via the characteristic polynomial, \
                  and why they decide whether a matrix can be diagonalised.

                  ## How to compute them
                  - Set up the characteristic polynomial: det(A − λI) = 0
                  - Find its roots — those are the eigenvalues
                  - Work out the eigenspace for each eigenvalue

                  ## Important for the exam
                  - A matrix is diagonalisable exactly when the geometric multiplicities add up to the dimension
                  - With repeated roots, always check both multiplicities

                  ## Tasks
                  - [ ] Work through problem sheet 4 by Friday
                  - [ ] Note the exam date: 12 February

                  ## Flashcards
                  - What is an eigenvalue? :: The factor by which an eigenvector is stretched by the map.
                  - How do you compute eigenvalues? :: From the roots of the characteristic polynomial det(A − λI) = 0.
                  - When is a matrix diagonalisable? :: When the geometric multiplicities add up to the \
                  dimension of the space.
                  - What is an eigenspace? :: The kernel of (A − λI) — all eigenvectors for one eigenvalue.
                  """,
                  transcript: [
                    TranscriptSegment(start: 0, end: 7, text: "Good morning. Today we talk about eigenvalues and eigenvectors."),
                    TranscriptSegment(start: 7, end: 21, text: "An eigenvalue is the factor by which an eigenvector is stretched by the map."),
                    TranscriptSegment(start: 21, end: 39, text: "You compute it from the characteristic polynomial, the determinant of A minus lambda times the identity."),
                    TranscriptSegment(start: 39, end: 58, text: "Be careful with repeated roots: you have to treat algebraic and geometric multiplicity separately."),
                    TranscriptSegment(start: 58, end: 72, text: "In my experience that is the most common mistake in the exam."),
                    TranscriptSegment(start: 72, end: 84, text: "The exam is on the twelfth of February, and problem sheet four is due Friday."),
                  ],
                  ago: -5_400, length: 5_100, isExported: true, withAudio: true),

            Entry(title: "Operating Systems – Scheduling",
                  area: "Operating Systems",
                  noteTitle: "Scheduling strategies compared",
                  markdown: """
                  Round robin, priority scheduling and the difference between preemptive and \
                  non-preemptive. We finished with starvation and how aging prevents it.

                  ## Strategies
                  - **Round robin**: fixed time slice, fair, but many context switches
                  - **Priorities**: important processes first, risk of starvation
                  - **Shortest job first**: best average waiting time, needs knowledge up front

                  ## Tasks
                  - [ ] Redo the Gantt charts from the exercise

                  ## Flashcards
                  - What is starvation? :: A process never gets the CPU because higher-priority processes \
                  keep arriving.
                  - What does aging do? :: It raises the priority of waiting processes over time, so they \
                  eventually run.
                  - What does preemptive mean? :: The operating system can take the CPU away from a running process.
                  """,
                  transcript: [
                    TranscriptSegment(start: 0, end: 9, text: "Today we compare three scheduling strategies."),
                    TranscriptSegment(start: 9, end: 24, text: "Round robin uses a fixed time slice and is fair, but it creates many context switches."),
                  ],
                  ago: -93_600, length: 5_280),

            Entry(title: "Sprint planning",
                  area: "Project meeting",
                  noteTitle: "Sprint planning, week 39",
                  markdown: """
                  We went through the state of the sign-in flow, the open question about the database \
                  migration and how the work is split for the coming sprint.

                  ## Decisions
                  - The migration moves to the next sprint
                  - Sign-in goes to staging on Thursday
                  - The weekly sync stays on Tuesdays at ten

                  ## Open questions
                  - Who approves staging releases during the holidays?

                  ## Tasks
                  - [ ] Ship sign-in to staging — Lena, by Thursday
                  - [ ] Write the migration plan — Tim, by the next sync
                  - [ ] Sort out holiday cover — Sarah, this week
                  """,
                  transcript: [
                    TranscriptSegment(start: 0, end: 8, text: "Let's start with the state of the sign-in flow."),
                    TranscriptSegment(start: 8, end: 22, text: "We'll push the migration to the next sprint, there is no time for it this week."),
                  ],
                  ago: -180_000, length: 2_760, sourceApp: "Microsoft Teams"),

            Entry(title: "Study group – exam preparation",
                  area: "Study group",
                  noteTitle: "Exam preparation: who does what",
                  markdown: """
                  We split the past exams between us and agreed on a date to go through the results together.

                  ## Split
                  - Past exam 2023: Jonas
                  - Past exam 2024: me
                  - Problem sheets 1–3: Mira

                  ## Tasks
                  - [ ] Work through the 2024 exam by Wednesday
                  - [ ] Put the results in the shared folder
                  """,
                  ago: -266_400, length: 3_720),

            Entry(title: "Linear Algebra – Diagonalisation",
                  area: "Linear Algebra",
                  noteTitle: "Diagonalisation",
                  markdown: """
                  Following on from eigenvalues: when can a matrix be diagonalised, and what does that \
                  buy you when computing powers.

                  ## Key points
                  - Diagonalisable means there is a basis of eigenvectors
                  - Then A = S · D · S⁻¹, and A^n suddenly becomes easy

                  ## Tasks
                  - [ ] Redo the lecture example yourself

                  ## Flashcards
                  - Why diagonalise at all? :: Powers and exponentials of matrices become easy to compute.
                  """,
                  ago: -612_000, length: 5_040),

            Entry(title: "Linear Algebra – six weeks at a glance",
                  area: "Linear Algebra",
                  noteTitle: "Linear Algebra – six weeks at a glance",
                  markdown: """
                  Six lectures, one thread: from linear maps through eigenvalues to diagonalisation. \
                  Everything builds on describing a map in a basis where it looks as simple as possible.

                  ## Week by week
                  - Weeks 1–2: linear maps and change of basis
                  - Weeks 3–4: determinants and the characteristic polynomial
                  - Weeks 5–6: eigenvalues, eigenspaces, diagonalisation

                  ## The thread
                  The determinant gives you the characteristic polynomial, its roots are the eigenvalues — \
                  and enough independent eigenvectors make the matrix diagonalisable.

                  ## Exam hints
                  - Mentioned repeatedly: repeated roots and the two multiplicities
                  - The lecturer stresses the computation, not the proofs

                  ## Open tasks from this period
                  - [ ] Work through problem sheet 4 by Friday
                  - [ ] Note the exam date: 12 February
                  - [ ] Redo the diagonalisation example
                  """,
                  ago: -9_000, length: 0, isOverview: true),
        ]
    }

    // MARK: Wörterbuch

    private static func glossary(english: Bool) -> [GlossaryTerm] {
        english
        ? [GlossaryTerm(term: "Professor Meyer", variants: ["Maier", "Mayer"]),
           GlossaryTerm(term: "eigenvalue", variants: ["eigen value"]),
           GlossaryTerm(term: "round robin", variants: ["round robbin"])]
        : [GlossaryTerm(term: "Professor Meyer", variants: ["Maier", "Mayer"]),
           GlossaryTerm(term: "Eigenwert", variants: ["Eigen Wert"]),
           GlossaryTerm(term: "Round Robin", variants: ["Round Robbin", "Rand Robin"])]
    }
}
#endif
