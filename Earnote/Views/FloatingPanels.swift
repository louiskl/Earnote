import AppKit
import EarnoteCore
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Schwebende Hinweise (z. B. "Call erkannt") oben rechts – ähnlich wie bei Notion.
@MainActor
final class FloatingPanels {
    static let shared = FloatingPanels()
    private var callPanel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func showCallPrompt(app appName: String, state: AppState) {
        hideCallPrompt(animated: false)
        let view = CallPromptView(appName: appName) { [weak self] category in
            state.startRecording(category: category, sourceApp: appName, byCall: true)
            self?.hideCallPrompt()
        } onDismiss: { [weak self] in
            self?.hideCallPrompt()
        }
        .environmentObject(state)

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.nonactivatingPanel, .borderless],
                                 backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 12))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        callPanel = panel
        NSSound(named: "Tink")?.play()

        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if !Task.isCancelled { self?.hideCallPrompt() }
        }
    }

    func hideCallPrompt(animated: Bool = true) {
        hideTask?.cancel()
        hideTask = nil
        guard let panel = callPanel else { return }
        callPanel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        } else {
            panel.orderOut(nil)
        }
    }
}

struct CallPromptView: View {
    @EnvironmentObject var app: AppState
    let appName: String
    var onRecord: (RecordingCategory?) -> Void
    var onDismiss: () -> Void
    @State private var categoryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.accent)
                    Image(systemName: "waveform").font(Theme.Font.heading).foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appName) erkannt").font(Theme.Font.body.weight(.semibold))
                    Text("Soll \(AppInfo.name) mitschreiben?").font(Theme.Font.small).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(Theme.Font.caption.weight(.semibold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(app.categories) { c in
                        Button { categoryID = c.id } label: { CategoryChip(category: c, selected: categoryID == c.id) }
                            .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Nicht jetzt", action: onDismiss).buttonStyle(SecondaryButtonStyle())
                Button {
                    onRecord(app.category(categoryID))
                } label: {
                    Label("Aufnahme starten", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if app.settings.showConsentReminder {
                Label("Denk daran, alle Teilnehmenden um Erlaubnis zu fragen.", systemImage: "hand.raised")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .onAppear {
            categoryID = app.settings.defaultCategoryID
                ?? app.categories.first(where: { $0.name == "Meeting" })?.id
                ?? app.categories.first?.id
        }
    }
}
