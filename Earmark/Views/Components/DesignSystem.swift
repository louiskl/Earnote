import SwiftUI

// MARK: - Gestaltungsregeln
//
// Eine Skala für Schrift, eine für Abstände, eine Akzentfarbe mit klarer Aufgabe.
// Alles andere baut darauf auf – das hält die Oberfläche ruhig und zusammenhängend.

enum Theme {
    /// Die Akzentfarbe ist reserviert: laufende Aufnahme und die jeweils wichtigste Aktion.
    static let accent = Color(hex: "#FF5A4E")!
    static let accentSoft = Color(hex: "#FF5A4E")!.opacity(0.12)

    /// Abstände in Vielfachen von 4 – kein handgesetztes „irgendwas dazwischen“ mehr.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    /// Fünf Stufen, abgeleitet von den macOS-Textstilen (22 / 15 / 13 / 12 / 11 Punkt).
    /// Sie skalieren mit den Systemeinstellungen mit – feste Punktgrößen tun das nicht.
    enum Font {
        static let title = SwiftUI.Font.system(.title, design: .default, weight: .semibold)
        static let heading = SwiftUI.Font.system(.title3, design: .default, weight: .semibold)
        static let body = SwiftUI.Font.system(.body)
        static let small = SwiftUI.Font.system(.callout)
        static let caption = SwiftUI.Font.system(.subheadline)
        /// Zahlen, die sich ständig ändern (Uhr, Pegel): rund und laufweitenstabil.
        static func number(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
    }

    /// Ruhiger Verlauf für große Flächen (Aufnahmeansicht, leere Zustände).
    static func glow(_ color: Color = accent) -> RadialGradient {
        RadialGradient(colors: [color.opacity(0.18), color.opacity(0.0)],
                       center: .center, startRadius: 4, endRadius: 260)
    }
}

// MARK: - Flächen

/// Karte mit Materialhintergrund, Haarlinie und weichem Schatten.
/// Bewusst sparsam einsetzen: nur für echte Gruppen, nie verschachtelt.
struct SurfaceBackground: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(elevated ? 0.14 : 0.05),
                            radius: elevated ? 14 : 5, y: elevated ? 6 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

/// Hebt ein Element beim Darüberfahren sanft an – gibt der Oberfläche Leben, ohne zu zappeln.
struct HoverLift: ViewModifier {
    var scale: CGFloat = 1.01
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .brightness(hovering ? 0.03 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func card(padding: CGFloat = Theme.Space.l, radius: CGFloat = Theme.Radius.large, elevated: Bool = false) -> some View {
        modifier(SurfaceBackground(padding: padding, radius: radius, elevated: elevated))
    }

    func hoverLift(_ scale: CGFloat = 1.01) -> some View { modifier(HoverLift(scale: scale)) }

    func fittingHeight() -> some View { fixedSize(horizontal: false, vertical: true) }
}

// MARK: - Bewegte Bausteine

/// Pulsierender Punkt für „läuft gerade“ – mit Hof, der langsam atmet.
struct PulsingDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 8
    var active = true
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: size * 2.4, height: size * 2.4)
                .scaleEffect(pulse ? 1 : 0.4)
                .opacity(pulse ? 0 : 0.8)
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear { if active { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true } } }
    }
}

/// Pegelanzeige als symmetrische Wellenform. Die Balken schwingen weich nach,
/// statt hart umzuspringen – das wirkt lebendig, ohne unruhig zu sein.
struct Waveform: View {
    var level: Float
    var color: Color = Theme.accent
    var bars = 28
    var height: CGFloat = 26
    var muted = false

    var body: some View {
        let db = level > 0 ? 20 * log10(level) : -80
        let loudness = CGFloat(max(0, min(1, (db + 55) / 50)))
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                // Mitte höher als die Ränder: ergibt die typische Wellenform
                let position = abs(CGFloat(i) - CGFloat(bars - 1) / 2) / (CGFloat(bars) / 2)
                let shape = pow(1 - position, 1.4)
                // feste, leicht ungleichmäßige Streuung je Balken – zufällig pro Bild würde flimmern
                let jitter = 0.78 + 0.32 * abs(sin(Double(i) * 12.9898))
                let value = max(0.12, loudness * shape * CGFloat(jitter))
                Capsule()
                    .fill(muted ? AnyShapeStyle(Color.secondary.opacity(0.25))
                                : AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.6)],
                                                               startPoint: .top, endPoint: .bottom)))
                    .frame(width: 3, height: max(3, height * value))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: loudness)
    }
}

