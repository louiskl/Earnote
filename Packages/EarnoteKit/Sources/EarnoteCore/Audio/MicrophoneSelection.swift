import Foundation

/// Ein Eingabegerät, unabhängig von der Plattform beschrieben (die Mac-App liest es aus Core Audio).
public struct AudioInputDeviceInfo: Identifiable, Hashable, Sendable {
    public enum Transport: String, Sendable {
        case builtIn, usb, bluetooth, bluetoothLE, virtual, aggregate, continuity, thunderbolt, hdmi, displayPort, pci, fireWire, airPlay, unknown
    }

    public var uid: String
    public var name: String
    public var transport: Transport
    public var sampleRate: Double
    public var channels: Int

    public var id: String { uid }

    public init(uid: String, name: String, transport: Transport, sampleRate: Double = 48_000, channels: Int = 1) {
        self.uid = uid
        self.name = name
        self.transport = transport
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var isBuiltIn: Bool { transport == .builtIn }

    /// Vorübergehende Hilfsgeräte, die macOS selbst anlegt (z. B. „CADefaultDeviceAggregate-<Prozess>“, wenn eine
    /// Audio-Engine Ein- und Ausgabe über verschiedene Geräte verbindet). Sie sind kein Mikrofon und werden nicht angezeigt.
    public var isSystemHelper: Bool {
        name.hasPrefix("CADefaultDeviceAggregate") || uid.hasPrefix("CADefaultDeviceAggregate")
    }

    /// Präfix der UIDs von Earnotes eigenen Aggregat-Geräten (Systemton-Aufnahme)
    public static let ownAggregatePrefix = "\(AppInfo.bundleIdentifier).aggregate"

    /// Bekannte virtuelle Treiber, die Ton nur weiterreichen (z. B. BlackHole, Teams, Zoom, Loopback)
    private static let virtualMarkers = ["blackhole", "loopback", "msloopback", "teams audio", "zoomaudio", "zoom audio",
                                         "soundflower", "virtual", "obs audio", "krisp"]

    /// Kein echtes Mikrofon: virtuelle Treiber, Aggregat-Geräte (auch Earnotes eigene).
    /// Bleiben wählbar, stehen aber hinten und werden nie automatisch als Ausweichgerät genommen.
    public var isVirtual: Bool {
        if transport == .virtual || transport == .aggregate || isSystemHelper || uid.hasPrefix(Self.ownAggregatePrefix) { return true }
        let haystack = (uid + " " + name).lowercased()
        return Self.virtualMarkers.contains { haystack.contains($0) }
    }
}

/// Entscheidet, mit welchem Mikrofon eine Aufnahme startet und worauf ausgewichen wird.
public enum MicrophonePlan {
    /// Was beim Start versucht wird
    public struct Start: Equatable, Sendable {
        /// In dieser Reihenfolge versuchen; das erste Gerät bekommt einen zweiten Versuch
        public var candidates: [AudioInputDeviceInfo]
        /// Das gewählte Gerät ist nicht verbunden; es wird der Systemstandard benutzt
        public var preferredMissing: Bool
    }

