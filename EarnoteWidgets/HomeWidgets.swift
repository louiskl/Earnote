import AppIntents
import SwiftUI
import WidgetKit

// Widgets für Home- und Sperrbildschirm. Die Daten schreibt die App (`WidgetSnapshot`); ein Tipp öffnet die passende
// Stelle in Earnote (`EarnoteLink`), der Aufnahme-Knopf startet direkt (`StartRecordingIntent`).

private let brand = Color(red: 0.91, green: 0.27, blue: 0.23)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .preview : .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Die App meldet jede Änderung selbst (WidgetCenter) – hier reicht ein Nachsehen pro Stunde
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: .load())], policy: .after(.now.addingTimeInterval(3600))))
    }
}

// MARK: - Aufnehmen

/// Ein Tipp nimmt auf – auf dem Home-Bildschirm groß, auf dem Sperrbildschirm als runder Knopf
struct RecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.earnote.Earnote.widget.record", provider: SnapshotProvider()) { entry in
            RecordWidgetView(isRecording: entry.snapshot.isRecording)
                .containerBackground(for: .widget) { RecordBackground() }
        }
        .configurationDisplayName("Aufnehmen")
        .description("Startet mit einem Tipp eine Aufnahme.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

private struct RecordWidgetView: View {
    let isRecording: Bool
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Button(intent: StartRecordingIntent()) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: isRecording ? "waveform" : "record.circle")
                        .font(.system(size: 26, weight: .semibold))
                        .widgetAccentable()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Earnote nimmt auf" : "Mit Earnote aufnehmen")
        case .accessoryInline:
            Label(isRecording ? "Earnote nimmt auf" : "Mit Earnote aufnehmen",
                  systemImage: isRecording ? "waveform" : "record.circle")
                .widgetURL(EarnoteLink.record)
        default:
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "waveform").font(.headline).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                Spacer()
                Button(intent: StartRecordingIntent()) {
                    Image(systemName: isRecording ? "waveform" : "record.circle")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isRecording)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(isRecording ? "Nimmt auf" : "Aufnehmen")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct RecordBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 1, green: 0.48, blue: 0.36), brand], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Letzte Notiz

struct LatestNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.earnote.Earnote.widget.latest", provider: SnapshotProvider()) { entry in
            LatestNoteView(notes: entry.snapshot.notes)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Letzte Notizen")
        .description("Deine neuesten Notizen – ein Tipp öffnet sie.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct LatestNoteView: View {
    let notes: [WidgetSnapshot.Note]
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let first = notes.first {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(first.area ?? String(localized: "Letzte Notiz")).font(.caption2).foregroundStyle(.secondary)
                    Text(first.title).font(.headline).lineLimit(1).widgetAccentable()
                    if let preview = first.preview { Text(preview).font(.caption).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(EarnoteLink.recording(first.id))
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    Header(title: "Letzte Notizen")
                    ForEach(notes.prefix(3)) { note in
                        Link(destination: EarnoteLink.recording(note.id)) { NoteLine(note: note) }
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Header(title: "Letzte Notiz")
                    Text(first.title).font(.headline).lineLimit(3).layoutPriority(1)
                    if let preview = first.preview {
                        Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    if first.openTasks > 0 {
                        Label("\(first.openTasks)", systemImage: "checklist").font(.caption.bold()).foregroundStyle(brand)
                    }
                }
                .widgetURL(EarnoteLink.recording(first.id))
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "waveform").font(.title2).foregroundStyle(brand)
                Text("Noch keine Notiz").font(.caption).foregroundStyle(.secondary)
            }
            .widgetURL(EarnoteLink.record)
        }
    }
}

private struct NoteLine: View {
    let note: WidgetSnapshot.Note

    var body: some View {
        HStack(spacing: 8) {
            Text(note.emoji ?? "🎙️")
                .font(.caption)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.22), in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text(note.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(note.area ?? note.date.formatted(.dateTime.day().month().hour().minute()))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var color: Color {
        guard let hex = note.colorHex, let value = UInt64(hex.dropFirst(), radix: 16) else { return .gray }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Offene Aufgaben

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.earnote.Earnote.widget.tasks", provider: SnapshotProvider()) { entry in
            TasksView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(EarnoteLink.tasks)
        }
        .configurationDisplayName("Offene Aufgaben")
        .description("Aufgaben und Fristen aus deinen Notizen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct TasksView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Image(systemName: "checklist").font(.caption)
                    Text("\(snapshot.openTaskCount)").font(.title3.bold()).widgetAccentable()
                }
            }
        case .accessoryInline:
            Label("\(snapshot.openTaskCount) offene Aufgaben", systemImage: "checklist")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("\(snapshot.openTaskCount) offen", systemImage: "checklist").font(.caption2.bold()).widgetAccentable()
                ForEach(snapshot.tasks.prefix(2)) { Text("· \($0.text)").font(.caption).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Header(title: family == .systemSmall ? "Aufgaben" : "Offene Aufgaben")
                    Spacer()
                    Text("\(snapshot.openTaskCount)").font(.title2.bold()).fontDesign(.rounded).foregroundStyle(brand)
                }
                if snapshot.tasks.isEmpty {
                    Spacer()
                    Label("Alles erledigt", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(snapshot.tasks.prefix(family == .systemMedium ? 4 : 3)) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "circle").font(.caption2).foregroundStyle(brand)
                            Text(task.text).font(.caption).lineLimit(family == .systemMedium ? 1 : 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct Header: View {
    let title: LocalizedStringKey

    var body: some View {
        Label(title, systemImage: "waveform")
            .font(.caption.weight(.semibold))
            .foregroundStyle(brand)
            .textCase(.uppercase)
    }
}

extension WidgetSnapshot {
    /// Für die Widget-Galerie
    static var preview: WidgetSnapshot {
        var s = WidgetSnapshot()
        let id = UUID()
        s.notes = [
            .init(id: id, title: String(localized: "Eigenwerte und Eigenvektoren"), area: "Analysis II", emoji: "📐", colorHex: "#E8453B",
                  preview: String(localized: "Charakteristisches Polynom, Eigenräume, Diagonalisierbarkeit."), date: .now, openTasks: 2),
            .init(id: UUID(), title: String(localized: "Scheduling-Verfahren"), area: String(localized: "Betriebssysteme"), emoji: "🖥️",
                  colorHex: "#2563EB", preview: nil, date: .now, openTasks: 0),
        ]
        s.tasks = [.init(id: "1", recordingID: id, text: String(localized: "Übungsblatt 4 bis Freitag rechnen")),
                   .init(id: "2", recordingID: id, text: String(localized: "Klausurtermin am 12. Februar notieren"))]
        s.openTaskCount = 2
        return s
    }
}
