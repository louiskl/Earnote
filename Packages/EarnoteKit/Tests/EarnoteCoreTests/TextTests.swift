import XCTest
@testable import EarnoteCore

final class TranscriptFormattingTests: XCTestCase {
    func testSpeakerChangesStartNewLines() {
        let transcript = Transcript(segments: [
            TranscriptSegment(start: 0, end: 2, text: "Hallo.", speaker: "Ich"),
            TranscriptSegment(start: 3, end: 5, text: " Wie geht's? ", speaker: "Ich"),
            TranscriptSegment(start: 10, end: 12, text: "Gut.", speaker: "Andere"),
            TranscriptSegment(start: 13, end: 14, text: "  ", speaker: "Ich"),
        ], engine: "Test")
        XCTAssertEqual(transcript.formatted(), "[00:00:00] Ich: Hallo. Wie geht's?\n[00:00:10] Andere: Gut.")
        XCTAssertEqual(transcript.formatted(includeSpeakers: false), "[00:00:00] Hallo. Wie geht's? Gut.")
    }

    func testBlocksAreSplitEverySixtySeconds() {
        let transcript = Transcript(segments: [
            TranscriptSegment(start: 0, end: 2, text: "Eins."),
            TranscriptSegment(start: 59, end: 60, text: "Zwei."),
            TranscriptSegment(start: 60, end: 62, text: "Drei."),
            TranscriptSegment(start: 3_725, end: 3_726, text: "Später."),
        ], engine: "Test")
        XCTAssertEqual(transcript.formatted(), "[00:00:00] Eins. Zwei.\n[00:01:00] Drei.\n[01:02:05] Später.")
    }

    func testSplitKeepsLinesAndCutsOverlongOnes() {
        XCTAssertEqual(Summarizer.split("aaa\nbbb\nccc", max: 7), ["aaa\nbbb", "ccc"])
        XCTAssertEqual(Summarizer.split("abcdefghij", max: 4), ["abcd", "efgh", "ij"])
        XCTAssertEqual(Summarizer.split("", max: 4), [])
    }

    func testLengthGuidanceFollowsSpokenWords() {
        XCTAssertTrue(Summarizer.lengthGuidance(words: 100).hasPrefix("Sehr kurz (ca. 100"))
        XCTAssertTrue(Summarizer.lengthGuidance(words: 150).hasPrefix("Kurz"))
        XCTAssertTrue(Summarizer.lengthGuidance(words: 700).hasPrefix("Mittel"))
        XCTAssertTrue(Summarizer.lengthGuidance(words: 3_000).hasPrefix("Lang"))
        XCTAssertTrue(Summarizer.lengthGuidance(words: 12_000).hasPrefix("Sehr lang"))
    }

    func testSpokenWordCountIgnoresTimestampsAndSpeakers() {
        XCTAssertEqual(Summarizer.spokenWordCount("[00:00:00] Ich: Hallo Welt\n[00:01:00] Andere: Ja [genau]"), 3)
    }
}

final class AppSettingsDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testOldSettingsWithoutNewFieldsKeepValuesAndGetDefaults() throws {
        let settings = try decode(#"{"language":"en","keepAudioFiles":false,"destinations":{"enabled":["notion"],"includeTranscript":false,"notionDatabaseID":"x","notionDatabaseURL":"","obsidianVaultPath":"","obsidianFolder":"O","markdownFolderPath":"/m","appleNotesFolder":"A","bearTags":"b","craftSpaceID":""}}"#)
        let defaults = AppSettings()
        XCTAssertEqual(settings.language, "en")
        XCTAssertFalse(settings.keepAudioFiles)
        XCTAssertEqual(settings.destinations.enabled, ["notion"])
        XCTAssertEqual(settings.destinations.markdownFolderPath, "/m")
        XCTAssertEqual(settings.openWindowAtLaunch, defaults.openWindowAtLaunch)
        XCTAssertEqual(settings.meetingDetection, defaults.meetingDetection)
        XCTAssertEqual(settings.transcriptionEngine, .whisperKit)
        XCTAssertEqual(settings.ai, defaults.ai)
        XCTAssertNil(settings.defaultCategoryID)
    }

