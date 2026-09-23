import XCTest
@testable import EarnoteCore

final class SummarizerTests: XCTestCase {
    private let context = SummaryContext(category: nil, titleHint: "", sourceApp: nil, date: Date(timeIntervalSince1970: 0),
                                         duration: 600, hasSpeakers: false, language: "Deutsch")

    private func summarize(_ transcript: String, chunk: Int, client: FakeLLMClient) async throws -> Summary {
        try await Summarizer(client: client, chunkCharacters: chunk, providerName: "Fake")
            .summarize(transcript: transcript, context: context) { _ in }
    }

    private func transcript(lines: Int, length: Int = 400) -> String {
        (0..<lines).map { "[00:\(String(format: "%02d", $0)):00] " + String(repeating: "wort ", count: length / 5) }
            .joined(separator: "\n")
    }

    func testShortTranscriptNeedsOneCall() async throws {
        let client = FakeLLMClient(answer: "# Kurzer Titel\n\nAlles besprochen.")
        let summary = try await summarize("[00:00:00] Hallo zusammen", chunk: 10_000, client: client)
        XCTAssertEqual(client.calls.get().count, 1)
        XCTAssertEqual(summary.title, "Kurzer Titel")
        XCTAssertEqual(summary.provider, "Fake")
        XCTAssertTrue(client.calls.get()[0].prompt.contains("Transkript:"))
    }

    func testLongTranscriptIsCondensedInSections() async throws {
        let client = FakeLLMClient { call, _ in
            FakeLLMClient.isCondense(call) ? "Kurze Notiz." : "# Lang\n\nZusammenfassung."
        }
        let summary = try await summarize(transcript(lines: 6), chunk: 1_000, client: client)
        let calls = client.calls.get()
        let condense = calls.filter(FakeLLMClient.isCondense)
        XCTAssertGreaterThan(condense.count, 1, "Mehrere Abschnitte verdichtet")
        XCTAssertTrue(condense.first?.prompt.hasPrefix("Teil 1 von \(condense.count):") == true)
        XCTAssertFalse(FakeLLMClient.isCondense(calls.last!), "Zum Schluss die eigentlichen Notizen")
        XCTAssertTrue(calls.last!.prompt.contains("bereits verdichtete Notizen"))
        XCTAssertEqual(summary.title, "Lang")
    }

    func testContextWindowExceededHalvesSections() async throws {
        let client = FakeLLMClient { call, _ in
            if FakeLLMClient.isCondense(call) { return "Notiz." }
            // Das ganze Transkript passt nicht, verdichtete Notizen schon
            if call.prompt.contains("Transkript:") { throw ContextWindowExceeded() }
            return "# Geschafft\n\nText."
        }
        let text = transcript(lines: 4)
        let summary = try await summarize(text, chunk: text.count + 10, client: client)
        let calls = client.calls.get()
        XCTAssertFalse(FakeLLMClient.isCondense(calls[0]), "Erst am Stück versucht")
        let condense = calls.filter(FakeLLMClient.isCondense)
        XCTAssertEqual(condense.count, 2, "Danach mit halber Abschnittsgröße verdichtet")
        XCTAssertEqual(summary.title, "Geschafft")
    }

    func testChunkTooLargeForContextIsSplitInHalves() async throws {
        let client = FakeLLMClient { call, _ in
            if FakeLLMClient.isCondense(call) {
                if call.prompt.count > 1_200 { throw ContextWindowExceeded() }
                return "Notiz."
            }
            return "# Titel\n\nText."
        }
        _ = try await summarize(transcript(lines: 1, length: 2_000), chunk: 2_000, client: client)
        let condense = client.calls.get().filter(FakeLLMClient.isCondense)
        XCTAssertTrue(condense.contains { $0.prompt.count > 1_200 }, "Zuerst der ganze Abschnitt")
        XCTAssertGreaterThanOrEqual(condense.filter { $0.prompt.count <= 1_200 }.count, 2, "Danach die Hälften")
    }

    /// Echte Ausgabe von Qwen3 4B zu einem englischen Meeting: „Team“ und Uhrzeiten, die nie fielen
    func testTaskCheckDropsInventedAssigneesAndDeadlines() {
        let transcript = "[00:00:24] Same for here, the unit tests from you, Heiko. Susanne's team has to fix the API. Ready by Monday, version 135."
        let note = """
        ## Aufgaben
        - [ ] Heiko: Unit-Test auf Android 9 überprüfen – bis 17:00
        - [ ] Team: Aktualisierung der Pull-Requests – bis 08:00
        - [ ] Professor Meyer: Rotation testen
        - [ ] **Maria**: Übersetzungen prüfen (bis Montag)
        - [ ] Version 135 fertigstellen – bis 135
        - [ ] Heiko: Filter prüfen. Frist: bis 00:00 Uhr.
        Ein Satz mit Doppelpunkt: bleibt, wie er ist.
        """
        XCTAssertEqual(TaskCheck.clean(note, transcript: transcript), """
        ## Aufgaben
        - [ ] Heiko: Unit-Test auf Android 9 überprüfen
        - [ ] Aktualisierung der Pull-Requests
        - [ ] Rotation testen
        - [ ] Übersetzungen prüfen (bis Montag)
        - [ ] Version 135 fertigstellen – bis 135
        - [ ] Heiko: Filter prüfen.
        Ein Satz mit Doppelpunkt: bleibt, wie er ist.
        """)
    }

