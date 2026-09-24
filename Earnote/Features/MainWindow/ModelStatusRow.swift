import EarnoteCore
import EarnoteML
import SwiftUI

/// Zeigt, solange ein Modell geladen oder für diesen Mac vorbereitet wird – und sonst gar nichts.
/// Ohne diese Zeile wundern sich Neue beim ersten Start, warum die erste Notiz so lange braucht.
struct ModelStatusRow: View {
    @ObservedObject private var whisper = WhisperModelManager.shared
    @ObservedObject private var localModel = LocalModelManager.shared

    /// Was gerade passiert (nil = nichts zu tun); `progress` nil = Dauer unbekannt
    var status: (title: String, detail: String, progress: Double?)? {
        if whisper.downloading != nil {
            return (String(localized: "Spracherkennung wird geladen"), String(localized: "Einmaliger Download"), whisper.downloadProgress)
        }
        if whisper.preparing != nil {
            return (String(localized: "Spracherkennung wird für deinen Mac vorbereitet"),
                    String(localized: "Einmalig, kann einige Minuten dauern. Aufnehmen geht trotzdem."), nil)
        }
        if localModel.isDownloading {
            return (String(localized: "KI-Modell wird geladen"), String(localized: "Einmaliger Download"), localModel.progress)
        }
        return nil
    }

    var body: some View {
        if let status {
            HStack(spacing: 10) {
                if let progress = status.progress {
                    ProgressView(value: progress).frame(width: 70)
                } else {
                    ProgressView().controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.title).font(.callout)
                    Text(status.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(status.title). \(status.detail)")
        }
    }
}

/// Hinweis, solange eine Aufnahme verarbeitet wird. Wichtig, weil macOS beim Zuklappen schläft –
/// und die Verarbeitung dann mit schläft. Das kostet sonst unbemerkt eine halbe Stunde.
struct ProcessingHintRow: View {
    @Environment(ProcessingQueue.self) private var queue
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if queue.processingID == nil, queue.isWaitingForPower {
            WaitingForPowerRow(count: queue.pending.count, processNow: queue.processNow)
        } else if let id = queue.processingID, let recording = library.recording(id) {
            HStack(spacing: 10) {
                ProgressView(value: queue.progress[id] ?? 0).frame(width: 70)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(recording.status.label): \(recording.title)")
                        .font(.callout).lineLimit(1).truncationMode(.middle)
                    Text("Lass den Deckel offen – zugeklappt schläft der Mac und die Verarbeitung pausiert.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .accessibilityElement(children: .combine)
        }
    }
}

/// „Erst am Netzteil“: Die Aufnahmen warten, bis der Mac am Strom hängt – oder bis man es anders will.
private struct WaitingForPowerRow: View {
    let count: Int
    let processNow: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "powerplug")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if count == 1 {
                        Text("Eine Aufnahme wartet aufs Netzteil")
                    } else {
                        Text("\(count) Aufnahmen warten aufs Netzteil")
                    }
                }
                .font(.callout)
                Text("Die Verarbeitung beginnt, sobald der Mac am Strom hängt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Jetzt verarbeiten", action: processNow)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}
