import EarnoteCore
import Foundation
import IOKit.ps
import Observation

/// Läuft der Mac gerade auf Akku oder im Stromsparmodus? Danach richtet sich, was während einer
/// Aufnahme nebenher laufen darf (Live-Mitschrift, Vorverdichten) und ob danach gleich verarbeitet wird.
@MainActor
@Observable
final class PowerSource {
    private(set) var isOnBattery = PowerSource.readIsOnBattery()
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Strom sparen: auf Akku oder im Stromsparmodus (der gilt auch am Netzteil – wer ihn einschaltet, will sparen)
    var savesEnergy: Bool { isOnBattery || isLowPowerMode }

    /// Nach jeder Änderung von Akku/Netzteil oder Stromsparmodus
    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    nonisolated private static let changed = Notification.Name("EarnotePowerSourceChanged")

    func start() {
        guard runLoopSource == nil else { return }
        // IOKit meldet sich über eine C-Funktion ohne Kontext – sie gibt die Meldung nur weiter.
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: PowerSource.changed, object: nil)
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        for name in [Self.changed, .NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    private func refresh() {
        let battery = Self.readIsOnBattery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard battery != isOnBattery || lowPower != isLowPowerMode else { return }
        isOnBattery = battery
        isLowPowerMode = lowPower
        Log.info("Stromquelle: \(battery ? "Akku" : "Netzteil")\(lowPower ? ", Stromsparmodus" : "")")
        onChange()
    }

    /// Macs ohne Akku (Mac mini, iMac) liefern „AC Power“ – dort wird nie gespart.
    nonisolated private static func readIsOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
