import Foundation
import SwiftData

// Weg B (docs/IPHONE.md, Abschnitt 6a): Das iPhone nimmt auf, der eigene Mac verarbeitet.
// Das Audio reist als `LibraryHandoff` über die private iCloud-Datenbank und wird danach gelöscht.

public enum HandoffState: String, Codable, Sendable {
    /// Liegt bereit, kein Mac hat sie genommen
    case waiting
    /// Ein Mac verarbeitet sie (`claimedBy`)
    case claimed
    /// Der Mac konnte sie nicht verarbeiten (`errorMessage`); das iPhone bietet an, selbst zu verarbeiten
    case failed
}

public enum DevicePlatform: String, Codable, Sendable {
    case mac, iphone, ipad
}

/// Übergabe als Wert – ohne das Audio, das nur `HandoffRepository.handoffAudio` lädt
public struct Handoff: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var recordingID: UUID?
    public var createdAt: Date
    public var fromDevice: String
    public var audioFormat: String
    public var state: HandoffState
    public var claimedBy: UUID?
    public var claimedAt: Date?
    public var errorMessage: String?

    public init(id: UUID = UUID(), recordingID: UUID?, createdAt: Date = Date(), fromDevice: String = "",
                audioFormat: String = "m4a", state: HandoffState = .waiting, claimedBy: UUID? = nil,
                claimedAt: Date? = nil, errorMessage: String? = nil) {
        self.id = id
        self.recordingID = recordingID
        self.createdAt = createdAt
        self.fromDevice = fromDevice
        self.audioFormat = audioFormat
        self.state = state
        self.claimedBy = claimedBy
        self.claimedAt = claimedAt
        self.errorMessage = errorMessage
    }
}

/// Ein Gerät der Bibliothek als Wert
public struct SyncedDevice: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var platform: DevicePlatform
    public var canProcess: Bool
    public var schemaVersion: Int
    public var lastSeen: Date

    public init(id: UUID, name: String, platform: DevicePlatform, canProcess: Bool,
                schemaVersion: Int = 2, lastSeen: Date = Date()) {
        self.id = id
        self.name = name
        self.platform = platform
        self.canProcess = canProcess
        self.schemaVersion = schemaVersion
        self.lastSeen = lastSeen
    }
}

/// Wer darf eine Übergabe nehmen, wann gilt sie als liegengeblieben, welcher Mac zählt als erreichbar.
/// Reine Regeln ohne Speicher – so sind sie auf jedem Gerät gleich und testbar.
public enum HandoffRules {
    /// So lange gilt der Anspruch eines Macs. Danach darf ein anderer übernehmen (der erste ist abgestürzt o. ä.).
    public static let claimExpiry: TimeInterval = 2 * 3600
    /// Nach dem Beanspruchen so lange warten, bis der Abgleich die Ansprüche anderer Macs geliefert hat
    public static let claimSettle: TimeInterval = 60
    /// Ohne Mac so lange warten, bis das iPhone anbietet, selbst zu verarbeiten
    public static let overdueAfter: TimeInterval = 24 * 3600
    /// Ein Mac, der sich so lange nicht gemeldet hat, zählt nicht mehr als erreichbar
    public static let deviceRecent: TimeInterval = 14 * 24 * 3600
    /// So oft meldet sich ein Gerät höchstens (jede Meldung ist ein Schreibvorgang in iCloud)
    public static let heartbeatInterval: TimeInterval = 3600

    public static func canClaim(_ handoff: Handoff, by device: UUID, now: Date = Date()) -> Bool {
        switch handoff.state {
        case .waiting:
            return true
        case .claimed:
            if handoff.claimedBy == device { return true }
            guard let claimedAt = handoff.claimedAt else { return true }
            return now.timeIntervalSince(claimedAt) > claimExpiry
        case .failed:
            return false
        }
    }

    /// Nach `claimSettle` nachsehen: Haben zwei Macs gleichzeitig beansprucht, hat CloudKit einen Wert behalten
    /// (der letzte Schreiber gewinnt) – beide sehen denselben, und nur einer macht weiter.
    public static func isStillMine(_ handoff: Handoff, device: UUID) -> Bool {
        handoff.state == .claimed && handoff.claimedBy == device
    }

    /// Kein Mac hat die Aufnahme rechtzeitig genommen
    public static func isOverdue(_ handoff: Handoff, now: Date = Date()) -> Bool {
        handoff.state == .waiting && now.timeIntervalSince(handoff.createdAt) > overdueAfter
    }

    /// Macs, an die das iPhone übergeben kann: melden sich regelmäßig, übernehmen Aufnahmen und kennen Schema V2
    public static func processingMacs(_ devices: [SyncedDevice], now: Date = Date()) -> [SyncedDevice] {
        devices.filter {
            $0.platform == .mac && $0.canProcess && $0.schemaVersion >= 2 && now.timeIntervalSince($0.lastSeen) < deviceRecent
        }
    }

