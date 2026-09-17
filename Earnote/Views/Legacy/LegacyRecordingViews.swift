import EarnoteCore
import SwiftUI

// Übergang bis Phase 2b: Teile des alten Hauptfensters, die das Menüleisten-Fenster noch nutzt.

extension Notification.Name {
    /// Einrichtungsassistent erneut zeigen (aus den Einstellungen)
    static let showOnboarding = Notification.Name("\(AppInfo.bundleIdentifier).showOnboarding")
}

struct LiveTranscriptView: View {
    enum Style { case stage, compact, menu }

    @EnvironmentObject var live: LiveTranscript
    var style: Style = .compact

    var body: some View {
        let onDark = style != .compact
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    (Text(live.settled)
                        .foregroundColor(onDark ? .white.opacity(0.92) : .primary)
                     + Text(live.settled.isEmpty ? "" : " ")
                     + Text(live.volatile)
                        .foregroundColor(onDark ? .white.opacity(0.45) : .secondary))
                        .font(font)
                        .lineSpacing(style == .stage ? 6 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("ende")
                }
            }
            .onChange(of: live.text) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("ende", anchor: .bottom) }
            }
        }
        .frame(maxHeight: style == .stage ? .infinity : (style == .menu ? 52 : 110))
        // Oben weich ausblenden, damit älterer Text nicht hart abgeschnitten wirkt
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                     .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: style == .stage ? .center : .leading) {
            if live.isEmpty {
                Text(live.unavailable ?? (style == .stage ? "Sobald jemand spricht, erscheint hier die Live-Mitschrift." : "Live-Mitschrift erscheint hier …"))
                    .font(style == .stage ? Theme.Font.body : Theme.Font.caption)
                    .foregroundStyle(onDark ? AnyShapeStyle(Color.white.opacity(0.35)) : AnyShapeStyle(.tertiary))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var font: Font {
        switch style {
        case .stage: return .system(size: 20, weight: .medium)
        case .compact: return Theme.Font.small
        case .menu: return Theme.Font.caption
        }
    }
}

/// Pausieren / Fortsetzen der laufenden Aufnahme.
struct PauseButton: View {
    @EnvironmentObject var app: AppState
    var compact = false

    var body: some View {
        Button { app.togglePause() } label: {
            if compact {
                Image(systemName: app.isPaused ? "play.fill" : "pause.fill")
            } else {
                Label(app.isPaused ? "Fortsetzen" : "Pause", systemImage: app.isPaused ? "play.fill" : "pause.fill")
            }
        }
        .help(app.isPaused ? "Aufnahme fortsetzen (⇧⌘P)" : "Aufnahme pausieren (⇧⌘P)")
    }
}
