import AppKit
import EarnoteCore
import SwiftUI

extension RecordingCategory {
    var color: Color { Color(hex: colorHex) ?? .accentColor }

    /// Farbe für Auswahl, Tint und Symbole. Sie löst sich je nach Erscheinungsbild selbst auf,
    /// deshalb muss keine Ansicht nach Hell oder Dunkel fragen (siehe `CategoryColor`).
    var tint: Color {
        guard let rgb = ColorRGB(hex: colorHex) else { return .accentColor }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let readable = CategoryColor.readable(rgb, dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            return NSColor(srgbRed: readable.red, green: readable.green, blue: readable.blue, alpha: 1)
        })
    }
}

extension LibraryCategory {
    var tint: Color { snapshot().tint }
}

extension Color {
    init?(hex: String) {
        guard let rgb = ColorRGB(hex: hex) else { return nil }
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

private struct CategoryTintKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    /// Farbe des gewählten Bereichs – für Stellen, die `.tint` nicht selbst auswerten (z. B. `Canvas`)
    var categoryTint: Color {
        get { self[CategoryTintKey.self] }
        set { self[CategoryTintKey.self] = newValue }
    }
}

/// Emoji oder Symbol eines Bereichs auf einer runden, getönten Fläche – das eine Icon einer Zeile.
struct CategoryBadge: View {
    let emoji: String?
    let symbol: String
    let tint: Color
    var size: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size * 0.6))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Kleiner farbiger Punkt vor einem Bereichsnamen
struct CategoryDot: View {
    let tint: Color
    var size: CGFloat = 6.5

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