    /// Nur wenn ein weiterer Mac mitliest, kann er zeitgleich beanspruchen – sonst ist das Warten (`claimSettle`) unnötig
    public static func mustSettleClaim(_ devices: [SyncedDevice], me: UUID, now: Date = Date()) -> Bool {
        processingMacs(devices, now: now).contains { $0.id != me }
    }

    public static func needsHeartbeat(lastSeen: Date?, now: Date = Date()) -> Bool {
        guard let lastSeen else { return true }
        return now.timeIntervalSince(lastSeen) > heartbeatInterval
    }
}

/// Übergaben und Geräte speichern. Getrennt von `LibraryRepository`, weil nur Weg B sie braucht.
public protocol HandoffRepository: Sendable {
    /// Alle Übergaben, älteste zuerst – ohne Audio
    func handoffs() async throws -> [Handoff]
    func insertHandoff(_ handoff: Handoff, audio: Data) async throws
    func handoffAudio(_ id: UUID) async throws -> Data?
    /// Beansprucht die Übergabe für dieses Gerät, wenn `HandoffRules.canClaim` es erlaubt. Liefert, ob es geklappt hat.
    func claimHandoff(_ id: UUID, by device: UUID, now: Date) async throws -> Bool
    func updateHandoff(_ id: UUID, _ change: @escaping @Sendable (inout Handoff) -> Void) async throws
    /// Löscht die Übergabe samt Audio (auch aus iCloud)
    func deleteHandoff(_ id: UUID) async throws

    func devices() async throws -> [SyncedDevice]
    /// Legt das Gerät an oder aktualisiert es
    func saveDevice(_ device: SyncedDevice) async throws
}

extension LibraryHandoff {
    public func snapshot() -> Handoff {
        Handoff(id: id, recordingID: recordingID, createdAt: createdAt, fromDevice: fromDevice, audioFormat: audioFormat,
                state: state, claimedBy: claimedBy, claimedAt: claimedAt, errorMessage: errorMessage)
    }

    /// Alles außer dem Audio
    public func apply(_ handoff: Handoff) {
        recordingID = handoff.recordingID
        createdAt = handoff.createdAt
        fromDevice = handoff.fromDevice
        audioFormat = handoff.audioFormat
        state = handoff.state
        claimedBy = handoff.claimedBy
        claimedAt = handoff.claimedAt
        errorMessage = handoff.errorMessage
    }
}

extension LibraryDevice {
    public func snapshot() -> SyncedDevice {
        SyncedDevice(id: id, name: name, platform: platform, canProcess: canProcess, schemaVersion: schemaVersion, lastSeen: lastSeen)
    }

    public func apply(_ device: SyncedDevice) {
        name = device.name
        platform = device.platform
        canProcess = device.canProcess
        schemaVersion = device.schemaVersion
        lastSeen = device.lastSeen
    }
}

extension SwiftDataLibraryRepository: HandoffRepository {
    private func handoffModel(_ id: UUID) throws -> LibraryHandoff? {
        var descriptor = FetchDescriptor<LibraryHandoff>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    public func handoffs() throws -> [Handoff] {
        try modelContext.fetch(FetchDescriptor<LibraryHandoff>(sortBy: [SortDescriptor(\.createdAt)])).map { $0.snapshot() }
    }

    public func insertHandoff(_ handoff: Handoff, audio: Data) throws {
        guard try handoffModel(handoff.id) == nil else { return }
        let model = LibraryHandoff(id: handoff.id)
        model.apply(handoff)
        model.audio = audio
        modelContext.insert(model)
        try modelContext.save()
    }

    public func handoffAudio(_ id: UUID) throws -> Data? {
        try handoffModel(id)?.audio
    }

    public func claimHandoff(_ id: UUID, by device: UUID, now: Date) throws -> Bool {
        guard let model = try handoffModel(id), HandoffRules.canClaim(model.snapshot(), by: device, now: now) else { return false }
        model.state = .claimed
        model.claimedBy = device
        model.claimedAt = now
        try modelContext.save()
        return true
    }

    public func updateHandoff(_ id: UUID, _ change: @escaping @Sendable (inout Handoff) -> Void) throws {
        guard let model = try handoffModel(id) else { return }
        var handoff = model.snapshot()
        change(&handoff)
        handoff.id = id
        model.apply(handoff)
        try modelContext.save()
    }

    public func deleteHandoff(_ id: UUID) throws {
        guard let model = try handoffModel(id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    public func devices() throws -> [SyncedDevice] {
        try modelContext.fetch(FetchDescriptor<LibraryDevice>(sortBy: [SortDescriptor(\.lastSeen, order: .reverse)])).map { $0.snapshot() }
    }

    public func saveDevice(_ device: SyncedDevice) throws {
        let id = device.id
        var descriptor = FetchDescriptor<LibraryDevice>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let model = try modelContext.fetch(descriptor).first {
            model.apply(device)
        } else {
            let model = LibraryDevice(id: device.id)
            model.apply(device)
            modelContext.insert(model)
        }
        try modelContext.save()
    }
}
