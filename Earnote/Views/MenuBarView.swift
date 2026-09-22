import EarnoteCore
import SwiftUI

struct MenuBarLabel: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @EnvironmentObject var meter: LiveMeter

    var body: some View {
        // Das Symbol in der Menüleiste ist für viele der einzige Einstieg. Ohne eigene Beschriftung
        // liest VoiceOver den Namen des Symbols vor („waveform“) statt des Zustands.
        if recorder.isRecording {
            HStack(spacing: 4) {
                Image(systemName: recorder.isPaused ? "pause.circle.fill" : "record.circle.fill")
                Text(TimeFormat.duration(meter.elapsed)).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recorder.isPaused ? Text("\(AppInfo.name): Aufnahme pausiert")
                                                  : Text("\(AppInfo.name): Aufnahme läuft"))
            .accessibilityValue(Text(TimeFormat.duration(meter.elapsed)))
        } else if library.recordings.contains(where: { $0.status.isBusy }) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .accessibilityLabel("\(AppInfo.name): Aufnahme wird verarbeitet")
        } else {
            Image(systemName: "waveform")
                .accessibilityLabel("\(AppInfo.name): bereit zum Aufnehmen")
        }
    }
}

/// Das Fenster aus der Menüleiste: aufnehmen, sehen was läuft, ins Hauptfenster wechseln.
/// Bewusst schmal (300 pt) – lange Bereichs- und Mikrofonnamen werden gekürzt, nie umgebrochen.
struct MenuBarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecordingController.self) private var recorder
    @Environment(\.openWindow) private var openWindow

    /// Bereich, in dem die nächste Aufnahme landet – bis zur ersten Wahl gilt der Standardbereich
    @State private var chosenCategoryID: UUID?
    @State private var hasChosen = false

    private static let width: CGFloat = 300

    private var activeCategory: RecordingCategory? {
        library.category(hasChosen ? chosenCategoryID : library.settings.defaultCategoryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if !recorder.isRecording { CalendarEventLine() }
            RecordControl(categoryID: activeCategory?.id, maxNameLength: 26)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tint(activeCategory?.tint ?? .accentColor)
            if recorder.isRecording {
                LiveSummary(meter: recorder.meter, isPaused: recorder.isPaused,
                            categoryName: activeCategoryName)
                    .tint(activeCategory?.tint ?? .accentColor)
            } else {
                categoryPicker
                MicrophoneChoiceMenu(maxNameLength: 26)
                    .labelsHidden()
            }
            if !recorder.isRecording { recentNotes }
            ModelStatusRow()
            Divider()
            Button("Hauptfenster öffnen") { MainWindowOpener.showOrOpen(openWindow) }
                .buttonStyle(.link)
            HStack {
                SettingsLink { Text("Einstellungen …") }
                    .buttonStyle(.link)
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
            }
        }
        .lineLimit(1)
        .padding(14)
        .frame(width: Self.width)
    }

    /// Bereiche direkt wählbar – ein Tipp genügt, kein Umweg über ein Menü.
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            noCategoryRow
            ForEach(library.categories) { category in
                let selected = activeCategory?.id == category.id
                Button {
                    chosenCategoryID = category.id
                    hasChosen = true
                } label: {
                    HStack(spacing: 8) {
                        CategoryBadge(emoji: category.emoji, symbol: category.symbol,
                                      tint: category.tint, size: 18)
                        Text(category.name)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(category.tint)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? category.tint.opacity(0.14) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    /// „Ohne Bereich“: Die Aufnahme steht dann nur unter „Alle Aufnahmen“ und kann später einsortiert werden.
    private var noCategoryRow: some View {
        let selected = activeCategory == nil
        return Button {
            chosenCategoryID = nil
            hasChosen = true
        } label: {
            HStack(spacing: 8) {
                CategoryBadge(emoji: nil, symbol: "tray", tint: .secondary, size: 18)
                Text("Ohne Bereich")
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.secondary.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Die drei jüngsten Aufnahmen – ein Klick öffnet die Notiz im Hauptfenster.
    /// Nach einer Vorlesung ist genau das der Weg: Menüleiste, Titel, lesen.
    @ViewBuilder private var recentNotes: some View {
        let recent = Array(library.recordings.prefix(3))
        if !recent.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Zuletzt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(recent) { recording in
                    Button {
                        MainWindowOpener.showOrOpen(openWindow)
                        NotificationCenter.default.post(name: .showRecording, object: recording.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(recording.displayTitle)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            if recording.status.isBusy {
                                ProgressView().controlSize(.small)
                            } else if recording.taskCount > 0 {
                                Text("\(recording.taskCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .help("Offene Aufgaben")
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Label(AppInfo.name, systemImage: "waveform")
                .font(.headline)
            Spacer()
            if let call = recorder.detector.activeCallApp, !recorder.isRecording {
                Text(call)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeCategoryName: String? {
        guard let id = recorder.activeRecordingID, let recording = library.recording(id) else { return nil }
        return library.category(recording.categoryID)?.name
    }
}

/// Während der Aufnahme: Laufzeit, Pegel und Bereich – kompakt.
private struct LiveSummary: View {
    @ObservedObject var meter: LiveMeter
    let isPaused: Bool
    let categoryName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isPaused ? "Pausiert" : "Aufnahme läuft")
                    .font(.subheadline)
                    .foregroundStyle(isPaused ? .secondary : .primary)
                Spacer()
                Text(TimeFormat.duration(meter.elapsed))
                    .font(.title3.monospacedDigit())
            }
            Gauge(value: MainWindowFormat.level(max(meter.mic, meter.system))) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .opacity(isPaused ? 0.4 : 1)
                .accessibilityLabel("Pegel")
            if let categoryName {
                Text(categoryName)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
