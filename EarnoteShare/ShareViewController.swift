import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// „Mit Earnote teilen“: nimmt Audio und Video an, legt es für die App bereit (`ShareInbox`) und bestätigt kurz.
/// Die Notiz entsteht in der App – eine Erweiterung darf weder lange rechnen noch die App selbst öffnen.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareConfirmation(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        model.collect(items.flatMap { $0.attachments ?? [] })
    }
}

@MainActor
@Observable
final class ShareModel {
    enum State { case copying, done, failed }

    private(set) var state = State.copying
    private var remaining = 0
    private var copied = 0

    func collect(_ providers: [NSItemProvider]) {
        let types: [UTType] = [.audio, .movie, .audiovisualContent]
        var matching: [(NSItemProvider, UTType)] = []
        for provider in providers {
            if let type = types.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                matching.append((provider, type))
            }
        }
        guard !matching.isEmpty else {
            state = .failed
            return
        }
        remaining = matching.count
        for (provider, type) in matching {
            // Die Datei gilt nur innerhalb des Rückrufs – deshalb wird dort kopiert
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, _ in
                let ok = url.map { (try? ShareInbox.add($0)) != nil } ?? false
                Task { @MainActor in self?.finished(ok) }
            }
        }
    }

    private func finished(_ ok: Bool) {
        remaining -= 1
        if ok { copied += 1 }
        if remaining == 0 { state = copied > 0 ? .done : .failed }
    }
}

/// Kurze Bestätigung im Teilen-Blatt
struct ShareConfirmation: View {
    let model: ShareModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .copying:
                    ProgressView("Wird übernommen …")
                case .done:
                    ContentUnavailableView("Bei Earnote angekommen", systemImage: "checkmark.circle",
                                           description: Text("Öffne Earnote – dann entsteht die Notiz."))
                case .failed:
                    ContentUnavailableView("Das geht leider nicht", systemImage: "exclamationmark.triangle",
                                           description: Text("Earnote kann nur Audio und Video übernehmen."))
                }
            }
            .navigationTitle(Text(verbatim: "Earnote"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: close)
                }
            }
        }
    }
}
