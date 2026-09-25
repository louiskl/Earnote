import EarnoteCore
import SwiftUI

/// Klausur-Radar (Earnote Pro): alles Prüfungsrelevante eines Bereichs auf einer Seite – die Abschnitte
/// „Wichtig für die Klausur“/„Prüfungshinweise“ aller Notizen, neueste Vorlesung zuerst. Ohne KI-Anfrage.
struct ExamRadarView: View {
    let category: RecordingCategory
    @Environment(LibraryStore.self) private var library
    @State private var notes: [(id: UUID, title: String, date: Date, items: [String])] = []
    @State private var loaded = false

    var body: some View {
        List {
            ForEach(notes, id: \.id) { note in
                Section {
                    ForEach(note.items, id: \.self) { item in
                        Label {
                            NoteContentView(markdown: item) { _ in }
                        } icon: {
                            Image(systemName: "scope").foregroundStyle(.tint)
                        }
                    }
                } header: {
                    NavigationLink(value: note.id) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(note.title).multilineTextAlignment(.leading)
                            Spacer()
                            Text(note.date, format: .dateTime.day().month()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .paper()
        .overlay {
            if loaded && notes.isEmpty {
                ContentUnavailableView {
                    Label("Noch nichts für die Klausur", systemImage: "scope")
                } description: {
                    Text("Tippe während der Vorlesung auf „Wichtig“ – auch auf dem Sperrbildschirm. Earnote sammelt hier alles, was die Lehrkraft als prüfungsrelevant betont hat.")
                }
            }
        }
        .navigationTitle("Klausur-Radar")
        .navigationSubtitle(category.name)
        .toolbar {
            if !notes.isEmpty {
                ShareLink(item: ExamRadar.markdown(title: String(localized: "Klausur-Radar: \(category.name)"),
                                                   notes: notes.map { ($0.title, $0.items) })) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        var found: [(id: UUID, title: String, date: Date, items: [String])] = []
        let recordings = library.recordings
            // Übersichten eines Bereichs (ohne Ton, Dauer 0) wiederholen nur, was in den Vorlesungen steht
            .filter { $0.categoryID == category.id && $0.status == .done && $0.duration >= 1 }
            .sorted { $0.startedAt > $1.startedAt }
        for recording in recordings {
            guard let note = await library.summary(recording.id) else { continue }
            let items = ExamRadar.items(in: note.markdown)
            if !items.isEmpty { found.append((recording.id, note.title, recording.startedAt, items)) }
        }
        notes = found
        loaded = true
    }
}
