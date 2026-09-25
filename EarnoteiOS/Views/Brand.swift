import SwiftUI

/// Der eine „besondere Moment“ je Bildschirm (DESIGN_GUIDELINES Abschnitt 30): ein ruhig fließender Verlauf in
/// der Farbe der App (Earnote-Rot oder die gewählte aus dem Dankeschön-Paket) hinter Willkommensseite und laufender Aufnahme. Mit „Bewegung reduzieren“ steht er still.
struct BrandGlow: View {
    /// 0…1 – z. B. schwächer, solange eine Aufnahme pausiert
    var intensity: Double = 1
    /// Pegel 0…1, jedes Bild abgefragt – der Verlauf atmet dann mit der Stimme (Aufnahme)
    var level: (() -> Float)?
    @State private var smoothed = Smoothed()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.skin) private var skin

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let energy = reduceMotion ? 0 : smoothed.next(Double(level?() ?? 0))
            let base = Color(uiColor: .systemBackground)
            let strength = (colorScheme == .dark ? 0.55 : 0.38) * (1 + 0.6 * energy)
            let swing = 1 + 1.8 * energy
            let accent = skin.tint, (side, other) = skin.glow
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, Float(0.45 + 0.08 * swing * sin(t * 0.5))],
                [Float(0.5 + 0.12 * swing * cos(t * 0.4)), Float(0.45 - 0.12 * energy + 0.1 * sin(t * 0.6))],
                [1, Float(0.5 + 0.08 * swing * cos(t * 0.35))],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                side.opacity(strength * 0.8), accent.opacity(strength), other.opacity(strength * 0.7),
                accent.opacity(strength * 0.6), side.opacity(strength * 0.35), accent.opacity(strength * 0.5),
                base, base, base,
            ])
        }
        .opacity(intensity)
        .animation(.easeInOut(duration: 0.6), value: intensity)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Glättet den Pegel, damit der Verlauf ruhig atmet statt zu flackern
private final class Smoothed {
    private var value = 0.0
    func next(_ target: Double) -> Double {
        value += (min(1, target) - value) * 0.12
        return value
    }
}

extension Color {
    /// Farbe eines Bereichs („#9B5CFF“)
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xE8453B
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
