import EarnoteCore
import SwiftUI

/// Klausur-Radar (Earnote Pro): alles Prüfungsrelevante eines Bereichs auf einer Seite – die Abschnitte
/// „Wichtig für die Klausur“/„Prüfungshinweise“ aller Notizen, neueste Vorlesung zuerst. Ohne KI-Anfrage.
struct ExamRadarView: View {
    let category: RecordingCategory
    @Environment(LibraryStore.self) private var library
    @State private var notes: [(id: UUID, title: String, date: Date, items: [String])] = []
    @State private var loaded = false
    @State private var showsPro = false

    var body: some View {
        List {
            if !notes.isEmpty {
                // Einsteiger wissen sonst nicht, woher die Punkte kommen
                Section {} footer: {
                    Text("Alles, was in deinen Notizen als prüfungsrelevant gilt – dazu, was du mit „Wichtig“ markiert hast. Neueste Vorlesung zuerst.")
                }
            }
            ForEach(notes, id: \.id) { note in
                Section {
                    ForEach(note.items, id: \.self) { item in
                        NoteContentView(markdown: item) { _ in }
                    }
                } header: {
                    // Ziel direkt statt `value:` – das Radar liegt per `isPresented` im Stapel, dort griff der Wert-Link nicht
                    NavigationLink {
                        RecordingDetailView(id: note.id)
                    } label: {
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
        .sheet(isPresented: $showsPro) { ProSheet(highlight: .mockExam) }
        .toolbar {
            // Oben, nicht unten: Unten liegen schon „Aufnehmen“ und die Tabs
            ToolbarItem(placement: .primaryAction) {
                // Ziel direkt: Das Radar liegt per `isPresented` im Stapel, ein weiteres `navigationDestination` griff dort nicht
                if Pro.isUnlocked || Pro.triesLeft(.mockExam) > 0 {
                    NavigationLink {
                        MockExamView(categoryID: category.id, allowStart: {
                            // Ein Probeversuch je gestellter Klausur, nicht je Öffnen der Seite
                            if Pro.use(.mockExam) { return true }
                            showsPro = true
                            return false
                        })
                    } label: {
                        Label("Probeklausur", systemImage: "graduationcap")
                    }
                } else {
                    Button("Probeklausur", systemImage: "graduationcap") { showsPro = true }
                }
            }
            if !notes.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: ExamRadar.markdown(title: String(localized: "Klausur-Radar: \(category.name)"),
                                                       notes: notes.map { ($0.title, $0.items) })) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
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
