import EarnoteCore
import StoreKit
import SwiftUI

/// Trinkgeld als einmaliger In-App-Kauf (docs/IPHONE.md, Abschnitt 9): Apple lässt am iPhone keine Spendenlinks zu.
/// Jedes Trinkgeld schaltet das Dankeschön-Paket frei (Farben und App-Symbole, `AppearanceView`); Funktionen bleiben
/// für alle kostenlos. Die Produkte (Verbrauchsartikel) werden in App Store Connect angelegt.
enum TipJar {
    static let productIDs = ["app.earnote.Earnote.tip.small", "app.earnote.Earnote.tip.medium", "app.earnote.Earnote.tip.large"]
    /// Merker in den Einstellungen des Geräts; die Kaufhistorie bleibt die Quelle (`refreshSupporter`)
    static let supporterKey = "supporter"

    /// Beim Start: Dankeschön-Paket prüfen, dann Käufe abschließen, die beim letzten Mal offen blieben (App beendet,
    /// Bestätigung durch Eltern …) oder auf einem anderen Gerät kamen
    static func finishPendingTransactions() -> Task<Void, Never> {
        Task.detached { await refreshSupporter() }
        return Task.detached {
            for await update in StoreKit.Transaction.updates {
                await finish(update)
            }
        }
    }

    /// Die Trinkgelder, günstigstes zuerst – leer, solange sie in App Store Connect fehlen oder der Store nicht erreichbar ist
    static func products() async -> [Product] {
        let loaded = (try? await Product.products(for: productIDs)) ?? []
        return loaded.sorted { $0.price < $1.price }
    }

    static func finish(_ result: VerificationResult<StoreKit.Transaction>) async {
        if case .verified(let transaction) = result { apply(transaction) }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            await transaction.finish()
        }
    }

    /// Trinkgeld oder Pro schalten das Dankeschön-Paket frei, Pro zusätzlich die Pro-Funktionen.
    /// Eine Erstattung nimmt Pro wieder weg; das Dankeschön-Paket bleibt.
    private static func apply(_ transaction: StoreKit.Transaction) {
        let defaults = UserDefaults.standard
        if transaction.productID == Pro.productID {
            let valid = transaction.revocationDate == nil
            defaults.set(valid, forKey: Pro.key)
            if valid { defaults.set(true, forKey: supporterKey) }
        } else if productIDs.contains(transaction.productID), transaction.revocationDate == nil {
            defaults.set(true, forKey: supporterKey)
        }
    }

    /// Beim Start und nach „Käufe wiederherstellen“: Hat dieses Apple-Konto schon Trinkgeld gegeben oder Pro gekauft?
    /// Dank `SKIncludeConsumableInAppPurchaseHistory` (Info.plist) stehen auch abgeschlossene Trinkgelder in der Historie.
    /// Setzt den Merker nur, nimmt ihn nie weg – ohne Netz ist die Historie womöglich leer.
    static func refreshSupporter() async {
        for await result in StoreKit.Transaction.all {
            if case .verified(let transaction) = result { apply(transaction) }
        }
    }
}

/// Das Dankeschön-Paket: was ein Trinkgeld bringt, und die Trinkgelder selbst. In den Einstellungen und ab und zu
/// von selbst als Blatt (`FeedbackMoment.supporter`).
struct SupporterView: View {
    /// Aus „Aussehen“ heraus geöffnet, führt der Link nur im Kreis
    var showsAppearanceLink = true
    @AppStorage(TipJar.supporterKey) private var isSupporter = false
    @State private var products: [Product] = []
    @State private var loaded = false
    @State private var restoring = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(AppIconChoice.allCases.dropFirst()) { icon in
                            icon.preview.resizable().frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 10))
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Earnote bleibt kostenlos – ohne Werbung, ohne Konto, mit allen Funktionen. Wer mag, gibt ein Trinkgeld und bekommt als Dank ein paar Extras.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section("Das bekommst du") {
                Label("\(AppSkin.colors.count - 1) weitere Farben für die App", systemImage: "paintpalette")
                Label("Designs: Retro, Notizbuch und Terminal", systemImage: "textformat")
                Label("\(AppIconChoice.allCases.count - 1) weitere App-Symbole", systemImage: "app.badge")
                Label("Du hilfst bei den Kosten für Apple-Konto und Weiterentwicklung", systemImage: "heart")
            }
            if isSupporter {
                Section {
                    Label("Freigeschaltet – danke!", systemImage: "checkmark.seal.fill").foregroundStyle(.tint)
                    if showsAppearanceLink {
                        NavigationLink("Farbe und Symbol wählen") { AppearanceView() }
                    }
                }
            }
            if !products.isEmpty {
                TipSection(products: products)
            } else if loaded {
                Section {
                    Text("Der App Store ist gerade nicht erreichbar. Versuch es später noch einmal.").foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    Task {
                        restoring = true
                        try? await AppStore.sync()
                        await TipJar.refreshSupporter()
                        restoring = false
                    }
                } label: {
                    HStack {
                        Text("Käufe wiederherstellen")
                        if restoring { Spacer(); ProgressView() }
                    }
                }
                .disabled(restoring)
            } footer: {
                Text("Schon einmal Trinkgeld gegeben, z. B. auf einem anderen Gerät? Dann holt das hier dein Dankeschön-Paket zurück.")
            }
        }
        .navigationTitle("Dankeschön-Paket")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            products = await TipJar.products()
            loaded = true
        }
    }
}

/// Die Trinkgeld-Käufe mit Preisen aus dem App Store
struct TipSection: View {
    let products: [Product]
    @State private var thanked = false

    var body: some View {
        Section {
            ForEach(products) { product in
                ProductView(product) {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(.tint)
                }
                .productViewStyle(.compact)
            }
        } header: {
            Text("Trinkgeld geben")
        } footer: {
            if thanked {
                Text("Danke! Das hilft, Earnote kostenlos weiterzuentwickeln. Farben und Symbole sind jetzt freigeschaltet.")
            } else {
                Text("Jedes Trinkgeld schaltet das ganze Dankeschön-Paket frei. Einmalig, kein Abo.")
            }
        }
        .onInAppPurchaseCompletion { _, result in
            guard case .success(.success(let verification)) = result else { return }
            await TipJar.finish(verification)
            thanked = true
        }
    }
}
