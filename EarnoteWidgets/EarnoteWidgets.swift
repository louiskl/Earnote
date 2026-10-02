import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Widget-Erweiterung der iPhone-App: Live-Aktivität der Aufnahme und das Steuerelement „Aufnehmen“.
@main
struct EarnoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
        StartRecordingControl()
        RecordWidget()
        LatestNoteWidget()
        TasksWidget()
    }
}

private let brand = Color(red: 0.91, green: 0.27, blue: 0.23)

/// Sperrbildschirm und Dynamic Island, solange aufgenommen wird
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Ruhig und schmal: links Zeit und Pegel, rechts die Knöpfe – kein Symbol und keine Überschrift, die sich
            // neben drei Knöpfen nur quetschen würden (Sperrbildschirm, 27.09. am Gerät durchgesehen)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Elapsed(state: context.state, alignment: .leading)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(context.state.isPaused ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Levels(levels: context.state.levels).frame(height: 16)
                }
                Controls(state: context.state)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(context.state.isPaused ? "Earnote, pausiert" : "Earnote nimmt auf")
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RecordingIcon(isPaused: context.state.isPaused).font(.title2).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Elapsed(state: context.state)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .fontDesign(.rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 72, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 6) {
                        Text(context.attributes.categoryName ?? String(localized: "Aufnahme")).font(.headline).lineLimit(1)
                        Levels(levels: context.state.levels).frame(height: 18)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Controls(state: context.state).padding(.top, 4)
                }
            } compactLeading: {
                RecordingIcon(isPaused: context.state.isPaused)
            } compactTrailing: {
                Elapsed(state: context.state).monospacedDigit().lineLimit(1).frame(width: 44, alignment: .trailing)
            } minimal: {
                RecordingIcon(isPaused: context.state.isPaused)
            }
            .keylineTint(brand)
        }
    }
}

private struct RecordingIcon: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle")
            .foregroundStyle(brand)
            .accessibilityLabel(isPaused ? "Pausiert" : "Nimmt auf")
    }
}

/// Pegel als ruhige Balken – die neuesten rechts
private struct Levels: View {
    let levels: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(brand.opacity(0.4 + 0.6 * Double(index + 1) / Double(max(1, levels.count))))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 16 * level))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Mitlaufende Uhr – bei Pause steht sie
private struct Elapsed: View {
    let state: RecordingActivityAttributes.ContentState
    var alignment: TextAlignment = .trailing

    var body: some View {
        if let paused = state.pausedElapsed {
            Text(Duration.seconds(paused).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text(timerInterval: state.countingSince...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(alignment)
        }
    }
}

private struct Controls: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            if state.canMark && !state.isPaused {
                Button(intent: MarkImportantIntent()) {
                    Label("Wichtig", systemImage: state.marks > 0 ? "star.fill" : "star").labelStyle(.iconOnly)
                }
                .tint(.orange)
            }
            Button(intent: TogglePauseRecordingIntent()) {
                Label(state.isPaused ? "Fortsetzen" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(.primary)
            Button(intent: StopRecordingIntent()) {
                Label("Stopp", systemImage: "stop.fill").labelStyle(.iconOnly)
            }
            .tint(brand)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }
}

/// Kontrollzentrum, Sperrbildschirm, Action-Taste: „Aufnehmen“ mit einem Tipp
struct StartRecordingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.earnote.Earnote.record") {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Aufnehmen", systemImage: "record.circle")
            }
        }
        .displayName("Earnote-Aufnahme")
        .description("Startet eine Aufnahme in Earnote.")
    }
}
