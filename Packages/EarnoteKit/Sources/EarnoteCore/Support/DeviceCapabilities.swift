import Foundation

/// Was das Gerät kann – Grundlage für Standardwerte (z. B. empfohlener KI-Anbieter, Abschnittsgröße)
/// und für die Voraussetzungen des lokalen Sprachmodells.
public enum DeviceCapabilities {
    /// Arbeitsspeicher in GB
    public static var memoryGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Warum das lokale Sprachmodell hier nicht läuft (nil = läuft).
    /// Voraussetzung: Apple Silicon mit mindestens 8 GB Arbeitsspeicher.
    public static var localModelUnsupportedReason: String? {
        guard isAppleSilicon else { return t("Das lokale Modell benötigt einen Mac mit Apple-Chip (M1 oder neuer).") }
        return memoryGB >= 7.5 ? nil : t("Dieser Mac hat zu wenig Arbeitsspeicher für das lokale Modell (mindestens 8 GB).")
    }

    public static var supportsLocalModel: Bool { localModelUnsupportedReason == nil }
}
