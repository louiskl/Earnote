import EarnoteCore
import Foundation
import Network

/// Ist überhaupt ein Netz da? Ohne diese Frage wartet der erste Start ohne Internet minutenlang
/// stumm am Download, statt zu sagen, was fehlt.
enum Reachability {
    /// Nur ein eindeutiges „kein Netz“ zählt als offline – im Zweifel (WLAN ohne Internet, VPN im Aufbau)
    /// läuft der Download los und die Fehlermeldung des Downloads greift.
    static func isOnline() async -> Bool {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "earnote.reachability"))
        // Der Monitor kennt den Pfad erst einen Augenblick nach dem Start
        try? await Task.sleep(nanoseconds: 300_000_000)
        let status = monitor.currentPath.status
        monitor.cancel()
        return status != .unsatisfied
    }

    /// Text für die Oberfläche, wenn wirklich kein Netz da ist
    static var offlineMessage: String {
        t("Keine Internetverbindung. Verbinde dich mit einem WLAN und versuche es erneut – das Modell wird nur ein einziges Mal geladen.")
    }
}
