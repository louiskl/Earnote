import EarnoteCore
import SwiftUI

/// Tab „Suche“: in Titeln, Notizen und Transkripten (Suche aus dem `LibraryStore`, wie am Mac).
struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var matches: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Suchen", systemImage: "magnifyingglass",
                                           description: Text("Titel, Notizen und Transkripte aller Aufnahmen."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { recording in
                        NavigationLink(value: recording.id) { RecordingRow(recording: recording) }
                    }
                }
            }
            .navigationTitle("Suche")
            .navigationDestination(for: UUID.self) { RecordingDetailView(id: $0) }
        }
        .searchable(text: $query, prompt: "Titel, Notizen, Transkripte")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            matches = await library.search(query)
        }
    }

    private var results: [Recording] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return library.recordings.filter { matches.contains($0.id) || $0.displayTitle.localizedStandardContains(needle) }
    }
}