    func testParseTitleCodeFenceAndTasks() {
        let raw = "```markdown\n# Planung Q3\n\nKurzfassung.\n\n## Aufgaben\n- [ ] Anna: Budget\n  - [ ] Tom: Folien\n- [x] erledigt\n```"
        let summary = Summary.parse(raw, provider: "P", fallbackTitle: "Ersatz")
        XCTAssertEqual(summary.title, "Planung Q3")
        XCTAssertFalse(summary.markdown.contains("```"))
        XCTAssertTrue(summary.markdown.hasPrefix("Kurzfassung."))
        XCTAssertEqual(summary.taskCount, 2)
        XCTAssertEqual(summary.preview, "Kurzfassung.")

        let doubled = Summary.parse("# T\n\n## Aufgaben\n- - [ ] Anna: Budget", provider: "P", fallbackTitle: "Ersatz")
        XCTAssertEqual(doubled.markdown, "## Aufgaben\n- [ ] Anna: Budget")
        XCTAssertEqual(doubled.taskCount, 1)

        let untitled = Summary.parse("Nur Text ohne Überschrift.", provider: "P", fallbackTitle: "Ersatz")
        XCTAssertEqual(untitled.title, "Ersatz")
        XCTAssertEqual(untitled.taskCount, 0)
    }

    func testNotesDraftRemovesDuplicates() {
        let draft = NotesDraft(title: "- Titel", summary: "Kurz.",
                               topics: [.init(heading: "Budget", points: ["- Mehr Geld", "mehr geld"]),
                                        .init(heading: "Fazit", points: ["Wiederholung"])],
                               decisions: ["Mehr Geld"], tasks: ["[ ] Anna schreibt", "Anna schreibt"], openQuestions: [])
        let summary = draft.summary(provider: "P", fallbackTitle: "Ersatz", showTopics: true)
        XCTAssertEqual(summary.title, "Titel")
        XCTAssertEqual(summary.taskCount, 1)
        XCTAssertEqual(summary.markdown.components(separatedBy: "Mehr Geld").count - 1, 1, "Jede Aussage nur einmal")
        XCTAssertFalse(summary.markdown.contains("## Fazit"), "Rückblick-Abschnitte entfallen")
        XCTAssertTrue(summary.markdown.contains("## Entscheidungen\n- Mehr Geld"))
        XCTAssertFalse(summary.markdown.contains("## Budget"), "Thema ohne neue Aussagen entfällt")
        XCTAssertTrue(summary.markdown.contains("- [ ] Anna schreibt"))
    }

    func testPassiveRecordingHasNoTasksOrDecisions() {
        let draft = NotesDraft(kind: NotesDraft.passiveKind, title: "Vortrag", summary: "Ein Vortrag.",
                               topics: [.init(heading: "Inhalt", points: ["Punkt"])],
                               decisions: ["Etwas entschieden"], tasks: ["Etwas tun"], openQuestions: [])
        let summary = draft.summary(provider: "P", fallbackTitle: "Ersatz", showTopics: true)
        XCTAssertEqual(summary.taskCount, 0)
        XCTAssertFalse(summary.markdown.contains("Aufgaben"))
        XCTAssertFalse(summary.markdown.contains("Entscheidungen"))
    }
}

final class NoteCheckTests: XCTestCase {
    /// Eine Frage bleibt nur, wenn sie im Transkript gestellt wurde; ausgedachte fallen weg.
    func testQuestionCheckKeepsOnlyAskedQuestions() {
        let transcript = "[00:01:00] Wer übernimmt die Folien für Freitag? Anna macht das. Dann zur Sicherheit von Speichern."
        let note = "Kurzfassung über Folien und Speicher.\n\n## Offene Fragen\n- Wer übernimmt die Folien?\n"
            + "- Wie kann die IT-Sicherheit weiter verbessert werden?\n\n## Aufgaben\n- [ ] Anna: Folien"
        XCTAssertEqual(QuestionCheck.clean(note, transcript: transcript),
                       "Kurzfassung über Folien und Speicher.\n\n## Offene Fragen\n- Wer übernimmt die Folien?\n\n## Aufgaben\n- [ ] Anna: Folien")

        // Keine einzige Frage im Transkript: Der Abschnitt entfällt ganz
        XCTAssertEqual(QuestionCheck.clean("Kurzfassung.\n\n## Offene Fragen\n- Was folgt daraus?", transcript: "Heute nur Folien."),
                       "Kurzfassung.")
    }

