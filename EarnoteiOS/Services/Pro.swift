import EarnoteCore
import StoreKit
import SwiftUI

/// Earnote Pro (docs/PRO.md): ein einmaliger Kauf für Funktionen, die über das Notizenschreiben hinausgehen.
/// Die kostenlose App bleibt vollständig; jede Pro-Funktion lässt sich vorher ein paar Mal ausprobieren.
/// Käufe schließt `TipJar` ab (ein Zuhörer für alle Käufe); Pro schaltet auch das Dankeschön-Paket frei.
enum Pro {
    static let productID = "app.earnote.Earnote.pro"
    static let key = "pro"
    static let freeTries = 3

    enum Feature: String, CaseIterable, Identifiable {
        case chat, examRadar

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .chat: "Fragen zur Notiz"
            case .examRadar: "Klausur-Radar"
            }
        }

        var detail: LocalizedStringKey {
            switch self {
            case .chat: "Frag nach, was du nicht verstanden hast – die KI kennt die Notiz und die passenden Stellen der Aufnahme."
            case .examRadar: "Tippe in der Vorlesung auf „Wichtig“, auch auf dem Sperrbildschirm. Vor der Prüfung siehst du je Fach alles, was drankommt."
            }
        }

        var symbol: String {
            switch self {
            case .chat: "bubble.left.and.text.bubble.right"
            case .examRadar: "scope"
            }
        }
    }

    static var isUnlocked: Bool { UserDefaults.standard.bool(forKey: key) }

    private static func triesKey(_ feature: Feature) -> String { "pro.tries.\(feature.rawValue)" }

    static func triesLeft(_ feature: Feature) -> Int {
        max(0, freeTries - UserDefaults.standard.integer(forKey: triesKey(feature)))
    }

    /// Darf die Funktion jetzt laufen? Ohne Pro verbraucht das einen Versuch.
    static func use(_ feature: Feature) -> Bool {
        if isUnlocked { return true }
        guard triesLeft(feature) > 0 else { return false }
        UserDefaults.standard.set(freeTries - triesLeft(feature) + 1, forKey: triesKey(feature))
        return true
    }

    static func product() async -> Product? {
        try? await Product.products(for: [productID]).first
    }
}

/// Der Pro-Hinweis: was Pro bringt, Kaufen, Wiederherstellen. Als Blatt (`ProSheet`) oder in den Einstellungen.
struct ProView: View {
    /// Die Funktion, von der aus der Hinweis kam – steht oben in der Liste
    var highlight: Pro.Feature?
    @AppStorage(Pro.key) private var isPro = false
    @State private var product: Product?
    @State private var loaded = false
    @State private var buying = false
    @State private var failed = false

    private var features: [Pro.Feature] {
        guard let highlight else { return Pro.Feature.allCases }
        return [highlight] + Pro.Feature.allCases.filter { $0 != highlight }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("IconPreview-Standard")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 16))
                        .accessibilityHidden(true)
                    Text("Earnote Pro").font(.title.bold())
                    Text("Einmal kaufen, für immer. Alles, was Earnote heute kann, bleibt kostenlos.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(features) { feature in
                    Label {
                        Text(feature.title).font(.headline)
                        Text(feature.detail)
                    } icon: {
                        Image(systemName: feature.symbol).foregroundStyle(.tint)
                    }
                    .padding(.vertical, 4)
                }
                Label {
                    Text("Dankeschön-Paket inklusive").font(.headline)
                    Text("Alle Farben, Designs und App-Symbole.")
                } icon: {
                    Image(systemName: "paintpalette").foregroundStyle(.tint)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Das bringt Pro")
            }
            Section {
                Button("Käufe wiederherstellen") {
                    Task {
                        try? await AppStore.sync()
                        await TipJar.refreshSupporter()
                    }
                }
            } footer: {
                Text("Einmalige Zahlung, kein Abo. Gilt auf all deinen Geräten mit derselben Apple-ID und für deine Familie.")
            }
        }
        .navigationTitle("Earnote Pro")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { buyBar }
        .task {
            product = await Pro.product()
            loaded = true
        }
        .alert("Der Kauf hat nicht geklappt. Versuch es noch einmal.", isPresented: $failed) {}
    }

    @ViewBuilder private var buyBar: some View {
        Group {
            if isPro {
                Label("Freigeschaltet – danke!", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)
            } else if let product {
                Button {
                    Task { await buy(product) }
                } label: {
                    HStack {
                        if buying { ProgressView() }
                        Text("Earnote Pro für \(product.displayPrice)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(buying)
            } else if loaded {
                Text("Der App Store ist gerade nicht erreichbar. Versuch es später noch einmal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func buy(_ product: Product) async {
        buying = true
        defer { buying = false }
        switch try? await product.purchase() {
        case .success(let verification): await TipJar.finish(verification)
        case .userCancelled, .pending: break
        default: failed = true
        }
    }
}

/// Pro-Hinweis als eigenes Blatt, z. B. wenn die Probeversuche einer Funktion aufgebraucht sind
struct ProSheet: View {
    var highlight: Pro.Feature?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProView(highlight: highlight)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Später") { dismiss() } }
                }
        }
    }
}