    func testUnknownProviderFallsBackToDefault() throws {
        let settings = try decode(#"{"ai":{"provider":"somethingNew","model":"m","baseURL":"","summaryLanguage":"Englisch"},"transcriptionEngine":"future"}"#)
        XCTAssertEqual(settings.ai, AIConfig())
        XCTAssertEqual(settings.ai.provider, AIProviderKind.recommended)
        XCTAssertEqual(settings.transcriptionEngine, .whisperKit)
    }

    func testRoundTripKeepsEverything() throws {
        var settings = AppSettings()
        settings.ai.provider = .ollama
        settings.defaultCategoryID = UUID()
        settings.destinations.enabled = ["markdown", "notion"]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }
}

final class TranscriptCleanupTests: XCTestCase {
    private func segments(_ texts: [String], gap: Double = 0) -> [TranscriptSegment] {
        texts.enumerated().map { i, text in
            TranscriptSegment(start: Double(i) * (2 + gap), end: Double(i) * (2 + gap) + 2, text: text)
        }
    }

    func testNormalizedRepeatedSentencesAndAlternatingLoops() {
        let a = "Vielen Dank fürs Zuhören."
        let b = "Das war unsere heutige Zusammenfassung."
        XCTAssertEqual(TranscriptCleanup.removeRepetitions(segments([a, "VIELEN DANK fürs Zuhören!", a])).map(\.text), [a])
        XCTAssertEqual(TranscriptCleanup.removeRepetitions(segments([a, b, a, b, a, b])).map(\.text), [a, b])
    }

