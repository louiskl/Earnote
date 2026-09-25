import XCTest
@testable import EarnoteCore

final class FeedbackMomentTests: XCTestCase {
    private func next(notes: Int = 10, supporter: Bool = false, seen: String? = "1.0", reviewed: String? = "1.0",
                      asked: Date? = nil, whatsNew: String? = nil) -> FeedbackMoment? {
        FeedbackMoment.next(version: "1.0", whatsNewVersion: whatsNew, finishedNotes: notes, isSupporter: supporter,
                            lastSeenVersion: seen, reviewAskedVersion: reviewed, supporterAskedAt: asked,
                            now: Date(timeIntervalSince1970: 100 * 24 * 3600))
    }

    func testWhatsNewOnlyOncePerVersion() {
        XCTAssertEqual(next(seen: "0.9", whatsNew: "1.0"), .whatsNew)
        XCTAssertNotEqual(next(seen: "1.0", whatsNew: "1.0"), .whatsNew)
        XCTAssertNotEqual(next(seen: "0.9", whatsNew: "0.9"), .whatsNew)
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
}