/// Dünne Fortschrittslinie mit wanderndem Glanz – zeigt „es passiert etwas“,
/// auch wenn ein Schritt gerade keinen Zwischenstand meldet.
struct ProgressLine: View {
    var progress: Double
    var color: Color = Theme.accent
    @State private var shimmer = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * min(1, max(0, progress))))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.45), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 60)
                            .offset(x: shimmer ? geo.size.width : -60)
                            .allowsHitTesting(false)
                    }
                    .clipShape(Capsule())
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: progress)
            }
        }
        .frame(height: 3)
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmer = true }
        }
    }
}

/// Status als kleine Plakette: Punkt plus Wort, keine schreienden Farben.
struct StatusPill: View {
    let text: String
    var color: Color = .secondary
    var animated = false

    var body: some View {
        HStack(spacing: Theme.Space.xs + 1) {
            if animated {
                PulsingDot(color: color, size: 5)
            } else {
                Circle().fill(color).frame(width: 5, height: 5)
            }
            Text(text)
        }
        .font(Theme.Font.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Arc-Look

extension Theme {
    /// Grundfarbe, wenn kein Bereich ausgewählt ist: das warme Earmark-Koralle.
    static let brand = accent
    /// Zweitfarbe für Verläufe: ein weiches Lila, das zur Koralle passt.
    static let brandSecondary = Color(hex: "#8B5CF6")!
    /// Dunkle Bühne für die laufende Aufnahme
    static let stage = Color(hex: "#15141A")!
    static let stageRaised = Color(hex: "#24222B")!

    /// Karte, auf der der Inhalt liegt – hebt sich vom farbigen Fensterhintergrund ab.
    static let cardBackground = Color(nsColor: .textBackgroundColor)
}

/// Farbiger Fensterhintergrund wie bei Arc: ein ruhiger Verlauf mit weichen Farbwolken.
/// Die Farbe folgt dem gewählten Bereich und wechselt sanft.
struct Backdrop: View {
    var tint: Color

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            // Von oben nach unten: kräftig in der Bereichsfarbe, unten weich ins Lila – sichtbar in der Seitenleiste
            LinearGradient(colors: [tint.opacity(0.5), tint.opacity(0.26), Theme.brandSecondary.opacity(0.22)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                Circle()
                    .fill(tint.opacity(0.45))
                    .frame(width: 520)
                    .blur(radius: 100)
                    .offset(x: -260, y: -260)
                Circle()
                    .fill(Theme.brandSecondary.opacity(0.28))
                    .frame(width: 460)
                    .blur(radius: 110)
                    .offset(x: -200, y: geo.size.height - 260)
                Circle()
                    .fill(Color(hex: "#FFC7A8")!.opacity(0.35))
                    .frame(width: 300)
                    .blur(radius: 90)
                    .offset(x: 60, y: geo.size.height * 0.45)
            }
        }
        .drawingGroup()
    }
}

/// Emoji auf einer weich eingefärbten Fläche – das Gesicht eines Bereichs.
struct EmojiBadge: View {
    let emoji: String
    var color: Color = .gray
    var size: CGFloat = 32

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.26), color.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(color.opacity(0.22), lineWidth: 0.5)
            )
    }
}

extension RecordingCategory {
    func badge(size: CGFloat = 32) -> EmojiBadge { EmojiBadge(emoji: displayEmoji, color: color, size: size) }
}

/// Umschalter mit gleitender Markierung – statt des grauen Standard-Segmentschalters.
struct PillTabs<Value: Hashable>: View {
    let items: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let selected = item.value == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = item.value }
                } label: {
                    Text(item.title)
                        .font(Theme.Font.small.weight(.semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.cardBackground)
                                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// Runder Knopf nur mit Symbol – für Nebenaktionen in Kopfzeilen und auf der dunklen Bühne.
struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var fill: Color = .primary.opacity(0.06)
    var foreground: Color = .primary
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(fill).opacity(hovering ? 1 : 0.8))
            .overlay(Circle().fill(Color.white.opacity(hovering ? 0.08 : 0)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onHover { hovering = $0 }
            .contentShape(Circle())
    }
}

/// Kleine Plakette für Metadaten (Datum, Dauer, App …)
struct MetaChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(Theme.Font.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
}

/// Suchfeld als Glasfläche auf dem farbigen Hintergrund
struct GlassSearchField: View {
    @Binding var text: String
    var prompt = "Suchen"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Font.small)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.m - 2)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(focused ? 0.75 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
