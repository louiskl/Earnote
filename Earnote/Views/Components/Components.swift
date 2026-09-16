import EarnoteCore
import SwiftUI

/// Hauptaktion: gefüllt, mit feinem Verlauf und Lichtkante. Beim Drücken federt sie kurz ein.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.body.weight(.semibold))
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s + 1)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(hovering ? 1 : 0.94), color.opacity(0.82)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: color.opacity(configuration.isPressed ? 0.1 : 0.32), radius: 8, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// Nebenaktion: nur eine Fläche, die beim Darüberfahren sichtbar wird.
struct SecondaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.body.weight(.medium))
            .padding(.horizontal, Theme.Space.m + 2)
            .padding(.vertical, Theme.Space.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.1 : 0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
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
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(color.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                            .strokeBorder(color.opacity(0.18), lineWidth: 0.5)
                    )
            )
    }
}

struct CategoryChip: View {
    let category: RecordingCategory
    var selected: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs + 2) {
            Image(systemName: category.symbol).font(.system(size: 10, weight: .semibold))
            Text(category.name).font(Theme.Font.caption.weight(.medium))
        }
        .padding(.horizontal, Theme.Space.s + 2)
        .padding(.vertical, Theme.Space.xs + 1)
        .foregroundStyle(selected ? .white : category.color)
        .background(Capsule().fill(selected ? AnyShapeStyle(category.color) : AnyShapeStyle(category.color.opacity(0.12))))
        .contentShape(Capsule())
    }
}

/// Status einer Aufnahme als kleine Plakette.
struct StatusBadge: View {
    @EnvironmentObject var app: AppState
    let recording: Recording

    var body: some View {
        switch recording.status {
        case .done:
            StatusPill(text: "Fertig", color: .green)
        case .failed:
            StatusPill(text: "Problem", color: .orange)
        case .recording:
            StatusPill(text: app.isPaused ? "Pausiert" : "Aufnahme läuft",
                       color: Theme.accent, animated: !app.isPaused)
        default:
            StatusPill(text: recording.progress > 0
                       ? "\(recording.status.label) · \(Int(recording.progress * 100)) %"
                       : recording.status.label,
                       color: Theme.accent, animated: true)
        }
    }
}

/// Pegelanzeige – zeichnet die Wellenform aus dem DesignSystem.
struct LevelMeter: View {
    var level: Float
    var color: Color = Theme.accent
    var bars = 24
    var muted = false

    var body: some View {
        Waveform(level: level, color: color, bars: bars, height: 18, muted: muted)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.Font.heading)
            if let subtitle { Text(subtitle).font(Theme.Font.caption).foregroundStyle(.secondary) }
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(granted == true ? Color.green : Theme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(granted == true ? Color.green.opacity(0.12) : Theme.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.small.weight(.semibold))
                Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary).fittingHeight()
            }
            Spacer()
            if granted == true {
                Label("Erlaubt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(Theme.Font.caption.weight(.medium))
            } else {
                Button(actionTitle, action: action).buttonStyle(SecondaryButtonStyle())
            }
        }
        .card(padding: Theme.Space.m)
    }
}

// MARK: - Markdown-Anzeige

/// Stellt die Notizen als Dokument dar: ruhige Typografie, klare Absatzhierarchie,
/// Aufgaben als echte Haken zum Abhaken.
struct MarkdownView: View {
    let markdown: String
    /// Wird mit der geänderten Markdown-Fassung aufgerufen, wenn ein Haken gesetzt wird.
    var onToggleTask: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { index, raw in
                line(raw, at: index)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func line(_ raw: String, at index: Int) -> some View {
        let indent = CGFloat(raw.prefix { $0 == " " }.count / 2) * 18
        let l = raw.trimmingCharacters(in: .whitespaces)
        if l.isEmpty {
            Spacer().frame(height: Theme.Space.xs)
        } else if l.hasPrefix("### ") {
            Text(inline(String(l.dropFirst(4))))
                .font(Theme.Font.heading)
                .padding(.top, Theme.Space.s)
        } else if l.hasPrefix("## ") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Divider().opacity(0.5)
                Text(inline(String(l.dropFirst(3))))
                    .font(.system(.title3, weight: .semibold))
            }
            .padding(.top, Theme.Space.l)
        } else if l.hasPrefix("# ") {
            Text(inline(String(l.dropFirst(2)))).font(Theme.Font.title)
        } else if l.hasPrefix("- [ ] ") || l.hasPrefix("- [x] ") {
            let done = l.hasPrefix("- [x]")
            Button {
                toggleTask(at: index, done: done)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? Theme.accent : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(inline(String(l.dropFirst(6))))
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onToggleTask == nil)
            .padding(.leading, indent)
        } else if l.hasPrefix("- ") || l.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
                    .padding(.top, 6)
                Text(inline(String(l.dropFirst(2))))
            }
            .padding(.leading, indent)
        } else if let r = l.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(String(l[..<r.upperBound]).trimmingCharacters(in: .whitespaces))
                    .foregroundStyle(.secondary).monospacedDigit()
                Text(inline(String(l[r.upperBound...])))
            }
            .padding(.leading, indent)
        } else if l.hasPrefix("> ") {
            HStack(spacing: Theme.Space.m) {
                Capsule().fill(Theme.accent.opacity(0.4)).frame(width: 2)
                Text(inline(String(l.dropFirst(2)))).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(inline(l)).lineSpacing(4)
        }
    }

    private func toggleTask(at index: Int, done: Bool) {
        var lines = markdown.components(separatedBy: "\n")
        guard index < lines.count else { return }
        lines[index] = done
            ? lines[index].replacingOccurrences(of: "- [x] ", with: "- [ ] ")
            : lines[index].replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        onToggleTask?(lines.joined(separator: "\n"))
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
