import AVFoundation
import EarnoteCore
import Foundation
import Observation
import UIKit

/// Weg B auf dem iPhone (docs/IPHONE.md, Abschnitt 6a): Nach dem Stopp geht die Aufnahme komprimiert über iCloud an den
/// eigenen Mac (`LibraryHandoff`), der Mac schreibt Transkript und Notiz, beides kommt über den Abgleich zurück.
/// Das eigene Audio bleibt auf dem iPhone – scheitert die Übergabe, verarbeitet das iPhone selbst.
@MainActor
@Observable
final class HandoffSender {
    /// Macs, die Aufnahmen übernehmen (`HandoffRules.processingMacs`) – nach jedem Empfang aus iCloud neu gelesen
    private(set) var macs: [SyncedDevice] = []
    /// Offene Übergaben je Aufnahme: wartet, beim Mac, gescheitert
    private(set) var pending: [UUID: Handoff] = [:]

    @ObservationIgnored private let handoffs: any HandoffRepository
    @ObservationIgnored private let library: LibraryStore
    /// Schon gemeldete Übergaben (liegengeblieben oder gescheitert) – jede nur einmal
    @ObservationIgnored private var warned: Set<UUID> = []
    @ObservationIgnored private let defaults: UserDefaults
    private static let handedOffKey = "HandedOffRecordings"

    init(handoffs: any HandoffRepository, library: LibraryStore, defaults: UserDefaults) {
        self.handoffs = handoffs
        self.library = library
        self.defaults = defaults
    }

    /// Aufnahmen, die der Mac verarbeitet. Die Warteschlange des iPhones setzt sie nach einem Neustart nicht fort,
    /// auch wenn der Mac sie inzwischen auf „Wartet“ oder „Wird transkribiert“ gesetzt hat.
    private(set) var handedOff: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Self.handedOffKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { defaults.set(newValue.map(\.uuidString), forKey: Self.handedOffKey) }
    }

    /// Soll die Warteschlange dieses iPhones die Aufnahme nach einem Neustart fortsetzen?
    func resumesHere(_ recording: Recording) -> Bool {
        !handedOff.contains(recording.id) && library.audio.hasAudio(recording)
    }

    /// Ein Mac ist da, an den übergeben werden kann
    var isAvailable: Bool { library.settings.syncWithCloud && !macs.isEmpty }
    /// Neue Aufnahmen gehen an den Mac
    var isActive: Bool { isAvailable && library.settings.processOnMac }

    /// Nach dem Stopp: an den Mac übergeben oder hier verarbeiten
    func finish(_ id: UUID) {
        guard isActive else {
            library.enqueue(id)
            return
        }
        library.update(id) { $0.status = .waitingForMac }
        Task { await send(id) }
    }

    private func send(_ id: UUID) async {
        do {
            await library.waitForPendingWrites()
            let data = try await Self.compress(library.audio.micURL(for: id))
            let handoff = Handoff(recordingID: id, fromDevice: UIDevice.current.model)
            try await handoffs.insertHandoff(handoff, audio: data)
            pending[id] = handoff
            handedOff.insert(id)
            Log.info("Aufnahme an den Mac übergeben (\(data.count / 1_000_000) MB)")
        } catch {
            Log.error("Übergabe an den Mac: \(error.localizedDescription)")
            library.lastError = String(localized: "Die Aufnahme konnte nicht an deinen Mac übergeben werden. Sie wird jetzt auf dem iPhone verarbeitet.")
            processHere(id)
        }
    }

    /// Doch auf dem iPhone verarbeiten: Übergabe zurücknehmen (das Audio verschwindet aus iCloud) und einreihen
    func processHere(_ id: UUID) {
        handedOff.remove(id)
        if let handoff = pending.removeValue(forKey: id) {
            Task { try? await handoffs.deleteHandoff(handoff.id) }
        }
        library.enqueue(id)
    }

    /// Beim Start und nach jedem Empfang aus iCloud: Macs und offene Übergaben neu lesen, Liegengebliebenes melden
    func refresh() async {
        guard library.settings.syncWithCloud else { return }
        do {
            macs = HandoffRules.processingMacs(try await handoffs.devices())
            let all = try await handoffs.handoffs()
            var byRecording: [UUID: Handoff] = [:]
            for handoff in all {
                guard let id = handoff.recordingID else { continue }
                byRecording[id] = handoff
                notifyIfStuck(handoff)
            }
            pending = byRecording
            // Fertig oder gescheitert: Der Mac ist durch, die Aufnahme gehört wieder niemandem
            let finished = handedOff.filter { library.recording($0)?.status == .done }
            handedOff = handedOff.filter { id in
                guard let status = library.recording(id)?.status else { return false }
                return status != .done && status != .failed
            }
            // Die Notiz kam vom Mac – das eigene Audio braucht das iPhone nur, wenn „Audio behalten“ an ist
            if !library.settings.keepAudioFiles {
                for id in finished where library.hasAudio(id) {
                    library.deleteAudio(id)
                    Log.info("Audio nach der Notiz vom Mac gelöscht")
                }
            }
        } catch {
            Log.error("Übergaben lesen: \(error.localizedDescription)")
        }
    }

    private func notifyIfStuck(_ handoff: Handoff) {
        guard !warned.contains(handoff.id), handoff.state == .failed || HandoffRules.isOverdue(handoff) else { return }
        warned.insert(handoff.id)
        Notifier.send(String(localized: "Dein Mac hat die Aufnahme nicht übernommen"),
                      String(localized: "Öffne die Aufnahme und tippe auf „Auf dem iPhone verarbeiten“."))
    }

    /// PCM (~170 MB pro Stunde) als AAC in einer M4A-Datei (~30–60 MB pro Stunde)
    nonisolated private static func compress(_ source: URL) async throws -> Data {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("handoff-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: target) }
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await session.export(to: target, as: .m4a)
        return try Data(contentsOf: target)
    }
}
