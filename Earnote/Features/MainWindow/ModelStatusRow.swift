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
            return ("Spracherkennung wird geladen", "Einmaliger Download", whisper.downloadProgress)
        }
        if whisper.preparing != nil {
            return ("Spracherkennung wird für deinen Mac vorbereitet",
                    "Einmalig, kann einige Minuten dauern. Aufnehmen geht trotzdem.", nil)
        }
        if localModel.isDownloading {
            return ("KI-Modell wird geladen", "Einmaliger Download", localModel.progress)
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
