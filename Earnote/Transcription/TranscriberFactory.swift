import EarnoteCore
import EarnoteML
import Foundation

enum TranscriberFactory {
    @MainActor
    static func make(for settings: AppSettings) throws -> any Transcriber {
        switch settings.transcriptionEngine {
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleSpeechTranscriber() }
            #endif
            throw TranscriptionError.unavailable("Die Apple-Spracherkennung benötigt macOS 26. Bitte Whisper auswählen.")
        case .whisperKit:
            guard let selected = WhisperModelManager.shared.installedFolder(for: settings.whisperModel) else {
                throw TranscriptionError.modelMissing
            }
            return WhisperTranscriber(modelFolder: selected.folder, modelName: selected.model)
        }
    }

    static var appleSpeechAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

/// Transcriber für die Verarbeitung: Whisper oder Apple-Spracherkennung, je nach Einstellung.
struct PlatformTranscribers: TranscriberProvider {
    func makeTranscriber(for settings: AppSettings) async throws -> any Transcriber {
        try await MainActor.run { try TranscriberFactory.make(for: settings) }
    }
}
