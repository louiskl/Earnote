import EarnoteCore
import EarnoteML

/// Verbindet die Einstellung „lokales Modell“ mit der Verwaltung in EarnoteML.
/// Leere Einstellung heißt: das Modell, das zu diesem Mac passt.
@MainActor
enum LocalModels {
    static func resolved(_ settings: AppSettings) -> LocalModelInfo {
        if let chosen = LocalModelCatalog.model(settings.ai.localModel) { return chosen }
        // Ein schon geladenes Modell gewinnt: Ein Update darf niemanden zu einem neuen Download zwingen,
        // auch wenn der Mac inzwischen ein größeres tragen würde.
        if let installed = LocalModelCatalog.all.first(where: { LocalModelManager.isInstalled($0) }) { return installed }
        return LocalModelCatalog.recommended()
    }

    static func apply(_ settings: AppSettings) {
        LocalModelManager.shared.selected = resolved(settings)
    }
}
