import XCTest
@testable import EarnoteCore

final class CategoryColorTests: XCTestCase {
    func testHexRoundTrip() {
        let color = ColorRGB(hex: "#4F7CFF")
        XCTAssertEqual(color?.hex, "#4F7CFF")
        XCTAssertNil(ColorRGB(hex: "#12345"))
        XCTAssertNotNil(ColorRGB(hex: "4F7CFF"))
    }

    func testVeryDarkColorIsLightenedForDarkMode() throws {
        let dark = try XCTUnwrap(ColorRGB(hex: "#101014"))
        let adjusted = CategoryColor.readable(dark, dark: true)
        XCTAssertGreaterThanOrEqual(adjusted.luminance, CategoryColor.darkModeRange.lowerBound - 0.01)
    }

    func testVeryLightColorIsDarkenedForLightMode() throws {
        let light = try XCTUnwrap(ColorRGB(hex: "#FFF6C0"))
        let adjusted = CategoryColor.readable(light, dark: false)
        XCTAssertLessThanOrEqual(adjusted.luminance, CategoryColor.lightModeRange.upperBound + 0.01)
    }

    func testColorInRangeStaysUntouched() throws {
        let blue = try XCTUnwrap(ColorRGB(hex: "#4F7CFF"))
        XCTAssertEqual(CategoryColor.readable(blue, dark: false), blue)
    }

    func testHueIsKeptRoughly() throws {
        let green = try XCTUnwrap(ColorRGB(hex: "#062B10"))
        let adjusted = CategoryColor.readable(green, dark: true)
        XCTAssertGreaterThan(adjusted.green, adjusted.red)
        XCTAssertGreaterThan(adjusted.green, adjusted.blue)
    }
}

final class TextShorteningTests: XCTestCase {
    func testShortTextStaysAsItIs() {
        XCTAssertEqual(TextShortening.middleTruncated("Vorlesung", max: 20), "Vorlesung")
    }

    func testLongTextIsShortenedInTheMiddle() {
        let result = TextShortening.middleTruncated("Seminar für angewandte Wahrscheinlichkeitsrechnung", max: 20)
        XCTAssertEqual(result.count, 20)
        XCTAssertTrue(result.contains("…"))
        XCTAssertTrue(result.hasPrefix("Seminar"))
        XCTAssertTrue(result.hasSuffix("nung"))
    }
}

final class LevelBufferTests: XCTestCase {
    func testNewValuesArriveOnTheRight() {
        var buffer = LevelBuffer(capacity: 4)
        buffer.append(0.5)
        buffer.append(1)
        XCTAssertEqual(buffer.values, [0, 0, 0.5, 1])
        XCTAssertEqual(buffer.values.count, 4)
    }

    func testValuesAreClampedAndResetWorks() {
        var buffer = LevelBuffer(capacity: 3)
        buffer.append(5)
        buffer.append(-2)
        XCTAssertEqual(buffer.values, [0, 1, 0])
        buffer.reset()
        XCTAssertEqual(buffer.values, [0, 0, 0])
    }

    func testLoudnessDescription() {
        var buffer = LevelBuffer(capacity: 10)
        XCTAssertEqual(buffer.loudnessDescription, "still")
        for _ in 0..<10 { buffer.append(0.8) }
        XCTAssertEqual(buffer.loudnessDescription, "laut")
    }
}
