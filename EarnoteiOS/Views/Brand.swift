import SwiftUI

/// Der eine „besondere Moment“ je Bildschirm (DESIGN_GUIDELINES Abschnitt 30): ein ruhig fließender Verlauf in
/// Earnote-Rot hinter Willkommensseite und laufender Aufnahme. Mit „Bewegung reduzieren“ steht er still.
struct BrandGlow: View {
    /// 0…1 – z. B. schwächer, solange eine Aufnahme pausiert
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let base = Color(uiColor: .systemBackground)
            let strength = colorScheme == .dark ? 0.55 : 0.38
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, Float(0.45 + 0.08 * sin(t * 0.5))], [Float(0.5 + 0.12 * cos(t * 0.4)), Float(0.45 + 0.1 * sin(t * 0.6))], [1, Float(0.5 + 0.08 * cos(t * 0.35))],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                .orange.opacity(strength * 0.8), .accentColor.opacity(strength), .pink.opacity(strength * 0.7),
                .accentColor.opacity(strength * 0.6), .orange.opacity(strength * 0.35), .accentColor.opacity(strength * 0.5),
                base, base, base,
            ])
        }
        .opacity(intensity)
        .animation(.easeInOut(duration: 0.6), value: intensity)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension Color {
    /// Farbe eines Bereichs („#9B5CFF“)
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xE8453B
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
