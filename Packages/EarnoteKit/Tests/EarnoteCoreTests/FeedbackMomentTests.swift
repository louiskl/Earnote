import XCTest
@testable import EarnoteCore

final class FeedbackMomentTests: XCTestCase {
    private func next(success: Bool = true, notes: Int = 10, supporter: Bool = false, seen: String? = "1.0",
                      reviewed: String? = "1.0", asked: Date? = nil, asks: Int = 0, declined: Bool = false,
                      whatsNew: String? = nil, pro: Bool = false, proAsked: Date? = nil,
                      proAsks: Int = 0) -> FeedbackMoment? {
        FeedbackMoment.next(afterSuccess: success, version: "1.0", whatsNewVersion: whatsNew, finishedNotes: notes,
                            isSupporter: supporter, lastSeenVersion: seen, reviewAskedVersion: reviewed,
                            supporterAskedAt: asked, supporterAsks: asks, supporterDeclined: declined,
                            proHintAvailable: pro, proHintAskedAt: proAsked, proHintAsks: proAsks,
                            now: Date(timeIntervalSince1970: 100 * 24 * 3600))
    }

    func testAppStartShowsOnlyWhatsNewOncePerVersion() {
        XCTAssertEqual(next(success: false, seen: "0.9", whatsNew: "1.0"), .whatsNew)
        XCTAssertNil(next(success: false, seen: "1.0", whatsNew: "1.0"))
        XCTAssertNil(next(success: false, seen: "0.9", whatsNew: "0.9"))
        // Beim Start nie Bewertung oder Dankeschön-Paket, auch wenn beides fällig wäre
        XCTAssertNil(next(success: false, reviewed: nil))
        XCTAssertNil(next(success: false))
    }

    func testSuccessNeverShowsWhatsNew() {
        XCTAssertNotEqual(next(seen: "0.9", whatsNew: "1.0"), .whatsNew)
    }

    func testReviewAfterThreeNotesOncePerVersion() {
        XCTAssertNil(next(notes: 2, reviewed: nil))
        XCTAssertEqual(next(notes: 3, reviewed: nil), .review)
        XCTAssertEqual(next(notes: 3, reviewed: "0.9"), .review)
        XCTAssertNil(next(notes: 3, reviewed: "1.0"))
    }

    func testSupporterMonthlyAndNeverForSupporters() {
        XCTAssertEqual(next(), .supporter)
        XCTAssertNil(next(supporter: true))
        XCTAssertNil(next(notes: 4))
        XCTAssertNil(next(asked: Date(timeIntervalSince1970: 90 * 24 * 3600)))
        XCTAssertEqual(next(asked: Date(timeIntervalSince1970: 60 * 24 * 3600)), .supporter)
    }

    func testSupporterStopsAfterThreeAsksOrWhenDeclined() {
        XCTAssertEqual(next(asks: 2), .supporter)
        XCTAssertNil(next(asks: 3))
        XCTAssertNil(next(declined: true))
    }

    func testProHintAfterSecondNoteEveryTwoWeeksAtMostFourTimes() {
        let day: TimeInterval = 24 * 3600
        XCTAssertNil(next(notes: 1, pro: true))
        XCTAssertEqual(next(notes: 2, pro: true), .proHint)
        // Bewertung geht vor, ohne passende Funktion kein Hinweis
        XCTAssertEqual(next(reviewed: nil, pro: true), .review)
        XCTAssertNotEqual(next(pro: false), .proHint)
        XCTAssertNotEqual(next(pro: true, proAsked: Date(timeIntervalSince1970: 90 * day)), .proHint)
        XCTAssertEqual(next(pro: true, proAsked: Date(timeIntervalSince1970: 86 * day)), .proHint)
        XCTAssertNotEqual(next(pro: true, proAsks: 4), .proHint)
    }

    func testNoSupporterRightAfterProHint() {
        let day: TimeInterval = 24 * 3600
        XCTAssertNil(next(proAsked: Date(timeIntervalSince1970: 95 * day)))
        XCTAssertEqual(next(proAsked: Date(timeIntervalSince1970: 80 * day)), .supporter)
    }

    func testProSuggestionFitsTheRecording() {
        XCTAssertEqual(ProSuggestion.candidates(spokenLanguage: "en", readerLanguage: "de", isConversation: false,
                                                speakerCount: 0, hasMarks: false), [.translate, .examRadar, .chat])
        XCTAssertEqual(ProSuggestion.candidates(spokenLanguage: "de-DE", readerLanguage: "de", isConversation: true,
                                                speakerCount: 0, hasMarks: false), [.speakers, .chat])
        XCTAssertEqual(ProSuggestion.candidates(spokenLanguage: "de", readerLanguage: "de", isConversation: true,
                                                speakerCount: 3, hasMarks: false), [.chat])
        XCTAssertEqual(ProSuggestion.candidates(spokenLanguage: "de", readerLanguage: "de", isConversation: false,
                                                speakerCount: 0, hasMarks: true), [.chat])
    }
}
