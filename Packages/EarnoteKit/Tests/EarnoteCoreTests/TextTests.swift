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
