import EarnoteCore
import Foundation

/// Ein lokales Sprachmodell zur Auswahl. Alle laufen über MLX auf Apple Silicon und sind 4-Bit-Fassungen,
/// damit sie in den Arbeitsspeicher passen.
public struct LocalModelInfo: Identifiable, Hashable, Sendable {
    /// Zugleich das Repository bei Hugging Face
    public let id: String
    public let name: String
    /// Größe des Downloads in GB
    public let sizeGB: Double
    /// Ab so viel Arbeitsspeicher ist das Modell sinnvoll
    public let minMemoryGB: Double
    /// Ein Satz für die Oberfläche
    public let detail: String

    public var sizeText: String {
        String(format: "%.1f GB", sizeGB).replacingOccurrences(of: ".", with: ",")
    }
}

/// Die Auswahl an lokalen Modellen – von „läuft auf jedem M1“ bis „nutzt 32 GB aus“.
/// Bewusst kurz gehalten: jedes weitere Modell ist eine Entscheidung mehr, die niemand treffen will.
public enum LocalModelCatalog {
    public static let all: [LocalModelInfo] = [
        LocalModelInfo(id: "mlx-community/Qwen3-1.7B-4bit", name: "Qwen3 1.7B",
                       sizeGB: 1.0, minMemoryGB: 6,
                       detail: t("Am schnellsten und am sparsamsten. Für ältere Macs oder wenn nebenbei viel läuft.")),
        LocalModelInfo(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit", name: "Qwen3 4B",
                       sizeGB: 2.3, minMemoryGB: 8,
                       detail: t("Gutes Deutsch, hält sich an Vorgaben, verarbeitet lange Transkripte am Stück.")),
        LocalModelInfo(id: "mlx-community/gemma-3-text-4b-it-4bit", name: "Gemma 3 4B",
                       sizeGB: 2.6, minMemoryGB: 8,
                       detail: t("Googles Modell in derselben Größe – schreibt etwas ausführlicher.")),
        LocalModelInfo(id: "mlx-community/Qwen2.5-7B-Instruct-4bit", name: "Qwen2.5 7B",
                       sizeGB: 4.3, minMemoryGB: 16,
                       detail: t("Älteres, größeres Modell: schreibt knapper, braucht aber doppelt so viel Arbeitsspeicher. Ab 16 GB.")),
        LocalModelInfo(id: "mlx-community/gemma-3-text-12b-it-4bit", name: "Gemma 3 12B",
                       sizeGB: 7.2, minMemoryGB: 24,
                       detail: t("Deutlich gründlicher, dafür langsamer. Ab 24 GB Arbeitsspeicher.")),
        LocalModelInfo(id: "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit", name: "Qwen3 30B A3B",
                       sizeGB: 17.2, minMemoryGB: 32,
                       detail: t("Groß, aber flink: Es rechnet nur mit einem Teil seiner Größe. Ab 32 GB.")),
    ]

    /// Das Modell, mit dem alles begann – und der Rückfall, wenn eine Kennung nicht mehr passt.
    public static var standard: LocalModelInfo { all[1] }

    public static func model(_ id: String) -> LocalModelInfo? { all.first { $0.id == id } }

    /// Was auf diesem Mac sinnvoll ist. Größer ist nicht besser: Ein Modell, das den Arbeitsspeicher
    /// füllt, lässt den Mac auslagern und macht die Notiz langsamer statt besser.
    /// Qwen3 4B (2507) überall: Im Vergleich an echten Vorlesungen (23.09.2026, MacBook Air M1 16 GB)
    /// schrieb es echte Lernfragen und erfasste mehr Inhalt als Qwen2.5 7B – in derselben Zeit
    /// und mit halb so viel Arbeitsspeicher.
    /// Geräte mit 6 GB (iPhone 13 Pro bis 15, iPads mit 6 GB) tragen das 4B-Modell nicht – dort das 1.7B-Modell:
    /// einfachere Notizen, aber ohne Internet, ohne Schlüssel und ohne Altersgrenze eines Cloud-Anbieters.
    public static func recommended(memoryGB: Double = DeviceCapabilities.memoryGB) -> LocalModelInfo {
        memoryGB < DeviceCapabilities.fullModelMemoryGB ? all[0] : standard
    }

    /// Modelle, die auf diesem Mac nicht in den Speicher passen, werden nicht versteckt,
    /// sondern als „braucht mehr Arbeitsspeicher“ gekennzeichnet.
    public static func fits(_ model: LocalModelInfo, memoryGB: Double = DeviceCapabilities.memoryGB) -> Bool {
        memoryGB + 0.5 >= model.minMemoryGB
    }
}
