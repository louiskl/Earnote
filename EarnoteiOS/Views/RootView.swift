import SwiftUI

/// Feste Wurzel: drei Tabs, jeder mit eigenem Navigationsstapel. Die laufende Aufnahme sitzt später
/// im `tabViewBottomAccessory` – wie „Jetzt läuft“ in Musik.
struct RootView: View {
    enum Tab: Hashable { case recordings, learn, search }

    @SceneStorage("tab") private var tab: Tab = .recordings
    @State private var query = ""

    var body: some View {
        TabView(selection: $tab) {
            SwiftUI.Tab("Aufnahmen", systemImage: "waveform", value: .recordings) {
                NavigationStack {
                    ContentUnavailableView("Noch keine Aufnahme", systemImage: "waveform",
                                           description: Text("Tippe unten auf „Aufnehmen“. Danach steht hier deine Notiz."))
                        .navigationTitle("Aufnahmen")
                }
            }
            SwiftUI.Tab("Lernen", systemImage: "rectangle.on.rectangle.angled", value: .learn) {
                NavigationStack {
                    ContentUnavailableView("Noch keine Karteikarten", systemImage: "rectangle.on.rectangle.angled",
                                           description: Text("Aus jeder Notiz kannst du Karteikarten machen und hier lernen."))
                        .navigationTitle("Lernen")
                }
            }
            SwiftUI.Tab(value: .search, role: .search) {
                NavigationStack {
                    ContentUnavailableView.search(text: query)
                        .navigationTitle("Suche")
                }
                .searchable(text: $query, prompt: "Titel, Notizen, Transkripte")
            }
        }
        .tabViewBottomAccessory {
            // ponytail: Platzhalter bis M2 (PhoneRecorder); der Knopf nimmt noch nicht auf
            Button("Aufnehmen", systemImage: "record.circle") {}
                .disabled(true)
        }
    }
}

extension RootView.Tab: RawRepresentable {
    init?(rawValue: String) {
        switch rawValue {
        case "learn": self = .learn
        case "search": self = .search
        default: self = .recordings
        }
    }
    var rawValue: String {
        switch self {
        case .recordings: "recordings"
        case .learn: "learn"
        case .search: "search"
        }
    }
}
