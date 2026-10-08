import AVFoundation

/// Vorlesungsvideos (Moodle, ILIAS, Bildschirmaufnahmen): Für Transkript und Notiz zählt nur der Ton.
/// Statt des ganzen Videos (90 Minuten ≈ 1 GB) bleibt eine AAC-Tonspur (≈ 50 MB) in der Aufnahme.
public enum VideoAudio {
    public static func extract(from video: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: video)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: .m4a)
    }
}
