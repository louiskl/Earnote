import Foundation

/// Hebt das Vorverdichtete auf, bis die Warteschlange die Aufnahme verarbeitet.
/// Nur im Arbeitsspeicher: Beendet jemand die App dazwischen, wird eben normal verdichtet –
/// das Transkript liegt ja auf der Festplatte.
public actor PreCondensedStore {
    private var byRecording: [UUID: PreCondensed] = [:]

    public init() {}

    public func set(_ value: PreCondensed, for id: UUID) {
        byRecording[id] = value
    }

    /// Einmalig abholen – ein zweiter Durchgang („Neu zusammenfassen“) soll frisch rechnen.
    public func take(_ id: UUID) -> PreCondensed? {
        byRecording.removeValue(forKey: id)
    }

    public func forget(_ id: UUID) {
        byRecording[id] = nil
    }
}