    /// Übersetzte Notiz (englisches Meeting, deutsche Notiz): Wort für Wort nicht prüfbar, Fragen bleiben
    func testQuestionCheckKeepsQuestionsOfTranslatedNotes() {
        let note = "Das Team plant die Veröffentlichung.\n\n## Offene Fragen\n- Gibt es eine Schnittstelle für Durchschnittswerte?"
        XCTAssertEqual(QuestionCheck.clean(note, transcript: "Do we get the average from the backend? I don't know."), note)
    }

    /// Echte Ausgabe zu einer Vorlesung: Aufgaben aus dem Stoff erfunden, dazu leere und doppelte Abschnitte.
    func testTaskCheckDropsTasksNobodyAskedFor() {
        let transcript = "SATA schafft 540 Megabyte, NVMe über PCI Express bis 7000. "
            + "Bis nächste Woche rechnet ihr bitte das Übungsblatt zur Speicherbandbreite. Die MMU prüft jeden Zugriff."
        let note = """
        SATA schafft 540 Megabyte, NVMe über PCI Express deutlich mehr. Die MMU prüft jeden Zugriff.

        ## Entscheidungen
        - Die MMU bleibt als Grundlage für moderne Systeme relevant.

        ## Aufgaben
        - [ ] Vergleich der Leistung von SATA- und NVMe-SSDs in realen Anwendungsszenarien

        ## Aufgaben
        - [ ] Übungsblatt zur Speicherbandbreite rechnen
        """
        XCTAssertEqual(TaskCheck.clean(note, transcript: transcript), """
        SATA schafft 540 Megabyte, NVMe über PCI Express deutlich mehr. Die MMU prüft jeden Zugriff.

        ## Aufgaben
        - [ ] Übungsblatt zur Speicherbandbreite rechnen
        """)
    }

    func testLengthTargetGrowsWithTranscriptButIsCapped() {
        XCTAssertEqual(Summarizer.target(900), 150)
        XCTAssertEqual(Summarizer.target(4_800), 800)
        XCTAssertEqual(Summarizer.target(20_000), 1_200)
    }

    /// Whisper schreibt bei Stille seinen Wörterbuch-Hinweis ab – das gehört nicht ins Transkript.
    func testRemovesSegmentsThatOnlyEchoTheGlossary() {
        let segments = [TranscriptSegment(start: 0, end: 8, text: "Eigenwert, Professor Meyer."),
                        TranscriptSegment(start: 10, end: 11.5, text: "Professor Meyer?"),
                        TranscriptSegment(start: 12, end: 15, text: "Die Eigenwerte berechnen wir jetzt."),
                        TranscriptSegment(start: 20, end: 30, text: "Eigenwert.")]
        XCTAssertEqual(TranscriptCleanup.clean(segments, hints: ["Eigenwert", "Professor Meyer"]).map(\.text),
                       ["Professor Meyer?", "Die Eigenwerte berechnen wir jetzt."])
        XCTAssertEqual(TranscriptCleanup.clean(segments).count, 4, "ohne Wörterbuch bleibt alles")
    }

    /// Die Notiz ist schon beim Schreiben sichtbar: Zwischenstände des letzten Schritts gehen an `draft`.
    func testFinalStepReportsDrafts() async throws {
        let client = StreamingFake(parts: ["# Titel\n\nErster", "# Titel\n\nErster Satz. Zweiter Satz."])
        let drafts = Locked<[String]>([])
        let summary = try await Summarizer(client: client, chunkCharacters: 60_000, providerName: "P")
            .summarize(transcript: "[00:00:01] Erster Satz. Zweiter Satz.",
                       context: SummaryContext(category: nil, titleHint: "", sourceApp: nil, date: Date(), duration: 60,
                                               hasSpeakers: false, language: "Deutsch"),
                       draft: { text in drafts.mutate { $0.append(text) } }) { _ in }
        XCTAssertEqual(drafts.get(), ["# Titel\n\nErster", "# Titel\n\nErster Satz. Zweiter Satz."])
        XCTAssertEqual(summary.markdown, "Erster Satz. Zweiter Satz.")
    }
}

private struct StreamingFake: LLMClient {
    let parts: [String]
    func complete(system: String, prompt: String) async throws -> String { parts.last ?? "" }
    func complete(system: String, prompt: String, partial: @escaping @Sendable (String) -> Void) async throws -> String {
        parts.forEach(partial)
        return parts.last ?? ""
    }
}

final class DecisionCheckTests: XCTestCase {
    func testKeepsDecisionsThatWereMade() {
        let transcript = "Die Migration verschieben wir auf den nächsten Sprint. Die Tests laufen auf Android neun instabil."
        let note = "Die Migration der Schnittstelle und instabile Tests auf Android.\n\n## Entscheidungen\n"
            + "- Die Migration wird auf den nächsten Sprint verschoben.\n- Android neun bleibt die wichtigste Plattform."
        XCTAssertEqual(TaskCheck.clean(note, transcript: transcript),
                       "Die Migration der Schnittstelle und instabile Tests auf Android.\n\n## Entscheidungen\n"
                       + "- Die Migration wird auf den nächsten Sprint verschoben.")
    }
}
