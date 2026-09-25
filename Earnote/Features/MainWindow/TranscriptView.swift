import EarnoteCore
import SwiftUI

/// Das Transkript als Absätze mit Zeitmarke und Sprecher. Wird im Hintergrund geladen und nur sichtbar gerendert.
struct TranscriptView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    let recording: LibraryRecording
    /// Laufende Suche: Fundstellen hervorheben und zur ersten springen
    var searchText = ""
    /// Blättern durch die Fundstellen (⌘G) – nil, wenn diese Ansicht nicht blättert
    var cursor: SearchCursor?
    /// Nebeneinander mit der Notiz: beim Abspielen zur laufenden Stelle scrollen
    var followsPlayback = false
    /// Titelzeile zeigen (nebeneinander steht sie schon über der Notiz)
    var showsHeader = true

    @State private var paragraphs: [TranscriptParagraph] = []
    @State private var state: LoadState = .loading
    /// Zu jeder Fundstelle der Absatz, in dem sie steht – in der Reihenfolge des Transkripts
    @State private var hits: [Int] = []

    private enum LoadState { case loading, loaded, missing }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Transkript wird geladen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing:
                if recording.isBusy || recording.status == .failed {
                    ProcessingStateView(recording: recording)
                } else {
                    ContentUnavailableView("Kein Transkript", systemImage: "text.alignleft",
                                           description: Text("Für diese Aufnahme gibt es kein Transkript."))
                }
            case .loaded:
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if showsHeader {
                                DetailHeader(recording: recording)
                                    .padding(.bottom, 6)
                            }
                            if !hits.isEmpty {
                                Text(hits.count == 1
                                     ? "Eine Fundstelle"
                                     : "Fundstelle \((cursor?.index ?? 0) + 1) von \(hits.count) · ⌘G")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(paragraphs.enumerated()), id: \.element.id) { index, paragraph in
                                // Der nächste Absatz beginnt dort, wo dieser endet – genauer geht es ohne Segmentzeiten nicht
                                TranscriptParagraphView(paragraph: paragraph, searchText: searchText,
                                                        end: index + 1 < paragraphs.count
                                                            ? paragraphs[index + 1].start : .greatestFiniteMagnitude)
                                    .id(paragraph.id)
                            }
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: searchText, initial: true) { _, _ in updateHits(proxy) }
                    .onChange(of: paragraphs.count) { _, _ in updateHits(proxy) }
                    // Weitersuchen (⌘G) im Menü zählt hoch, hier wird gescrollt
                    .onChange(of: cursor?.index) { _, _ in scrollToHit(proxy) }
                    .onChange(of: playingParagraph) { _, id in
                        guard followsPlayback, let id else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        // Neu laden, wenn die Verarbeitung ein Transkript geschrieben oder entfernt hat
        .task(id: "\(recording.id)|\(recording.statusRaw)") { await load() }
    }

    /// Absatz, der gerade läuft – zum Mitlesen neben der Notiz
    private var playingParagraph: Int? {
        guard player.isPlaying else { return nil }
        return paragraphs.last { $0.start <= player.currentTime }?.id
    }

    /// Neue Suche oder neues Transkript: Fundstellen zählen und zur ersten springen
    private func updateHits(_ proxy: ScrollViewProxy) {
        guard !SearchText.normalized(searchText).isEmpty else {
            hits = []
            cursor?.reset(count: 0)
            return
        }
        // Je Fundstelle ein Eintrag, damit „3 von 12“ und ⌘G dasselbe zählen
        hits = paragraphs.flatMap { paragraph in
            Array(repeating: paragraph.id, count: SearchText.ranges(in: paragraph.text, query: searchText).count)
        }
        cursor?.reset(count: hits.count)
        scrollToHit(proxy)
    }

    /// Zur gezählten Fundstelle scrollen
    private func scrollToHit(_ proxy: ScrollViewProxy) {
        let index = cursor?.index ?? 0
        guard hits.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(hits[index], anchor: .top) }
    }

    private func load() async {
        let transcript = await library.transcript(recording.id)
        guard !Task.isCancelled else { return }
        if let transcript, !transcript.segments.isEmpty {
            paragraphs = TranscriptParagraph.group(transcript.segments,
                                                   speakers: library.settings.speakerLabels || library.settings.detectSpeakers)
            state = .loaded
        } else {
            paragraphs = []
            state = .missing
        }
    }
}

/// Aufeinanderfolgende Segmente desselben Sprechers, höchstens eine Minute je Absatz
struct TranscriptParagraph: Identifiable {
    let id: Int
    let start: Double
    let speaker: String?
    let text: String

    static func group(_ segments: [TranscriptSegment], speakers: Bool) -> [TranscriptParagraph] {
        var result: [TranscriptParagraph] = []
        var texts: [String] = []
        var start = 0.0
        var speaker: String?
        func flush() {
            guard !texts.isEmpty else { return }
            result.append(TranscriptParagraph(id: result.count, start: start, speaker: speakers ? speaker : nil,
                                              text: texts.joined(separator: " ")))
            texts = []
        }
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if texts.isEmpty || (speakers && segment.speaker != speaker) || segment.start - start >= 60 {
                flush()
                start = segment.start
                speaker = segment.speaker
            }
            texts.append(text)
        }
        flush()
        return result
    }
}

private struct TranscriptParagraphView: View {
    @Environment(AudioPlayer.self) private var player
    let paragraph: TranscriptParagraph
    let searchText: String
    /// Ende des Absatzes – für die Hervorhebung der laufenden Stelle
    let end: TimeInterval

    var body: some View {
        let playing = player.isPlaying(from: paragraph.start, to: end)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                TimestampButton(seconds: paragraph.start)
                if let speaker = paragraph.speaker {
                    Text(speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(SearchHighlight.attributed(paragraph.text, query: searchText))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(playing ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
