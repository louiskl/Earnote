#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct AppleIntelligenceClient: LLMClient {
    static var availabilityText: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "Dieser Mac unterstützt Apple Intelligence nicht."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence ist in den Systemeinstellungen nicht aktiviert."
            case .modelNotReady: return "Das Apple-Modell wird noch geladen. Bitte später erneut versuchen."
            @unknown default: return "Apple Intelligence ist nicht verfügbar."
            }
        }
    }

    func complete(system: String, prompt: String) async throws -> String {
        if let problem = Self.availabilityText { throw LLMError(message: problem) }
        let session = LanguageModelSession(instructions: system)
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif
