import EarnoteCore
import SwiftUI

/// Tab „Lernen“: Karteikarten aus allen Notizen, nach Bereich. Die Karten stehen in der Notiz selbst
/// (Abschnitt „Karteikarten“) – hier werden sie nur gesammelt und abgefragt.
struct LearnView: View {
    @Environment(LibraryStore.self) private var library
    @State private var cards: [UUID?: [Flashcard]] = [:]
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if cards.isEmpty {
                    ContentUnavailableView("Noch keine Karteikarten", systemImage: "rectangle.on.rectangle.angled",
                                           description: Text("Öffne eine Notiz und wähle „Karteikarten erstellen“. Danach lernst du sie hier."))
                } else {
                    List {
                        Section {
                            NavigationLink(value: LearnDeck(title: String(localized: "Alle Karten"), cards: cards.values.flatMap { $0 })) {
                                LabeledContent("Alle Karten", value: "\(cards.values.reduce(0) { $0 + $1.count })")
                            }
                        }
                        Section("Bereiche") {
                            ForEach(sortedKeys, id: \.self) { key in
                                let name = key.flatMap { library.category($0).map { "\($0.displayEmoji) \($0.name)" } } ?? String(localized: "Ohne Bereich")
                                NavigationLink(value: LearnDeck(title: name, cards: cards[key] ?? [])) {
                                    LabeledContent(name, value: "\(cards[key]?.count ?? 0)")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lernen")
            .navigationDestination(for: LearnDeck.self) { FlashcardSession(deck: $0) }
            .task(id: library.recordings.map(\.summaryPreview).hashValue) { await load() }
        }
    }

    /// In der Reihenfolge der Bereiche, „Ohne Bereich“ zuletzt
    private var sortedKeys: [UUID?] {
        func position(_ id: UUID?) -> Int { id.flatMap { id in library.categories.firstIndex { $0.id == id } } ?? .max }
        return cards.keys.sorted { position($0) < position($1) }
    }

    private func load() async {
        var byCategory: [UUID?: [Flashcard]] = [:]
        for recording in library.recordings where recording.status == .done {
            guard let note = await library.summary(recording.id) else { continue }
            let found = Flashcards.entries(note.markdown).map(\.card)
            if !found.isEmpty { byCategory[recording.categoryID, default: []] += found }
        }
        cards = byCategory
        isLoading = false
    }
}

struct LearnDeck: Hashable {
    let title: String
    let cards: [Flashcard]
}

/// Abfragen: Frage, Tippen zeigt die Antwort, „Wusste ich“ oder „Nochmal“ – Nochmal kommt ans Ende.
struct FlashcardSession: View {
    let deck: LearnDeck
    @State private var remaining: [Flashcard] = []
    @State private var known = 0
    @State private var showsAnswer = false

    var body: some View {
        VStack(spacing: 24) {
            if let card = remaining.first {
                ProgressView(value: Double(known), total: Double(deck.cards.count))
                    .padding(.horizontal)
                Button { withAnimation(.snappy) { showsAnswer.toggle() } } label: {
                    VStack(spacing: 16) {
                        Text(card.question)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        if showsAnswer {
                            Divider()
                            Text(card.answer)
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        } else {
                            Text("Tippen für die Antwort").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .background(.background.secondary, in: .rect(cornerRadius: 20))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .accessibilityHint(showsAnswer ? "" : "Zeigt die Antwort")
                Spacer()
                if showsAnswer {
                    HStack(spacing: 16) {
                        Button { next(knew: false) } label: {
                            Label("Nochmal", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button { next(knew: true) } label: {
                            Label("Wusste ich", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                    .padding(.horizontal)
                }
            } else {
                ContentUnavailableView {
                    Label("Geschafft!", systemImage: "checkmark.seal.fill")
                } description: {
                    Text("Du hast alle \(deck.cards.count) Karten gewusst.")
                } actions: {
                    Button("Noch einmal") { restart() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical)
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: known)
        .onAppear { if remaining.isEmpty && known == 0 { restart() } }
    }

    private func next(knew: Bool) {
        let card = remaining.removeFirst()
        if knew { known += 1 } else { remaining.append(card) }
        showsAnswer = false
    }

    private func restart() {
        remaining = deck.cards.shuffled()
        known = 0
        showsAnswer = false
    }
}
