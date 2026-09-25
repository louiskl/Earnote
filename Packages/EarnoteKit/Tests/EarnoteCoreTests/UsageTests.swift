import XCTest
@testable import EarnoteCore

final class UsageTests: XCTestCase {
    func testEverySuggestedTemplateExists() {
        let ids = Set(CategoryTemplate.all.map(\.id))
        for usage in Usage.allCases {
            let suggested = CategoryTemplate.suggested(for: usage)
            XCTAssertFalse(suggested.isEmpty)
            XCTAssertTrue(Set(suggested).isSubset(of: ids), "\(usage)")
        }
    }

    func testOldSettingsHaveNoUsage() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"onboardingCompleted": true}"#.utf8))
        XCTAssertNil(old.usage)
        var settings = AppSettings()
        settings.usage = .school
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.usage, .school)
    }
}
