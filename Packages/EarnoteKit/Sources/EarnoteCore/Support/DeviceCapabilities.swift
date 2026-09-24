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

    /// Ab hier trägt das Gerät das Standardmodell (Qwen3 4B); darunter, ab `smallModelMemoryGB`, das kleine (1.7B).
    /// Gemessen wird weniger als auf dem Etikett steht (ein iPhone mit 6 GB meldet etwa 5,6 GB).
    public static let fullModelMemoryGB = 7.5
    public static let smallModelMemoryGB = 5.5

    /// Warum das lokale Sprachmodell hier nicht läuft (nil = läuft).
    /// Voraussetzung: Apple Silicon mit mindestens 6 GB Arbeitsspeicher (jeder Mac mit Apple-Chip hat 8 GB oder mehr).
    public static var localModelUnsupportedReason: String? {
        guard isAppleSilicon else { return t("Das lokale Modell benötigt einen Mac mit Apple-Chip (M1 oder neuer).") }
        return memoryGB >= smallModelMemoryGB ? nil : t("Dieses Gerät hat zu wenig Arbeitsspeicher für das lokale Modell (mindestens 6 GB).")
    }

    public static var supportsLocalModel: Bool { localModelUnsupportedReason == nil }
}
