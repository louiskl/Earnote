import SwiftData
import XCTest
@testable import EarnoteCore

/// Weg B: Regeln für die Übergabe vom iPhone an den Mac
final class HandoffRulesTests: XCTestCase {
    private let mac = UUID()
    private let otherMac = UUID()
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testWaitingHandoffCanBeClaimedByAnyMac() {
        let handoff = Handoff(recordingID: UUID(), createdAt: now)
        XCTAssertTrue(HandoffRules.canClaim(handoff, by: mac, now: now))
        XCTAssertTrue(HandoffRules.canClaim(handoff, by: otherMac, now: now))
    }

    func testFreshClaimBlocksOtherMacsButNotItsOwner() {
        let handoff = Handoff(recordingID: UUID(), state: .claimed, claimedBy: mac, claimedAt: now.addingTimeInterval(-600))
        XCTAssertTrue(HandoffRules.canClaim(handoff, by: mac, now: now))
        XCTAssertFalse(HandoffRules.canClaim(handoff, by: otherMac, now: now))
        XCTAssertTrue(HandoffRules.isStillMine(handoff, device: mac))
        XCTAssertFalse(HandoffRules.isStillMine(handoff, device: otherMac))
    }

    /// Stürzt der erste Mac ab, bleibt die Aufnahme nicht für immer liegen
    func testExpiredClaimCanBeTakenOver() {
        let handoff = Handoff(recordingID: UUID(), state: .claimed, claimedBy: mac,
                              claimedAt: now.addingTimeInterval(-HandoffRules.claimExpiry - 1))
        XCTAssertTrue(HandoffRules.canClaim(handoff, by: otherMac, now: now))
    }

    func testFailedHandoffIsNotClaimedAgain() {
        let handoff = Handoff(recordingID: UUID(), state: .failed, errorMessage: "Audio beschädigt")
        XCTAssertFalse(HandoffRules.canClaim(handoff, by: mac, now: now))
    }

    func testOverdueOnlyWhileWaiting() {
        let old = now.addingTimeInterval(-HandoffRules.overdueAfter - 1)
        XCTAssertTrue(HandoffRules.isOverdue(Handoff(recordingID: nil, createdAt: old), now: now))
        XCTAssertFalse(HandoffRules.isOverdue(Handoff(recordingID: nil, createdAt: now.addingTimeInterval(-60)), now: now))
        XCTAssertFalse(HandoffRules.isOverdue(Handoff(recordingID: nil, createdAt: old, state: .claimed, claimedBy: mac, claimedAt: now), now: now))
    }

    func testOnlyRecentProcessingMacsWithV2Count() {
        let recent = now.addingTimeInterval(-3600)
        let devices = [
            SyncedDevice(id: mac, name: "MacBook", platform: .mac, canProcess: true, lastSeen: recent),
            SyncedDevice(id: UUID(), name: "Alter Mac", platform: .mac, canProcess: true,
                         lastSeen: now.addingTimeInterval(-HandoffRules.deviceRecent - 1)),
            SyncedDevice(id: UUID(), name: "Mac ohne Übernahme", platform: .mac, canProcess: false, lastSeen: recent),
            SyncedDevice(id: UUID(), name: "iPhone", platform: .iphone, canProcess: true, lastSeen: recent),
        ]
        XCTAssertEqual(HandoffRules.processingMacs(devices, now: now).map(\.id), [mac])
    }

    func testHeartbeatAtMostHourly() {
        XCTAssertTrue(HandoffRules.needsHeartbeat(lastSeen: nil, now: now))
        XCTAssertFalse(HandoffRules.needsHeartbeat(lastSeen: now.addingTimeInterval(-600), now: now))
        XCTAssertTrue(HandoffRules.needsHeartbeat(lastSeen: now.addingTimeInterval(-HandoffRules.heartbeatInterval - 1), now: now))
    }

