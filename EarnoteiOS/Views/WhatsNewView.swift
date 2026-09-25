import EarnoteCore
import SwiftUI

/// „Neu in Earnote“ – einmal nach einem Update (`FeedbackMoment.whatsNew`), wie die Neuigkeiten in Apples eigenen Apps.
/// Für jede Version mit Neuigkeiten `version` und `items` anpassen; ohne passende Version erscheint nichts.
@MainActor enum WhatsNew {
    static let version = "0.9.25"

    static let items: [(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey)] = [
        ("star.circle", "Earnote Pro",
         "Sprecher erkennen, Fragen zur Notiz, „Wichtig“ mit Klausur-Radar und Übersetzen – jede Funktion dreimal kostenlos zum Ausprobieren."),
        ("list.bullet.rectangle", "Aufgeräumt",
         "Das Menü einer Notiz hat jetzt drei Gruppen: Lernen, Bearbeiten und Löschen. Den Titel antippen, um ihn zu ändern."),
        ("gearshape", "Kürzere Einstellungen",
         "Das Wichtigste steht oben, Seltenes unter „Weitere Optionen“."),
    ]
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Neu in Earnote")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    ForEach(WhatsNew.items.indices, id: \.self) { index in
                        let item = WhatsNew.items[index]
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: item.symbol)
                                .font(.title)
                                .foregroundStyle(.tint)
                                .frame(width: 40)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.text).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Text("Weiter").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    NavigationLink("Farben und Symbole ansehen") { AppearanceView() }
                        .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: 520)
            }
        }
    }
}
