import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var app = AppState.shared
    @ObservedObject var meter = AppState.shared.meter

    var body: some View {
        if app.isRecording {
            HStack(spacing: 4) {
                Image(systemName: app.isPaused ? "pause.circle.fill" : "record.circle.fill")
                Text(TimeFormat.duration(meter.elapsed)).monospacedDigit()
            }
        } else if app.recordings.contains(where: { $0.status.isBusy }) {
            Image(systemName: "waveform.badge.magnifyingglass")
        } else {
            Image(systemName: "waveform")
        }
    }
}

/// Das Fenster aus der Menüleiste: bewusst reduziert – aufnehmen, sehen was läuft, zur letzten Notiz springen.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var categoryID: UUID?

    private var chosenCategory: RecordingCategory? {
        app.category(categoryID) ?? app.category(app.settings.defaultCategoryID) ?? app.categories.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header

            if app.isRecording {
                MenuRecordingStage()
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            } else {
                startSection
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }

            processing
            recent

            Button { open(nil) } label: {
                HStack {
                    Text("\(AppInfo.name) öffnen").font(Theme.Font.small.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s + 1)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Space.l - 2)
        .frame(width: 300)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.isRecording)
        .onAppear { categoryID = categoryID ?? chosenCategory?.id }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Text(AppInfo.name.lowercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
            if let call = app.detector.activeCallApp, !app.isRecording {
                Label(call, systemImage: "phone.fill")
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                    .lineLimit(1)
            }
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(RoundIconButtonStyle(size: 24, fill: .clear, foreground: .secondary))
                .help("Einstellungen")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(RoundIconButtonStyle(size: 24, fill: .clear, foreground: .secondary))
                .help("\(AppInfo.name) beenden")
        }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            Button {
                app.startRecording(category: chosenCategory, sourceApp: app.detector.activeCallApp)
            } label: {
                HStack(spacing: Theme.Space.s) {
                    ZStack {
                        Circle().fill(.white.opacity(0.3)).frame(width: 20, height: 20)
                        Circle().fill(.white).frame(width: 9, height: 9)
                    }
                    Text("Aufnahme starten").font(Theme.Font.body.weight(.semibold))
                    Spacer()
                    Text(chosenCategory.map { "\($0.displayEmoji) \($0.name)" } ?? "")
                        .font(Theme.Font.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent, Color(hex: "#FF7A59")!], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 3)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverLift(1.015)

            WrapLayout(spacing: 6) {
                ForEach(app.categories) { c in
                    let selected = chosenCategory?.id == c.id
                    Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { categoryID = c.id } } label: {
                        HStack(spacing: 4) {
                            Text(c.displayEmoji).font(.system(size: 12))
                            Text(c.name).font(Theme.Font.caption.weight(selected ? .semibold : .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 4)
                        .foregroundStyle(selected ? c.color : .primary)
                        .background(Capsule().fill(selected ? c.color.opacity(0.14) : Color.primary.opacity(0.05)))
                        .overlay(Capsule().strokeBorder(selected ? c.color.opacity(0.4) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var processing: some View {
        if let busy = app.recordings.first(where: { $0.status.isBusy }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Space.s) {
                    Text("✍️")
                    Text(busy.status == .summarizing ? "Notizen werden geschrieben" : busy.status.label)
                        .font(Theme.Font.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(busy.progress * 100)) %")
                        .font(Theme.Font.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                ProgressLine(progress: busy.progress, color: app.category(busy.categoryID)?.color ?? Theme.accent)
            }
            .padding(Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .onTapGesture { open(busy.id) }
        }
    }

    @ViewBuilder private var recent: some View {
        let items = Array(app.recordings.filter { $0.id != app.activeRecordingID && $0.status == .done }.prefix(3))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("ZULETZT").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.Space.s).padding(.bottom, 2)
                ForEach(items) { r in
                    MenuRecentRow(recording: r) { open(r.id) }
                }
            }
        }
    }

    private func open(_ id: UUID?) {
        if let id { app.selection = id }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuRecentRow: View {
    @EnvironmentObject var app: AppState
    let recording: Recording
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s + 2) {
                Text(app.category(recording.categoryID)?.displayEmoji ?? "🎙️").font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(recording.displayTitle).font(Theme.Font.caption.weight(.semibold)).lineLimit(1)
                    Text(recording.startedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if recording.taskCount > 0 {
                    Text("\(recording.taskCount) ☐").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Dunkle Aufnahme-Bühne im Kleinen
private struct MenuRecordingStage: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var meter = AppState.shared.meter

    var body: some View {
        let category = app.category(app.activeRecording?.categoryID)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                if app.isPaused {
                    Image(systemName: "pause.fill").font(.system(size: 10)).foregroundStyle(.orange)
                } else {
                    PulsingDot(size: 6)
                }
                Text(app.isPaused ? "Pausiert" : (category.map { "\($0.displayEmoji) \($0.name)" } ?? "Aufnahme läuft"))
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                Text(TimeFormat.duration(meter.elapsed))
                    .font(Theme.Font.number(22))
                    .foregroundStyle(.white.opacity(app.isPaused ? 0.5 : 1))
                    .contentTransition(.numericText())
            }
            Waveform(level: max(meter.mic, meter.system), color: category?.color ?? Theme.accent, bars: 34, height: 22, muted: app.isPaused)
                .frame(maxWidth: .infinity)
            LiveTranscriptView(style: .menu)
            HStack(spacing: Theme.Space.s) {
                Button("Verwerfen") { app.cancelRecording() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                PauseButton(compact: true)
                    .buttonStyle(RoundIconButtonStyle(size: 34, fill: .white.opacity(0.12), foreground: .white))
                Button { app.stopRecording() } label: {
                    Label("Stoppen", systemImage: "stop.fill").font(Theme.Font.small.weight(.semibold))
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Space.m + 2)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.stageRaised, Theme.stage], startPoint: .top, endPoint: .bottom))
        )
        .overlay(alignment: .top) {
            Circle().fill((category?.color ?? Theme.accent).opacity(app.isPaused ? 0.05 : 0.25))
                .frame(width: 200, height: 120).blur(radius: 50).offset(y: -30)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
