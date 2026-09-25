import EarnoteCore
import FluidAudio
import Foundation

/// Sprechererkennung auf dem Gerät mit FluidAudio (pyannote-Segmentierung + WeSpeaker + VBx, Core ML).
/// Die Modelle (einige MB) lädt FluidAudio beim ersten Mal von Hugging Face und legt sie in den Cache; die Aufnahme
/// liest es stückweise von der Platte, so passt auch eine Vorlesung von zwei Stunden in den Speicher eines iPhones.
public struct FluidSpeakerDiarizer: SpeakerDiarizer {
    public init() {}

    public func diarize(_ audio: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerTurn]? {
        // Je Durchgang neu: Der Manager ist nicht Sendable; die Modelle kommen danach aus dem Cache
        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        let result = try await manager.process(audio) { done, total in
            progress(Double(done) / Double(max(total, 1)))
        }
        return result.segments.map {
            SpeakerTurn(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), speaker: $0.speakerId)
        }
    }
}
