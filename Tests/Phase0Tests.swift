import EarnoteCore
import EarnoteML
import XCTest
@testable import Earnote

final class Phase0Tests: XCTestCase {
    private func fixture(_ body: (URL, UserDefaults) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "app.earnote.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try body(root, defaults)
    }

    private func run(_ root: URL, _ defaults: UserDefaults, old: [String: Any] = [:],
                     secrets: Bool = true, logs: inout [String]) {
        LegacyMigration.run(defaults: defaults, legacyValues: old, supportBase: root,
                            documents: root.appendingPathComponent("Documents"),
                            migrateSecrets: { _ in secrets }, log: { logs.append($0) })
    }

    func testMigrationMovesDataAndRewritesOnlyInternalPaths() throws {
        try fixture { root, defaults in
            let old = root.appendingPathComponent(AppInfo.legacySupportFolderName)
            let new = root.appendingPathComponent(AppInfo.supportFolderName)
            let model = old.appendingPathComponent("Models/llm/model")
            try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
            try Data("model".utf8).write(to: model.appendingPathComponent("weights"))
            try Data().write(to: model.appendingPathComponent(".earmark-complete")) // Legacy-Migrationsfixture
            try Data("log".utf8).write(to: old.appendingPathComponent("earmark.log")) // Legacy-Migrationsfixture
            let inode = try FileManager.default.attributesOfItem(atPath: model.path)[.systemFileNumber] as? NSNumber
            let settings: [String: Any] = ["destinations": ["markdownFolderPath": old.path + "/Exports",
                "obsidianVaultPath": "/tmp/external-vault", "obsidianFolder": AppInfo.legacySupportFolderName],
                "unknownFutureField": "preserved"]
            var logs: [String] = []
            run(root, defaults, old: ["settings": try JSONSerialization.data(withJSONObject: settings),
                "categories": Data("unchanged".utf8), "whisper.installed": ["base": model.path],
                "systemAudioRequested": true], logs: &logs)
            XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
            let moved = new.appendingPathComponent("Models/llm/model")
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: moved.path)[.systemFileNumber] as? NSNumber, inode)
            XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent(".complete").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent(AppInfo.logFileName).path))
            XCTAssertEqual(defaults.dictionary(forKey: "whisper.installed")?["base"] as? String, moved.path)
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "settings"))) as? [String: Any])
            let destinations = try XCTUnwrap(decoded["destinations"] as? [String: String])
            XCTAssertEqual(destinations["markdownFolderPath"], new.path + "/Exports")
            XCTAssertEqual(destinations["obsidianVaultPath"], "/tmp/external-vault")
            XCTAssertEqual(destinations["obsidianFolder"], AppInfo.legacySupportFolderName)
            XCTAssertEqual(decoded["unknownFutureField"] as? String, "preserved")
            XCTAssertEqual(defaults.data(forKey: "categories"), Data("unchanged".utf8))
            XCTAssertFalse(defaults.bool(forKey: "systemAudioRequested"))
            XCTAssertEqual(defaults.integer(forKey: "legacyMigrationVersion"), 1)
            run(root, defaults, logs: &logs)
            XCTAssertEqual(logs.count, 1, "Zweiter Lauf darf nichts mehr migrieren/protokollieren")
        }
    }

    func testConflictingFoldersAndNewPreferencesRemainUntouched() throws {
        try fixture { root, defaults in
            let old = root.appendingPathComponent(AppInfo.legacySupportFolderName)
            let new = root.appendingPathComponent(AppInfo.supportFolderName)
            for folder in [old, new] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            try Data("old".utf8).write(to: old.appendingPathComponent("data"))
            try Data("new".utf8).write(to: new.appendingPathComponent("data"))
            defaults.set(Data("new categories".utf8), forKey: "categories")
            defaults.set(true, forKey: "systemAudioRequested")
            var logs: [String] = []
            run(root, defaults, old: ["categories": Data(), "whisper.installed": ["base": old.path + "/model"],
                                     "systemAudioRequested": false], logs: &logs)
            XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("data")), Data("new".utf8))
            XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("data")), Data("old".utf8))
            XCTAssertEqual(defaults.dictionary(forKey: "whisper.installed")?["base"] as? String, old.path + "/model")
            XCTAssertEqual(defaults.data(forKey: "categories"), Data("new categories".utf8))
            XCTAssertTrue(defaults.bool(forKey: "systemAudioRequested"))
            XCTAssertTrue(logs.first?.contains("beide Ordner vorhanden") == true)
        }
    }

    func testFreshInstallCreatesNoFolders() throws {
        try fixture { root, defaults in
            var logs: [String] = []
            run(root, defaults, logs: &logs)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
            XCTAssertNil(defaults.data(forKey: "settings"))
            XCTAssertEqual(defaults.integer(forKey: "legacyMigrationVersion"), 1)
        }
    }

    func testPartialFailureRetriesWithoutOverwritingNewValues() throws {
        try fixture { root, defaults in
            let old = root.appendingPathComponent(AppInfo.legacySupportFolderName)
            try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
            var logs: [String] = []
            run(root, defaults, old: ["categories": Data("old".utf8)], secrets: false, logs: &logs)
            XCTAssertEqual(defaults.integer(forKey: "legacyMigrationVersion"), 0)
            defaults.set(Data("edited".utf8), forKey: "categories")
            run(root, defaults, old: ["categories": Data("old".utf8)], logs: &logs)
            XCTAssertEqual(defaults.integer(forKey: "legacyMigrationVersion"), 1)
            XCTAssertEqual(defaults.data(forKey: "categories"), Data("edited".utf8))
            XCTAssertEqual(logs.count, 2)
        }
    }

    func testFailedMoveKeepsPathsAndCanRetry() throws {
        try fixture { root, defaults in
            let old = root.appendingPathComponent(AppInfo.legacySupportFolderName)
            let new = root.appendingPathComponent(AppInfo.supportFolderName)
            try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
            var logs: [String] = []
            run(root, defaults, old: ["whisper.installed": ["base": old.path + "/model"]], logs: &logs)
            XCTAssertEqual(defaults.integer(forKey: "legacyMigrationVersion"), 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
            XCTAssertEqual(Storage.supportRoot(in: root, defaults: defaults).path, old.path)
            XCTAssertEqual(defaults.dictionary(forKey: "whisper.installed")?["base"] as? String, old.path + "/model")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            run(root, defaults, logs: &logs)
            XCTAssertEqual(defaults.integer(forKey: "legacyMigrationVersion"), 1)
            XCTAssertEqual(defaults.dictionary(forKey: "whisper.installed")?["base"] as? String, new.path + "/model")
            XCTAssertEqual(Storage.supportRoot(in: root, defaults: defaults).path, new.path)
        }
    }

    func testLegacyMarkdownDestinationIsPreserved() throws {
        try fixture { root, defaults in
            let legacy = root.appendingPathComponent("Documents").appendingPathComponent(AppInfo.legacySupportFolderName)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            var logs: [String] = []
            run(root, defaults, old: ["settings": try JSONSerialization.data(withJSONObject:
                ["destinations": ["markdownFolderPath": ""]])], logs: &logs)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "settings"))) as? [String: Any])
            XCTAssertEqual((json["destinations"] as? [String: String])?["markdownFolderPath"], legacy.path)
        }
    }

    @MainActor
    func testFallbackReportsActuallyUsedModel() throws {
        let manager = WhisperModelManager.shared
        guard let expected = manager.installed.keys.sorted().first else { throw XCTSkip("Kein Modell installiert") }
        let selected = try XCTUnwrap(manager.installedFolder(for: "missing-phase0-test-model"))
        XCTAssertEqual(selected.model, expected)
        XCTAssertEqual(manager.installedFolder(for: expected)?.model, expected)
        var settings = AppSettings()
        settings.whisperModel = "missing-phase0-test-model"
        let transcriber = try TranscriberFactory.make(for: settings)
        XCTAssertEqual(transcriber.engineName, "Whisper \(expected)")
    }
}
