import EarnoteCore
import SwiftUI

/// Das Transkript als Absätze mit Zeitmarke und Sprecher. Wird im Hintergrund geladen und nur sichtbar gerendert.
struct TranscriptView: View {
    @Environment(LibraryStore.self) private var library
    let recording: LibraryRecording
    /// Laufende Suche: Fundstellen hervorheben und zur ersten springen
    var searchText = ""

    @State private var paragraphs: [TranscriptParagraph] = []
    @State private var state: LoadState = .loading

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
                            DetailHeader(recording: recording)
                                .padding(.bottom, 6)
                            if let hits = hitCount, hits > 0 {
                                Text(hits == 1 ? "Eine Fundstelle" : "\(hits) Fundstellen")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(paragraphs) { paragraph in
                                TranscriptParagraphView(paragraph: paragraph, searchText: searchText)
                                    .id(paragraph.id)
                            }
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: searchText, initial: true) { _, _ in jumpToFirstHit(proxy) }
                    .onChange(of: paragraphs.count) { _, _ in jumpToFirstHit(proxy) }
                }
            }
        }
        // Neu laden, wenn die Verarbeitung ein Transkript geschrieben oder entfernt hat
        .task(id: "\(recording.id)|\(recording.statusRaw)") { await load() }
    }

    /// Anzahl der Fundstellen im ganzen Transkript (nil = keine Suche)
    private var hitCount: Int? {
        guard !SearchText.normalized(searchText).isEmpty else { return nil }
        return paragraphs.reduce(0) { $0 + SearchText.ranges(in: $1.text, query: searchText).count }
    }

    /// „Sprung zur Stelle“: zum ersten Absatz mit Treffer scrollen
    private func jumpToFirstHit(_ proxy: ScrollViewProxy) {
        guard !SearchText.normalized(searchText).isEmpty,
              let first = paragraphs.first(where: { SearchText.matches($0.text, query: searchText) }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(first.id, anchor: .top) }
    }

    private func load() async {
        let transcript = await library.transcript(recording.id)
        guard !Task.isCancelled else { return }
        if let transcript, !transcript.segments.isEmpty {
            paragraphs = TranscriptParagraph.group(transcript.segments, speakers: library.settings.speakerLabels)
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
    let paragraph: TranscriptParagraph
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(TimeFormat.clock(paragraph.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let speaker = paragraph.speaker {
                    Text(speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(SearchHighlight.attributed(paragraph.text, query: searchText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}
