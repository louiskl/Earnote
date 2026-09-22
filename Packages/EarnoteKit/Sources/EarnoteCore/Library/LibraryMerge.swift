import Foundation

/// Ergebnis von `LibraryRepository.mergeDuplicates()`
public struct LibraryMergeReport: Sendable, Equatable {
    /// Entfernter Bereich → Bereich, in dem er aufgegangen ist
    public var categoryReplacements: [UUID: UUID] = [:]
    /// Zusammengelegte Wörterbuch-Einträge
    public var removedGlossaryTerms = 0

    public init() {}

    public var isEmpty: Bool { categoryReplacements.isEmpty && removedGlossaryTerms == 0 }

    public var summary: String {
        "Doppelte zusammengeführt: \(categoryReplacements.count) Bereiche, \(removedGlossaryTerms) Wörterbuch-Einträge"
    }
}

/// Regeln, nach denen Doppelte beim iCloud-Abgleich erkannt werden.
///
/// Richten zwei Macs Earnote ein, legt jeder seine Standardbereiche an; nach dem Abgleich stehen sie doppelt da.
/// Beide Macs führen unabhängig voneinander zusammen – deshalb muss die Wahl des Überlebenden auf jedem Gerät
/// gleich ausfallen, sonst löscht jeder den Bereich, den der andere behalten hat.
public enum LibraryMerge {
    /// Vergleichsschlüssel für Namen: Groß-/Kleinschreibung, Akzente und Leerraum egal
    public static func key(_ name: String) -> String {
        SearchText.normalized(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    /// Fasst Einträge zu Gruppen zusammen, die dieselbe ID oder denselben (nicht leeren) Namen haben.
    /// Liefert nur Gruppen mit mehr als einem Eintrag; jede Gruppe in der Reihenfolge von `items`.
    static func groups<Item>(_ items: [Item], id: (Item) -> UUID, name: (Item) -> String) -> [[Item]] {
        // Union-Find über die Positionen: gleiche ID oder gleicher Name verbindet
        var parent = Array(items.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func join(_ a: Int, _ b: Int) { parent[root(a)] = root(b) }
        var byID: [UUID: Int] = [:]
        var byName: [String: Int] = [:]
        for (i, item) in items.enumerated() {
            if let other = byID[id(item)] { join(i, other) } else { byID[id(item)] = i }
            let k = key(name(item))
            guard !k.isEmpty else { continue }
            if let other = byName[k] { join(i, other) } else { byName[k] = i }
        }
        var grouped: [Int: [Item]] = [:]
        var order: [Int] = []
        for (i, item) in items.enumerated() {
            let r = root(i)
            if grouped[r] == nil { order.append(r) }
            grouped[r, default: []].append(item)
        }
        return order.compactMap { grouped[$0] }.filter { $0.count > 1 }
    }

    /// Auf jedem Gerät derselbe: der älteste, bei Gleichstand die kleinste ID
    static func survivor<Item>(_ group: [Item], createdAt: (Item) -> Date, id: (Item) -> UUID) -> Item? {
        group.min { a, b in
            let (da, db) = (createdAt(a), createdAt(b))
            return da != db ? da < db : id(a).uuidString < id(b).uuidString
        }
    }

    /// Schreibweisen zusammenlegen, ohne Doppelte (Groß-/Kleinschreibung egal), Reihenfolge bleibt
    static func union(_ lists: [[String]]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in lists.joined() where seen.insert(key(value)).inserted { result.append(value) }
        return result
    }
}
