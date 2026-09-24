import EarnoteCore
import Foundation
import Observation
import UIKit

/// Hängt das iPhone am Ladekabel, und ist der Stromsparmodus an? Danach richtet sich, ob nach dem Stopp
/// gleich verarbeitet wird – das Gegenstück zu `PowerSource` am Mac.
@MainActor
@Observable
final class PhonePower {
    private(set) var isCharging = false
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Nach jeder Änderung von Ladekabel oder Stromsparmodus
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        isCharging = Self.readIsCharging()
        for name in [UIDevice.batteryStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    /// Zurückhalten, solange das iPhone nicht lädt und man sparen will: mit „erst am Ladekabel“ oder im Stromsparmodus
    /// (wer ihn einschaltet, will sparen; die Notiz kommt dann beim nächsten Laden oder mit „Jetzt verarbeiten“)
    func holdsProcessing(onlyWhenCharging: Bool) -> Bool {
        !isCharging && (onlyWhenCharging || isLowPowerMode)
    }

    private func refresh() {
        let charging = Self.readIsCharging()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard charging != isCharging || lowPower != isLowPowerMode else { return }
        isCharging = charging
        isLowPowerMode = lowPower
        Log.info("Strom: \(charging ? "lädt" : "Akku")\(lowPower ? ", Stromsparmodus" : "")")
        onChange()
    }

    /// Der Simulator meldet `.unknown` – dort wird nie zurückgehalten.
    private static func readIsCharging() -> Bool {
        switch UIDevice.current.batteryState {
        case .unplugged: false
        case .charging, .full, .unknown: true
        @unknown default: true
        }
    }
}