    func testRealContentShortAnswersPausesAndSpeakersArePreserved() {
        for texts in [["Ja!", "ja", "Nein", "Ja"], ["...", "!"],
                      ["Wir haben drei Aufgaben.", "Wir haben vier Aufgaben."]] {
            XCTAssertEqual(TranscriptCleanup.removeRepetitions(segments(texts)).map(\.text), texts)
        }
        let texts = ["Vielen Dank fürs Zuhören.", "Vielen Dank fürs Zuhören."]
        XCTAssertEqual(TranscriptCleanup.removeRepetitions(segments(texts, gap: 10)).count, 2)
        var speakers = segments(texts)
        speakers[0].speaker = "Ich"
        speakers[1].speaker = "Andere"
        XCTAssertEqual(TranscriptCleanup.removeRepetitions(speakers).count, 2)
    }
}

final class AudioStoreTests: XCTestCase {
    func testDeletingImportedAudioRemovesFileAndDisablesReprocessing() throws {
        let folder = try TestFolder()
        let audio = folder.audio
        let source = folder.root.appendingPathComponent("vortrag.wav")
        try Data().write(to: source)
        var rec = Recording(title: "vortrag")
        rec.importedFileName = try audio.importAudio(from: source, for: rec.id)
        XCTAssertEqual(rec.importedFileName, "import.wav")
        XCTAssertTrue(audio.hasAudio(rec))

        let dir = audio.folderURL(for: rec.id)
        for name in ["mic.caf", "system.caf", "audio.wav", "notizen.txt"] { try Data().write(to: dir.appendingPathComponent(name)) }
        audio.deleteAudio(for: rec)
        XCTAssertFalse(audio.hasAudio(rec))
        for name in ["mic.caf", "system.caf", "audio.wav", "import.wav"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notizen.txt").path), "Nur Audio wird gelöscht")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Originaldatei bleibt erhalten")

        audio.deleteFolder(for: rec.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}

final class GlossaryTests: XCTestCase {
    func testReplacesWholeWordsOnlyAndIgnoresCase() {
        XCTAssertEqual(TermCorrection.replace("Herr maier und Maier", wrong: "Maier", with: "Meyer"),
                       "Herr Meyer und Meyer")
        XCTAssertEqual(TermCorrection.replace("Maiers Buch", wrong: "Maier", with: "Meyer"), "Maiers Buch")
        XCTAssertEqual(TermCorrection.replace("Siehe § 5 oben", wrong: "§ 5", with: "§ 15"), "Siehe § 15 oben")
        XCTAssertEqual(TermCorrection.replace("A $ B", wrong: "$", with: "€"), "A € B", "Sonderzeichen bleiben Text")
        XCTAssertEqual(TermCorrection.replace("nichts", wrong: "  ", with: "x"), "nichts")
    }

    func testGlossaryForCategoryKeepsGlobalAndOwnTerms() {
        let mine = UUID(), other = UUID()
        let terms = [GlossaryTerm(term: "Global"),
                     GlossaryTerm(term: "Meins", categoryID: mine),
                     GlossaryTerm(term: "Fremd", categoryID: other),
                     GlossaryTerm(term: "   ", categoryID: mine)]
        XCTAssertEqual(Glossary.forCategory(mine, in: terms).map(\.term), ["Global", "Meins"])
        XCTAssertEqual(Glossary.speechHints(Glossary.forCategory(nil, in: terms)), ["Global"])
    }

    func testPromptTextListsVariants() {
        let text = Glossary.promptText([GlossaryTerm(term: "Meyer", variants: ["Maier", "Mayer"]),
                                        GlossaryTerm(term: "Eigenwert")])
        XCTAssertTrue(text.contains("- Meyer (oft falsch erkannt als: Maier, Mayer)"), text)
        XCTAssertTrue(text.contains("- Eigenwert"), text)
        XCTAssertEqual(Glossary.promptText([]), "")
    }
}

final class TranscriptQualityTests: XCTestCase {
    private func segment(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text)
    }

    func testRemovesInventedSubtitleCredits() {
        let segments = [segment("Wir beginnen mit Kapitel drei.", 0, 4),
                        segment("Untertitel im Auftrag des ZDF, 2021", 60, 64),
                        segment("Zurück zum Thema.", 120, 123)]
        let cleaned = TranscriptCleanup.clean(segments)
        XCTAssertEqual(cleaned.map(\.text), ["Wir beginnen mit Kapitel drei.", "Zurück zum Thema."])
    }

    func testKeepsPoliteWordsInConversationButNotInSilence() {
        let inTalk = [segment("Kannst du das schicken?", 0, 2),
                      segment("Vielen Dank!", 2.5, 3.5),
                      segment("Mache ich.", 4, 5)]
        XCTAssertEqual(TranscriptCleanup.clean(inTalk).count, 3, "Mitten im Gespräch ist der Dank echt")

        let inSilence = [segment("Wir sind fertig.", 0, 3),
                         segment("Dankeschön.", 400, 402)]
        XCTAssertEqual(TranscriptCleanup.clean(inSilence).map(\.text), ["Wir sind fertig."],
                       "Allein in einer langen Pause erfindet Whisper die Floskel")
    }

    func testCountsSpokenWordsForTheNoSpeechCheck() {
        XCTAssertEqual(TranscriptCleanup.spokenWords([segment("Hallo Welt", 0, 1)]), 2)
        XCTAssertEqual(TranscriptCleanup.spokenWords([]), 0)
    }

    func testSearchRangesFindEveryHitAcrossUmlautSpellings() {
        let text = "Grüße an Grüsse und gruesse"
        let ranges = SearchText.ranges(in: text, query: "gruesse")
        XCTAssertEqual(ranges.count, 3, "Alle drei Schreibweisen zählen als Treffer")
        XCTAssertEqual(SearchText.ranges(in: text, query: "  ").count, 0)
        XCTAssertEqual(SearchText.ranges(in: "abc", query: "x").count, 0)
    }
}

final class SettingsCompatibilityTests: XCTestCase {
    /// Eine ältere Einstellungsdatei kennt neue Felder nicht – trotzdem darf nichts verloren gehen.
    func testOlderSettingsKeepTheirValues() throws {
        let json = """
            {"onboardingCompleted": true,
             "destinations": {"enabled": ["markdown", "notion"], "notionDatabaseID": "abc"},
             "ai": {"provider": "anthropic", "model": "claude-sonnet-4-5"}}
            """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.destinations.enabled, ["markdown", "notion"])
        XCTAssertEqual(settings.destinations.notionDatabaseID, "abc")
        XCTAssertEqual(settings.destinations.bearTags, DestinationSettings().bearTags, "Fehlendes Feld: Standardwert")
        XCTAssertEqual(settings.ai.provider, .anthropic)
        XCTAssertEqual(settings.ai.summaryLanguage, AIConfig().summaryLanguage)
        XCTAssertTrue(settings.onboardingCompleted)
    }
}

final class DiskSpaceTests: XCTestCase {
    func testWarnsBeforeTheDiskIsFull() {
        XCTAssertEqual(DiskSpace.check(availableBytes: 20 * 1_073_741_824), .fine)
        XCTAssertEqual(DiskSpace.check(availableBytes: nil), .fine, "Unbekannt heißt: nicht im Weg stehen")

        let low = DiskSpace.check(availableBytes: 1_000 * 1_048_576)
        XCTAssertEqual(low, .low(freeMB: 1_000, minutesLeft: 1_000 / DiskSpace.megabytesPerMinute))
        XCTAssertTrue(low.message?.contains("58 Minuten") == true, low.message ?? "-")

        let critical = DiskSpace.check(availableBytes: 100 * 1_048_576)
        XCTAssertEqual(critical, .critical(freeMB: 100))
        XCTAssertTrue(critical.message?.contains("100 MB") == true, critical.message ?? "-")
        XCTAssertNil(DiskSpace.fine.message)
    }
}
