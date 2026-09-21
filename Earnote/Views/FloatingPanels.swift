import AppKit
import EarnoteCore
import SwiftUI

/// Der Hinweis „Call erkannt“ als flache Pille oben auf dem Bildschirm, auf dem gerade gearbeitet wird.
/// Er nimmt nie den Fokus, verschwindet nach 20 Sekunden von selbst und lässt sich mit Esc schließen.
@MainActor
final class FloatingPanels {
    static let shared = FloatingPanels()
    private var callPanel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// So lange bleibt der Hinweis stehen, wenn niemand reagiert.
    private static let visibleSeconds: UInt64 = 20

    func showCallPrompt(app appName: String, state: AppState) {
        hideCallPrompt(animated: false)
        let view = CallPromptView(appName: appName) { [weak self] in
            state.startRecording(category: state.category(state.settings.defaultCategoryID),
                                 sourceApp: appName, byCall: true)
            self?.hideCallPrompt()
        } onDismiss: { [weak self] in
            self?.hideCallPrompt()
        }

        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: false)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        // Schlüsselfenster werden, ohne die App nach vorn zu holen (dafür ist ein nichtaktivierendes
        // Panel da): Erst dann sieht der Hauptknopf aktiv aus und ⏎ bzw. ⎋ wirken.
        panel.makeKey()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.2
            panel.animator().alphaValue = 1
        }
        callPanel = panel

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            if !Task.isCancelled { self?.hideCallPrompt() }
        }
    }

    /// Waagerecht mittig, auf 10 % der Höhe unter der Menüleiste – auf dem Bildschirm mit der Maus.
    private func origin(for size: CGSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - frame.height * 0.10 - size.height
        return NSPoint(x: x.rounded(), y: min(y, frame.maxY - size.height - 8).rounded())
    }

    func hideCallPrompt(animated: Bool = true) {
        hideTask?.cancel()
        hideTask = nil
        guard let panel = callPanel else { return }
        callPanel = nil
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

/// Ein Hinweis, der ins Auge springt: Logo, klare Ansage, ein Knopf im Earnote-Rot.
/// Bewusst eine Zeile hoch, damit nichts umbricht.
struct CallPromptView: View {
    let appName: String
    var onRecord: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AppMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("\(appName)-Call erkannt")
                    .font(.headline)
                    .truncationMode(.middle)
                Text("Soll \(AppInfo.name) mitschreiben?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Begründete Ausnahme von „Systemknöpfe statt eigener“ (Guidelines 14):
            // Dieses Fenster erscheint, während eine andere App vorn ist. Ein nichtaktivierendes
            // Panel kann dann nicht Schlüsselfenster sein – macOS zeichnet Systemknöpfe darin grau,
            // also ausgerechnet den Knopf, der mitten im Call sofort erkennbar sein muss.
            Button("Mitschreiben", action: onRecord)
                .buttonStyle(.plain)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Brand.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .keyboardShortcut(.defaultAction)
            Button("Nicht jetzt", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 560)
        // Ein schwebendes Fenster braucht seinen eigenen Hintergrund – dafür das Systemmaterial,
        // damit er sich wie Spotlight und die Menüleisten-Fenster von macOS verhält.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onExitCommand(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(appName)-Call erkannt")
    }
}

/// Das Earnote-Zeichen: Wellenform im Markenrot
private struct AppMark: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.gradient))
            .accessibilityHidden(true)
    }
}
