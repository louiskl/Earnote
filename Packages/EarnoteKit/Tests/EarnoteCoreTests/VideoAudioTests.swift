import AVFoundation
import XCTest
@testable import EarnoteCore

final class VideoAudioTests: XCTestCase {
    /// Aus einem Video bleibt nur die Tonspur – gleich lang, ohne Bild
    func testExtractKeepsOnlyAudio() async throws {
        let video = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/lecture", withExtension: "mp4"))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: out) }

        try await VideoAudio.extract(from: video, to: out)

        let asset = AVURLAsset(url: out)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let visual = try await asset.loadTracks(withMediaType: .video)
        let seconds = try await asset.load(.duration).seconds
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(visual.isEmpty)
        XCTAssertEqual(seconds, 2, accuracy: 0.2)
    }
}