    /// Die Warteschlange des iPhones darf übergebene Aufnahmen nicht selbst anfassen
    func testWaitingForMacIsNotBusy() {
        XCTAssertFalse(RecordingStatus.waitingForMac.isBusy)
    }
}

final class HandoffRepositoryTests: XCTestCase {
    private var library: SwiftDataLibraryRepository!

    override func setUpWithError() throws {
        library = SwiftDataLibraryRepository(modelContainer: try LibraryContainer.makeInMemory())
    }

    override func tearDown() { library = nil }

    func testHandoffRoundTripWithAudio() async throws {
        let recordingID = UUID()
        let handoff = Handoff(recordingID: recordingID, createdAt: Date(timeIntervalSince1970: 1_000), fromDevice: "iPhone")
        let audio = Data(repeating: 7, count: 4_096)
        try await library.insertHandoff(handoff, audio: audio)

        let stored = try await library.handoffs()
        XCTAssertEqual(stored, [handoff])
        let loaded = try await library.handoffAudio(handoff.id)
        XCTAssertEqual(loaded, audio)
    }

    func testClaimOnlyOnceAndDeleteRemovesAudio() async throws {
        let handoff = Handoff(recordingID: UUID())
        try await library.insertHandoff(handoff, audio: Data([1, 2, 3]))
        let mac = UUID(), otherMac = UUID()
        let now = Date()

        let first = try await library.claimHandoff(handoff.id, by: mac, now: now)
        let second = try await library.claimHandoff(handoff.id, by: otherMac, now: now)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let claimed = try await library.handoffs().first
        XCTAssertEqual(claimed?.claimedBy, mac)
        XCTAssertEqual(claimed?.state, .claimed)

        try await library.deleteHandoff(handoff.id)
        let remaining = try await library.handoffs()
        XCTAssertTrue(remaining.isEmpty)
        let audio = try await library.handoffAudio(handoff.id)
        XCTAssertNil(audio)
    }

    func testUpdateHandoffKeepsItsID() async throws {
        let handoff = Handoff(recordingID: UUID())
        try await library.insertHandoff(handoff, audio: Data())
        try await library.updateHandoff(handoff.id) {
            $0.id = UUID()
            $0.state = .failed
            $0.errorMessage = "Audio beschädigt"
        }
        let updated = try await library.handoffs()
        XCTAssertEqual(updated.map(\.id), [handoff.id])
        XCTAssertEqual(updated.first?.state, .failed)
        XCTAssertEqual(updated.first?.errorMessage, "Audio beschädigt")
    }

    func testSaveDeviceUpdatesInsteadOfDuplicating() async throws {
        let id = UUID()
        try await library.saveDevice(SyncedDevice(id: id, name: "MacBook", platform: .mac, canProcess: true,
                                                  lastSeen: Date(timeIntervalSince1970: 1_000)))
        try await library.saveDevice(SyncedDevice(id: id, name: "MacBook Pro", platform: .mac, canProcess: true,
                                                  lastSeen: Date(timeIntervalSince1970: 2_000)))
        let devices = try await library.devices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.name, "MacBook Pro")
        XCTAssertEqual(devices.first?.lastSeen, Date(timeIntervalSince1970: 2_000))
    }
}

/// Bestehende Bibliotheken (V1) müssen sich mit V2 öffnen lassen, ohne dass etwas verloren geht
final class LibraryMigrationTests: XCTestCase {
    func testVersion1StoreOpensWithLatestSchema() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EarnoteMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(LibraryContainer.fileName)
        let id = UUID()

        do {
            let schema = Schema(versionedSchema: EarnoteSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            let recording = LibraryRecording(id: id)
            recording.title = "Analysis II"
            context.insert(recording)
            try context.save()
        }

        let container = try LibraryContainer.make(url: url)
        let context = ModelContext(container)
        let recordings = try context.fetch(FetchDescriptor<LibraryRecording>())
        XCTAssertEqual(recordings.map(\.id), [id])
        XCTAssertEqual(recordings.first?.title, "Analysis II")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryHandoff>()), 0)
    }
}
