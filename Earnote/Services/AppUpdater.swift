import EarnoteCore
import Sparkle
import SwiftUI

/// Selbstaktualisierung über Sparkle: Earnote fragt einmal am Tag beim Appcast auf der Projektseite nach,
/// zeigt eine neue Version mit ihren Änderungen und installiert sie erst, wenn der Nutzer zustimmt.
///
/// Die Update-Datei ist mit einem EdDSA-Schlüssel signiert, dessen öffentlicher Teil in der `Info.plist`
/// steht. Damit kann niemand eine untergeschobene Fassung installieren, selbst wenn er den Download
/// austauschen könnte.
@MainActor
@Observable
final class AppUpdater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    /// Läuft gerade eine Prüfung? (für den Knopf in den Einstellungen)
    private(set) var isChecking = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Einmal am Tag von selbst nachsehen – abschaltbar in den Einstellungen
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Wann zuletzt nachgesehen wurde (nil = noch nie)
    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    /// „Jetzt nach Updates suchen“: zeigt den Sparkle-Dialog, auch wenn alles aktuell ist.
    func checkNow() {
        isChecking = true
        controller.updater.checkForUpdates()
        // Sparkle führt den Rest selbst; der Knopf darf gleich wieder benutzbar sein.
        isChecking = false
    }
}
