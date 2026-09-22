import XCTest
@testable import EarnoteCore

final class ManagedSettingsTests: XCTestCase {
    func testWithoutProfileNothingChanges() {
        var settings = AppSettings()
        settings.ai.provider = .anthropic
        settings.checkForUpdates = false
        XCTAssertEqual(ManagedSettings().apply(to: settings), settings)
    }

    func testProfileOverridesSwitches() {
        var settings = AppSettings()
        settings.checkForUpdates = true
        settings.syncWithCloud = true
        let managed = ManagedSettings(values: [.checkForUpdates: false, .syncWithCloud: false, .keepAudioFiles: false])
        let result = managed.apply(to: settings)
        XCTAssertFalse(result.checkForUpdates)
        XCTAssertFalse(result.syncWithCloud)
        XCTAssertFalse(result.keepAudioFiles)
        XCTAssertTrue(managed.isLocked(.checkForUpdates))
        XCTAssertFalse(managed.isLocked(.showConsentReminder))
    }

    func testBlockedCloudAIFallsBackToLocal() {
        var settings = AppSettings()
        settings.ai.provider = .openAICompatible
        settings.ai.model = "gpt-x"
        settings.ai.baseURL = "https://example.com/v1"
        let result = ManagedSettings(values: [.allowCloudAI: false]).apply(to: settings)
        XCTAssertFalse(result.ai.provider.sendsDataOffDevice)
        XCTAssertEqual(result.ai.model, "")
        XCTAssertEqual(result.ai.baseURL, "")
    }

    func testLocalProvidersStayWhenCloudAIIsBlocked() {
        let managed = ManagedSettings(values: [.allowCloudAI: false])
        for provider in AIProviderKind.allCases {
            XCTAssertEqual(managed.allows(provider), !provider.sendsDataOffDevice, provider.rawValue)
        }
        var settings = AppSettings()
        settings.ai.provider = .ollama
        settings.ai.model = "qwen3:8b"
        XCTAssertEqual(managed.apply(to: settings), settings)
    }

    func testFactoryRefusesBlockedProvider() {
        let factory = LLMFactory(apiKey: { _ in "key" }, managed: ManagedSettings(values: [.allowCloudAI: false]))
        var config = AIConfig()
        config.provider = .anthropic
        XCTAssertThrowsError(try factory.make(config))
        config.provider = .ollama
        XCTAssertNoThrow(try factory.make(config))
    }

    /// Selbst gesetzte Werte (`defaults write`) sind keine Vorgabe der Organisation
    func testUserValuesAreNotManaged() throws {
        let suite = "app.earnote.tests.managed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ManagedSettings.Key.allowCloudAI.rawValue)
        XCTAssertTrue(ManagedSettings.read(from: defaults).isEmpty)
    }
}
