import EarnoteCore
import SwiftData
import XCTest
@testable import Earnote

/// Bereiche anlegen, umbenennen, sortieren, löschen – und zwar so, dass es auch in der Bibliothek landet.
@MainActor
final class LibraryStoreCategoryTests: XCTestCase {
    private func makeStore() async throws -> (LibraryStore, SwiftDataLibraryRepository) {
        let container = try LibraryContainer.makeInMemory()
        let repository = SwiftDataLibraryRepository(modelContainer: container)
        let pipeline = ProcessingPipeline(library: repository, audio: FileAudioStore(storage: .standard),
                                          transcribers: PlatformTranscribers(), llm: LLMFactory(platform: PlatformLLMClients()),
                                          destinations: AppDestinations(), notify: { _, _ in })
        let suite = "app.earnote.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(library: repository, audio: FileAudioStore(storage: .standard),
                                 settingsRepository: UserDefaultsSettingsRepository(defaults: defaults),
                                 queue: ProcessingQueue(pipeline: pipeline))
        await store.load()
        return (store, repository)
    }

    /// Wie im Hauptfenster: „+ Neuer Bereich“ (⇧⌘N) und direkt danach den Namen eintippen
    func testNewCategoryRenamedRightAwayIsStored() async throws {
        let (store, repository) = try await makeStore()
        let category = store.addCategory()
        store.renameCategory(category.id, to: "Statistik")
        await store.waitForPendingWrites()

        let stored = try await repository.categories()
        XCTAssertEqual(stored.map(\.name), ["Statistik"])
        XCTAssertEqual(stored.first?.id, category.id)
    }

    func testOrderAndDeletionAreStoredAndRecordingsSurvive() async throws {
        let (store, repository) = try await makeStore()
        let first = store.addCategory(named: "Erster")
        let second = store.addCategory(named: "Zweiter")
        await store.waitForPendingWrites()

        store.setCategoryOrder([second.id, first.id])
        await store.waitForPendingWrites()
        var stored = try await repository.categories()
        XCTAssertEqual(stored.map(\.name), ["Zweiter", "Erster"])

        let recording = Recording(title: "Vorlesung", categoryID: second.id)
        try await repository.insertRecording(recording)
        store.deleteCategory(second.id)
        await store.waitForPendingWrites()

        stored = try await repository.categories()
        XCTAssertEqual(stored.map(\.name), ["Erster"])
        let recordings = try await repository.recordings()
        XCTAssertEqual(recordings.map(\.title), ["Vorlesung"])
        XCTAssertNil(recordings.first?.categoryID, "Die Aufnahme bleibt erhalten und verliert nur den Bereich")
    }
}
