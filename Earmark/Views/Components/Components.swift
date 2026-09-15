import SwiftUI

// MARK: - Stil

enum Theme {
    static let accent = Color(hex: "#FF5A4E")!        // Earmark-Rot
    static let accentSoft = Color(hex: "#FF5A4E")!.opacity(0.12)
    static let corner: CGFloat = 14
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07)))
            .contentShape(Rectangle())
    }
}

// MARK: - Bausteine

struct CategoryIcon: View {
    let category: RecordingCategory?
    var size: CGFloat = 28

    var body: some View {
        let color = category?.color ?? .gray
        Image(systemName: category?.symbol ?? "waveform")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.15)))
    }
}

struct CategoryChip: View {
    let category: RecordingCategory
    var selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbol).font(.system(size: 11, weight: .semibold))
            Text(category.name).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(selected ? .white : category.color)
        .background(Capsule().fill(selected ? category.color : category.color.opacity(0.13)))
        .contentShape(Capsule())
    }
}

struct StatusBadge: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 5) {
            switch recording.status {
            case .recording:
                Circle().fill(Theme.accent).frame(width: 7, height: 7)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            default:
                ProgressView().controlSize(.mini)
            }
            if recording.status != .done {
                Text(recording.status.isBusy && recording.progress > 0
                     ? "\(recording.status.label) · \(Int(recording.progress * 100)) %"
                     : recording.status.label)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

struct LevelMeter: View {
    var level: Float
    var color: Color = Theme.accent
    var bars = 24

    var body: some View {
        let db = level > 0 ? 20 * log10(level) : -80
        let normalized = max(0, min(1, (db + 55) / 50))
        HStack(spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Float(i) / Float(bars) < normalized ? color : Color.primary.opacity(0.1))
                    .frame(width: 4)
            }
        }
        .frame(height: 14)
        .animation(.linear(duration: 0.08), value: normalized)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool?
    let action: () -> Void
    var actionTitle = "Erlauben"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
            }
            Spacer()
            if granted == true {
                Label("Erlaubt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.system(size: 12, weight: .medium))
            } else {
                Button(actionTitle, action: action).buttonStyle(SecondaryButtonStyle())
            }
        }
        .card(padding: 12)
    }
}

extension View {
    func fixedSize() -> some View { fixedSize(horizontal: false, vertical: true) }
}

// MARK: - Markdown-Anzeige

/// Einfache Darstellung der Zusammenfassung (Überschriften, Listen, Checkboxen).
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                line(raw)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func line(_ raw: String) -> some View {
        let indent = CGFloat(raw.prefix { $0 == " " }.count / 2) * 18
        let l = raw.trimmingCharacters(in: .whitespaces)
        if l.isEmpty {
            Spacer().frame(height: 2)
        } else if l.hasPrefix("### ") {
            Text(inline(String(l.dropFirst(4)))).font(.system(size: 14, weight: .semibold)).padding(.top, 6)
        } else if l.hasPrefix("## ") {
            Text(inline(String(l.dropFirst(3)))).font(.system(size: 17, weight: .bold)).padding(.top, 12)
        } else if l.hasPrefix("# ") {
            Text(inline(String(l.dropFirst(2)))).font(.system(size: 21, weight: .bold))
        } else if l.hasPrefix("- [ ] ") || l.hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: l.hasPrefix("- [x]") ? "checkmark.square.fill" : "square")
                    .foregroundStyle(Theme.accent)
                Text(inline(String(l.dropFirst(6))))
            }
            .padding(.leading, indent)
        } else if l.hasPrefix("- ") || l.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(String(l.dropFirst(2))))
            }
            .padding(.leading, indent)
        } else if let r = l.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(l[..<r.upperBound]).trimmingCharacters(in: .whitespaces)).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(String(l[r.upperBound...])))
            }
            .padding(.leading, indent)
        } else if l.hasPrefix("> ") {
            Text(inline(String(l.dropFirst(2)))).foregroundStyle(.secondary).italic()
        } else {
            Text(inline(l))
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
