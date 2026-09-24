import EarnoteCore
import StoreKit
import SwiftUI

/// Trinkgeld als einmaliger In-App-Kauf (docs/IPHONE.md, Abschnitt 9): Apple lässt am iPhone keine Spendenlinks zu.
/// Nichts wird freigeschaltet – ein Kauf ist nur ein Dankeschön. Die Produkte (Verbrauchsartikel) werden in
/// App Store Connect angelegt; solange es sie nicht gibt, bleibt der Abschnitt in den Einstellungen verborgen.
enum TipJar {
    static let productIDs = ["app.earnote.Earnote.tip.small", "app.earnote.Earnote.tip.medium", "app.earnote.Earnote.tip.large"]

    /// Käufe, die beim letzten Mal nicht abgeschlossen wurden (App beendet, Bestätigung durch Eltern …), beim Start abschließen
    static func finishPendingTransactions() -> Task<Void, Never> {
        Task.detached {
            for await update in Transaction.updates {
                await finish(update)
            }
        }
    }

    /// Die Trinkgelder, günstigstes zuerst – leer, solange sie in App Store Connect fehlen oder der Store nicht erreichbar ist
    static func products() async -> [Product] {
        let loaded = (try? await Product.products(for: productIDs)) ?? []
        return loaded.sorted { $0.price < $1.price }
    }

    static func finish(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            await transaction.finish()
        }
    }
}

/// „Earnote unterstützen“ in den Einstellungen: die Trinkgeld-Käufe mit Preisen aus dem App Store
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
            Text("Earnote unterstützen")
        } footer: {
            if thanked {
                Text("Danke! Das hilft, Earnote kostenlos weiterzuentwickeln.")
            } else {
                Text("Earnote bleibt kostenlos und vollständig nutzbar. Ein Trinkgeld schaltet nichts frei – es hilft nur bei der Weiterentwicklung.")
            }
        }
        .onInAppPurchaseCompletion { _, result in
            guard case .success(.success(let verification)) = result else { return }
            await TipJar.finish(verification)
            thanked = true
        }
    }
}
