import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var app = AppState.shared
    @ObservedObject var meter = AppState.shared.meter

    var body: some View {
        if app.isRecording {
            HStack(spacing: 4) {
                Image(systemName: "record.circle.fill")
                Text(TimeFormat.duration(meter.elapsed)).monospacedDigit()
            }
        } else if app.recordings.contains(where: { $0.status.isBusy }) {
            Image(systemName: "waveform.badge.magnifyingglass")
        } else {
            Image(systemName: "waveform")
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var meter = AppState.shared.meter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Earmark").font(.system(size: 14, weight: .bold))
                Spacer()
                if let call = app.detector.activeCallApp {
                    Label(call, systemImage: "phone.fill").font(.system(size: 11)).foregroundStyle(.green).lineLimit(1)
                }
            }

            if app.isRecording {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(Theme.accent).frame(width: 9, height: 9)
                        Text(app.activeRecording?.title ?? "Aufnahme").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text(TimeFormat.duration(meter.elapsed)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    HStack { Image(systemName: "mic.fill").frame(width: 16); LevelMeter(level: meter.mic, bars: 26) }
                    if app.activeRecording?.hasSystemAudio == true {
                        HStack { Image(systemName: "speaker.wave.2.fill").frame(width: 16); LevelMeter(level: meter.system, color: .blue, bars: 26) }
                    }
                    HStack {
                        Button("Verwerfen") { app.cancelRecording() }.buttonStyle(SecondaryButtonStyle())
                        Button { app.stopRecording() } label: {
                            Label("Stoppen & auswerten", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .card(padding: 12)
            } else {
                Text("Aufnahme starten").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(app.categories) { c in
                        Button { app.startRecording(category: c, sourceApp: app.detector.activeCallApp) } label: {
                            HStack(spacing: 8) {
                                CategoryIcon(category: c, size: 26)
                                Text(c.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let recent = Array(app.recordings.filter { $0.id != app.activeRecordingID }.prefix(4))
            if !recent.isEmpty {
                Divider()
                Text("Zuletzt").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(recent) { r in
                    Button { open(r.id) } label: {
                        HStack(spacing: 8) {
                            CategoryIcon(category: app.category(r.categoryID), size: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.summaryTitle ?? r.title).font(.system(size: 12)).lineLimit(1)
                                if r.status == .done {
                                    Text(r.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                } else {
                                    StatusBadge(recording: r)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            HStack {
                Button("Earmark öffnen") { open(nil) }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Earmark beenden")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func open(_ id: UUID?) {
        if let id { app.selection = id }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
