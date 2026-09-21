import EarnoteCore
import EarnoteML
import XCTest
@testable import Earnote

/// Die Auswahl der lokalen Modelle: Was empfohlen wird, muss auf den Mac passen –
/// ein Modell, das den Arbeitsspeicher sprengt, macht die Notiz langsamer statt besser.
final class LocalModelCatalogTests: XCTestCase {
    func testRecommendationFitsTheMemoryItIsMeantFor() {
        for memory in [8.0, 16.0, 24.0, 36.0, 64.0] {
            let model = LocalModelCatalog.recommended(memoryGB: memory)
            XCTAssertLessThanOrEqual(model.minMemoryGB, memory,
                                     "\(model.name) wird bei \(Int(memory)) GB empfohlen, braucht aber mehr")
        }
        XCTAssertEqual(LocalModelCatalog.recommended(memoryGB: 8).name, "Qwen3 4B")
        XCTAssertEqual(LocalModelCatalog.recommended(memoryGB: 16).name, "Qwen2.5 7B")
    }

    func testEveryModelIsAFourBitMlxRepositoryWithAPlausibleSize() {
        XCTAssertFalse(LocalModelCatalog.all.isEmpty)
        for model in LocalModelCatalog.all {
            XCTAssertTrue(model.id.hasPrefix("mlx-community/"), "\(model.id) kommt nicht von mlx-community")
            XCTAssertTrue(model.id.contains("4bit"), "\(model.id) ist keine 4-Bit-Fassung")
            // Ein 4-Bit-Modell braucht grob halb so viel Platz wie sein Arbeitsspeicher-Minimum
            XCTAssertLessThan(model.sizeGB, model.minMemoryGB, "\(model.name) passt nicht zu seiner Untergrenze")
            XCTAssertFalse(model.detail.isEmpty)
        }
        XCTAssertEqual(Set(LocalModelCatalog.all.map(\.id)).count, LocalModelCatalog.all.count, "doppelte Kennung")
    }

    /// Ohne eigene Wahl gilt: ein schon geladenes Modell vor der Empfehlung – ein Update soll
    /// niemanden zu einem neuen Download zwingen.
    @MainActor
    func testEmptySettingPrefersAnInstalledModelOverTheRecommendation() {
        let fallback = LocalModelCatalog.all.first { LocalModelManager.isInstalled($0) }
            ?? LocalModelCatalog.recommended()
        var settings = AppSettings()
        XCTAssertEqual(LocalModels.resolved(settings).id, fallback.id)

        settings.ai.localModel = "mlx-community/Qwen3-1.7B-4bit"
        XCTAssertEqual(LocalModels.resolved(settings).name, "Qwen3 1.7B", "die eigene Wahl gilt")

        // Eine Kennung aus einer neueren Version darf nicht dazu führen, dass gar nichts geht
        settings.ai.localModel = "mlx-community/gibt-es-nicht"
        XCTAssertEqual(LocalModels.resolved(settings).id, fallback.id)
    }
}
