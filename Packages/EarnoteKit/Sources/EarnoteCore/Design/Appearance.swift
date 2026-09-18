import Foundation

/// Eine Farbe als Rot/Grün/Blau zwischen 0 und 1 – ohne SwiftUI, damit die Regeln testbar bleiben.
public struct ColorRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// „#4F7CFF“ oder „4F7CFF“
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }

    /// Wahrgenommene Helligkeit (0 = schwarz, 1 = weiß)
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

/// Bereichsfarben so anpassen, dass Auswahl und Symbole in Hell und Dunkel lesbar bleiben.
/// Reine Rechnung ohne Framework – dadurch mit Tests abgesichert.
public enum CategoryColor {
    /// Dunkler als das darf eine Farbe im Dunkelmodus nicht sein (sonst verschwindet sie im Hintergrund).
    static let darkModeRange = 0.45...0.85
    /// Heller als das darf sie im Hellmodus nicht sein (sonst ist weiße Schrift darauf nicht lesbar).
    static let lightModeRange = 0.18...0.55

    /// Farbe für Auswahl, Tint und Symbole: Helligkeit in den lesbaren Bereich schieben, Farbton bleibt.
    public static func readable(_ color: ColorRGB, dark: Bool) -> ColorRGB {
        let range = dark ? darkModeRange : lightModeRange
        let luminance = color.luminance
        if range.contains(luminance) { return color }
        if luminance < range.lowerBound {
            return blend(color, with: ColorRGB(red: 1, green: 1, blue: 1), target: range.lowerBound)
        }
        return blend(color, with: ColorRGB(red: 0, green: 0, blue: 0), target: range.upperBound)
    }

    /// Farbe zum Aufhellen/Abdunkeln mischen, bis die Zielhelligkeit erreicht ist (höchstens 60 Schritte).
    private static func blend(_ color: ColorRGB, with other: ColorRGB, target: Double) -> ColorRGB {
        var low = 0.0
        var high = 1.0
        var result = color
        for _ in 0..<60 {
            let amount = (low + high) / 2
            result = ColorRGB(red: color.red + (other.red - color.red) * amount,
                              green: color.green + (other.green - color.green) * amount,
                              blue: color.blue + (other.blue - color.blue) * amount)
            if abs(result.luminance - target) < 0.001 { return result }
            if result.luminance < target { low = amount } else { high = amount }
        }
        return result
    }
}

/// Lange Namen kürzen, damit schmale Fenster (Menüleiste) nicht auseinandergezogen werden.
public enum TextShortening {
    /// Kürzt in der Mitte: „Sehr langer Bereichsname“ → „Sehr la…name“. Kürzer als das Limit bleibt unverändert.
    public static func middleTruncated(_ text: String, max limit: Int) -> String {
        guard limit > 1, text.count > limit else { return text }
        let keep = limit - 1
        let front = (keep + 1) / 2
        let back = keep - front
        let start = text.prefix(front)
        let end = back > 0 ? text.suffix(back) : ""
        return "\(start)…\(end)"
    }
}

/// Ringpuffer der letzten Pegelwerte für die Wellenform: neue Werte rechts, alte wandern nach links.
public struct LevelBuffer: Equatable, Sendable {
    public private(set) var values: [Float]
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = Swift.max(1, capacity)
        values = Array(repeating: 0, count: self.capacity)
    }

    /// Neuen Wert anhängen (0…1); der älteste fällt hinten raus.
    public mutating func append(_ value: Float) {
        values.removeFirst()
        values.append(Swift.min(1, Swift.max(0, value)))
    }

    /// Alles auf Null – z. B. beim Start einer neuen Aufnahme.
    public mutating func reset() {
        values = Array(repeating: 0, count: capacity)
    }

    /// Grobe Einschätzung für VoiceOver: „still“, „leise“, „mittel“, „laut“
    public var loudnessDescription: String {
        let recent = values.suffix(10)
        return Self.loudness(recent.isEmpty ? 0 : recent.reduce(0, +) / Float(recent.count))
    }

    public static func loudness(_ level: Float) -> String {
        switch level {
        case ..<0.05: return "still"
        case ..<0.3: return "leise"
        case ..<0.7: return "mittel"
        default: return "laut"
        }
    }
}
