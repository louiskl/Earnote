import EarnoteCore
import Foundation

/// Weg B auf dem Mac (docs/IPHONE.md, Abschnitt 6a): meldet diesen Mac als Gerät, das Aufnahmen übernimmt,
/// holt Aufnahmen vom iPhone aus iCloud ab und reiht sie in die eigene Warteschlange ein.
/// Das Audio verlässt iCloud, sobald es sicher auf dem Mac liegt; verarbeitet wird mit den Einstellungen des Macs.
@MainActor
final class HandoffWatcher {
    private let handoffs: any HandoffRepository
    private let library: LibraryStore
    private let deviceID: UUID
    private let deviceName: String
    private var isChecking = false
    private var lastHeartbeat: Date?
    private var heartbeat: Task<Void, Never>?

    init(handoffs: any HandoffRepository, library: LibraryStore, defaults: UserDefaults, deviceName: String) {
        self.handoffs = handoffs
        self.library = library
        self.deviceName = deviceName
        // Feste ID pro Installation: Sie steht in `claimedBy` und in der Geräteliste
        if let stored = defaults.string(forKey: "HandoffDeviceID").flatMap(UUID.init(uuidString:)) {
            deviceID = stored
        } else {
            deviceID = UUID()
            defaults.set(deviceID.uuidString, forKey: "HandoffDeviceID")
        }
    }

    /// Beim Start und stündlich nachsehen – dazu nach jedem Empfang aus iCloud (`check()` von außen)
    func start() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(HandoffRules.heartbeatInterval))
            }
        }
    }

    func check() async {
        guard library.settings.syncWithCloud, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        await announce()
        do {
            for handoff in try await handoffs.handoffs() where HandoffRules.canClaim(handoff, by: deviceID) {
                await take(handoff)
            }
        } catch {
            Log.error("Übergaben lesen: \(error.localizedDescription)")
        }
    }

    /// Höchstens stündlich in die Geräteliste schreiben – jede Meldung ist ein Schreibvorgang in iCloud
    private func announce() async {
        let now = Date()
        guard HandoffRules.needsHeartbeat(lastSeen: lastHeartbeat, now: now) else { return }
        do {
            try await handoffs.saveDevice(SyncedDevice(id: deviceID, name: deviceName, platform: .mac, canProcess: true, lastSeen: now))
            lastHeartbeat = now
        } catch {
            Log.error("Gerät melden: \(error.localizedDescription)")
        }
    }

    private func take(_ handoff: Handoff) async {
        guard let recordingID = handoff.recordingID else {
            try? await handoffs.deleteHandoff(handoff.id)
            return
        }
        // Die Aufnahme kommt womöglich erst mit einem späteren Abgleich – dann beim nächsten Mal
        if library.recording(recordingID) == nil { await library.load() }
        guard library.recording(recordingID) != nil else { return }

        do {
            if !HandoffRules.isStillMine(handoff, device: deviceID) {
                guard try await handoffs.claimHandoff(handoff.id, by: deviceID, now: Date()) else { return }
                // Haben zwei Macs zugleich beansprucht, hat CloudKit nach dem Abgleich einen Wert behalten
                try await Task.sleep(for: .seconds(HandoffRules.claimSettle))
                guard let current = try await handoffs.handoffs().first(where: { $0.id == handoff.id }),
                      HandoffRules.isStillMine(current, device: deviceID) else { return }
            }
            guard let data = try await handoffs.handoffAudio(handoff.id), !data.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let fileName = try store(data, format: handoff.audioFormat, for: recordingID)
            library.update(recordingID) {
                $0.importedFileName = fileName
                $0.status = .queued
                $0.errorMessage = nil
            }
            library.enqueue(recordingID)
            await library.waitForPendingWrites()
            // Das Audio liegt jetzt auf dem Mac – aus iCloud entfernen
            try await handoffs.deleteHandoff(handoff.id)
            Log.info("Aufnahme vom \(handoff.fromDevice.isEmpty ? "iPhone" : handoff.fromDevice) übernommen: \(recordingID)")
        } catch is CancellationError {
            return
        } catch {
            Log.error("Übergabe \(handoff.id): \(error.localizedDescription)")
            let message = String(localized: "Der Mac konnte die Aufnahme nicht übernehmen (\(error.localizedDescription)).")
            try? await handoffs.updateHandoff(handoff.id) {
                $0.state = .failed
                $0.errorMessage = message
            }
        }
    }

    /// Über eine temporäre Datei in den Audio-Speicher des Macs (wie ein Import)
    private func store(_ data: Data, format: String, for id: UUID) throws -> String {
        let ext = format.isEmpty ? "m4a" : format
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("handoff-\(id.uuidString).\(ext)")
        try data.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Nach einem Absturz mitten in der Übernahme liegt die Datei womöglich schon da
        try? FileManager.default.removeItem(at: library.audio.importedAudioURL(for: id, fileName: "import.\(ext)"))
        return try library.audio.importAudio(from: temporary, for: id)
    }
}
