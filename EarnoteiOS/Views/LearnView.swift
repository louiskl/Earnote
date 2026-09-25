import EarnoteCore
import SwiftUI

/// Karten zum Abfragen – aus einer Notiz oder allen Notizen eines Bereichs (`FlashcardDeck.load`)
struct LearnDeck: Hashable {
    let title: String
    let cards: [Flashcard]
}

/// Abfragen: Karte antippen dreht sie um, „Wusste ich“ oder „Nochmal“ – Nochmal kommt ans Ende.
struct FlashcardSession: View {
    let deck: LearnDeck
    @State private var remaining: [Flashcard] = []
    @State private var known = 0
    @State private var showsAnswer = false

    var body: some View {
        VStack(spacing: 24) {
            if let card = remaining.first {
                VStack(spacing: 6) {
                    ProgressView(value: Double(known), total: Double(deck.cards.count))
                    Text("\(known) von \(deck.cards.count) gewusst")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal)
                FlipCard(card: card, showsAnswer: $showsAnswer)
                    .id(card)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .padding(.horizontal)
                Spacer(minLength: 0)
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        Button { next(knew: false) } label: {
                            Label("Nochmal", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        Button { next(knew: true) } label: {
                            Label("Wusste ich", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .controlSize(.extraLarge)
                }
                .padding(.horizontal)
                .opacity(showsAnswer ? 1 : 0)
                .disabled(!showsAnswer)
            } else {
                ContentUnavailableView {
                    Label("Geschafft!", systemImage: "checkmark.seal.fill")
                        .symbolEffect(.bounce, value: known)
                } description: {
                    Text("Du hast alle \(deck.cards.count) Karten gewusst.")
                } actions: {
                    Button("Noch einmal") { restart() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
        }
        .padding(.vertical)
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        // Beim Lernen zählt nur die Karte – Tabs und Aufnahme-Leiste treten zurück
        .toolbarVisibility(.hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: known)
        .animation(.smooth, value: showsAnswer)
        .onAppear { if remaining.isEmpty && known == 0 { restart() } }
    }

    private func next(knew: Bool) {
        withAnimation(.smooth(duration: 0.35)) {
            let card = remaining.removeFirst()
            if knew { known += 1 } else { remaining.append(card) }
            showsAnswer = false
        }
    }

    private func restart() {
        remaining = deck.cards.shuffled()
        known = 0
        showsAnswer = false
    }
}

/// Karteikarte aus Glas: Vorderseite Frage, Rückseite Antwort. Mit „Bewegung reduzieren“ blendet sie nur über.
private struct FlipCard: View {
    let card: Flashcard
    @Binding var showsAnswer: Bool
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            face(caption: "Frage", text: card.question, font: .title2.weight(.semibold), hint: "Tippen zum Umdrehen")
                .opacity(showsAnswer ? 0 : 1)
            face(caption: "Antwort", text: card.answer, font: .title3, hint: nil)
                .opacity(showsAnswer ? 1 : 0)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(showsAnswer && !reduceMotion ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .contentShape(.rect(cornerRadius: 32))
        .onTapGesture {
            withAnimation(.spring(duration: 0.55, bounce: 0.2)) { showsAnswer.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(showsAnswer ? "" : "Zeigt die Antwort")
    }

    private func face(caption: LocalizedStringKey, text: String, font: Font, hint: LocalizedStringKey?) -> some View {
        VStack(spacing: 16) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tint)
            Spacer(minLength: 0)
            Text(text)
                .font(font)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let hint {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 380)
        .glassEffect(.regular.tint(skin.tint.opacity(0.08)).interactive(), in: .rect(cornerRadius: 32))
    }
}
