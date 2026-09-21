import CoreData
import EarnoteCore
import Foundation
import Observation

/// Was der iCloud-Abgleich gerade macht. CloudKit meldet jeden Schritt über eine Benachrichtigung;
/// ohne sie sieht man weder, dass etwas läuft, noch warum nichts ankommt.
@MainActor
@Observable
final class CloudSyncStatus {
    enum State: Equatable {
        case off
        case starting
        case syncing
        case idle(Date)
        case failed(String)
    }

    private(set) var state: State = .off

    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// Beobachtet den Abgleich. Ohne eingeschalteten Sync passiert nichts.
    func start(enabled: Bool) {
        guard enabled, observer == nil else { return }
        state = .starting
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main) { [weak self] notification in
                // Das Ereignis selbst ist nicht Sendable – hier gleich auf einfache Werte reduzieren.
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { return }
                let kind: String
                switch event.type {
                case .setup: kind = String(localized: "Einrichtung")
                case .import: kind = String(localized: "Empfangen")
                case .export: kind = String(localized: "Senden")
                @unknown default: kind = String(localized: "Abgleich")
                }
                let message = event.error?.localizedDescription
                let ended = event.endDate
                MainActor.assumeIsolated { self?.handle(kind: kind, error: message, ended: ended) }
            }
    }

    private func handle(kind: String, error: String?, ended: Date?) {
        if let error {
            state = .failed(error)
            Log.error("iCloud \(kind): \(error)")
            return
        }
        guard let ended else {
            state = .syncing
            return
        }
        state = .idle(ended)
        Log.info("iCloud \(kind) fertig")
    }

    /// Ein Satz für die Einstellungen
    var text: String {
        switch state {
        case .off: return String(localized: "Aus")
        case .starting: return String(localized: "Wird verbunden …")
        case .syncing: return String(localized: "Gleicht ab …")
        case .idle(let date):
            return String(localized: "Aktuell (\(date.formatted(date: .omitted, time: .shortened)))")
        case .failed(let message): return message
        }
    }
}