    /// Geräte für die Auswahl: echte Mikrofone zuerst (eingebautes vorne), virtuelle Geräte ans Ende.
    public static func sortedForDisplay(_ devices: [AudioInputDeviceInfo]) -> [AudioInputDeviceInfo] {
        devices.filter { !$0.isSystemHelper }.sorted { a, b in
            if a.isVirtual != b.isVirtual { return !a.isVirtual }
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Ausweichgeräte: nur echte Mikrofone. Eingebautes zuerst, Bluetooth zuletzt
    /// (ein Headset schaltet dabei in den Telefonmodus und klingt schlechter).
    public static func fallbacks(_ devices: [AudioInputDeviceInfo], excluding: Set<String>) -> [AudioInputDeviceInfo] {
        func rank(_ d: AudioInputDeviceInfo) -> Int {
            switch d.transport {
            case .builtIn: return 0
            case .bluetooth, .bluetoothLE: return 3
            case .continuity: return 2
            default: return 1
            }
        }
        return devices
            .filter { !$0.isVirtual && !$0.isSystemHelper && !excluding.contains($0.uid) }
            .sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// - Parameters:
    ///   - preferredUID: gewähltes Gerät (nil = Systemstandard)
    ///   - defaultUID: aktuelles Standard-Eingabegerät des Systems
    public static func start(devices: [AudioInputDeviceInfo], preferredUID: String?, defaultUID: String?) -> Start {
        let preferred = preferredUID.flatMap { uid in devices.first { $0.uid == uid } }
        let systemDefault = defaultUID.flatMap { uid in devices.first { $0.uid == uid } }
        let primary = preferred ?? systemDefault ?? fallbacks(devices, excluding: []).first
        var candidates = primary.map { [$0] } ?? []
        candidates += fallbacks(devices, excluding: Set(candidates.map(\.uid)))
        return Start(candidates: candidates, preferredMissing: preferredUID != nil && preferred == nil)
    }

    /// Ersatz, wenn das laufende Gerät während der Aufnahme verschwindet oder nicht mehr startet.
    /// Das gewählte Gerät kommt zuerst, falls es (wieder) da ist, dann der Systemstandard, dann echte Mikrofone.
    public static func replacement(devices: [AudioInputDeviceInfo], lostUID: String, preferredUID: String?,
                                   defaultUID: String?) -> [AudioInputDeviceInfo] {
        var result: [AudioInputDeviceInfo] = []
        func add(_ d: AudioInputDeviceInfo?) {
            if let d, d.uid != lostUID, !result.contains(where: { $0.uid == d.uid }) { result.append(d) }
        }
        add(preferredUID.flatMap { uid in devices.first { $0.uid == uid } })
        add(defaultUID.flatMap { uid in devices.first { $0.uid == uid } })
        fallbacks(devices, excluding: [lostUID]).forEach { add($0) }
        return result
    }
}

/// Was beim Mikrofon passieren kann – und was die Nutzerin / der Nutzer darüber liest.
/// Technische Details (Fehlerdomäne, Code, Formate) gehören ins Protokoll, nie in diese Texte.
public enum MicrophoneEvent: Equatable, Sendable {
    /// Keine Erlaubnis für das Mikrofon
    case permissionDenied
    /// Es ist gar kein Eingabegerät vorhanden
    case noDevices
    /// Kein Gerät ließ sich starten
    case allFailed
    /// Gewähltes Gerät nicht verbunden, Aufnahme läuft über den Systemstandard
    case preferredMissing(preferred: String, used: String)
    /// Gerät hat beim Start nicht reagiert, Aufnahme läuft über ein anderes
    case fellBack(failed: String, used: String)
    /// Gerät ist während der Aufnahme verschwunden, Aufnahme läuft über ein anderes weiter
    case switchedDuringRecording(lost: String, used: String)
    /// Gerät ist während der Aufnahme verschwunden und es gibt keinen Ersatz
    case lostWithoutReplacement(lost: String)

    public var message: String {
        switch self {
        case .permissionDenied:
            return "\(AppInfo.name) hat keinen Zugriff auf das Mikrofon. Bitte in den Systemeinstellungen erlauben."
        case .noDevices:
            return "Es ist kein Mikrofon verfügbar. Schließ ein Mikrofon an und versuche es erneut."
        case .allFailed:
            return "Kein Mikrofon hat reagiert. Steck das Mikrofon kurz ab und wieder an oder wähle in den Einstellungen unter „Aufnahme“ ein anderes."
        case .preferredMissing(let preferred, let used):
            return "Das gewählte Mikrofon „\(preferred)“ ist nicht verbunden. Die Aufnahme läuft über den Systemstandard „\(used)“."
        case .fellBack(let failed, let used):
            return "Das Mikrofon „\(failed)“ hat nicht reagiert. Die Aufnahme läuft über „\(used)“."
        case .switchedDuringRecording(let lost, let used):
            return "Das Mikrofon „\(lost)“ ist nicht mehr verfügbar. Die Aufnahme läuft über „\(used)“ weiter."
        case .lostWithoutReplacement(let lost):
            return "Das Mikrofon „\(lost)“ ist nicht mehr verfügbar und es gibt kein anderes. Schließ ein Mikrofon an – die Aufnahme geht dann weiter."
        }
    }
}
