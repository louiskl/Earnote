import EarnoteCore
import EarnoteML
import Foundation

/// KI-Anbieter, die Mac- oder ML-Code brauchen: eingebautes lokales Modell, Apple Intelligence, Kommandozeilen-Tools.
struct PlatformLLMClients: LLMClientProvider {
    func makeClient(for config: AIConfig) throws -> (any LLMClient)? {
        switch config.provider {
        case .localModel:
            if let reason = LocalModelManager.unsupportedReason { throw LLMError(message: reason) }
            return LocalLLMClient()
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleIntelligenceClient() }
            #endif
            throw LLMError(message: String(localized: "Apple Intelligence benötigt macOS 26 oder neuer."))
        case .claudeCode:
            return CLIClient(tool: .claude, model: config.model)
        case .codex:
            return CLIClient(tool: .codex, model: config.model)
        default:
            return nil
        }
    }
}
