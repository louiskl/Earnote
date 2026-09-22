import AppKit
import SwiftUI

extension View {
    /// Meldet, ob das Fenster dieser Ansicht gerade zu sehen ist – nicht verdeckt, minimiert oder
    /// ausgeblendet. Damit hören Animationen auf, die niemand sieht; sie kosten sonst dauernd Strom.
    func onWindowVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibilityReader(onChange: action))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) { view.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if let window {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.report() }
                    }
            }
            report()
        }

        private func report() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            let action = onChange
            // Nicht mitten im Aufbau der Ansicht deren Zustand ändern
            Task { action(visible) }
        }
    }
}
