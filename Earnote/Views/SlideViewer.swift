import PDFKit
import SwiftUI

/// Welche Folie gezeigt werden soll (1 = erste)
struct SlidePage: Identifiable, Equatable {
    let url: URL
    let page: Int
    var id: Int { page }
}

/// Die Folien als PDF, aufgeschlagen bei einer Seite – Blatt am Mac, iPhone und iPad.
/// PDFKit statt eigener Darstellung: Zoomen, Blättern, Text markieren und VoiceOver kommen vom System.
struct SlideViewer: View {
    let slide: SlidePage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: slide.url, page: slide.page)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Folien")   // nicht „Folie N“: der Titel folgt dem Blättern nicht
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 860, minHeight: 480, idealHeight: 640)
        #endif
    }
}

#if os(macOS)
private struct PDFKitView: NSViewRepresentable {
    let url: URL
    let page: Int
    func makeNSView(context: Context) -> PDFView { PDFKitView.make(url, page) }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#else
private struct PDFKitView: UIViewRepresentable {
    let url: URL
    let page: Int
    func makeUIView(context: Context) -> PDFView { PDFKitView.make(url, page) }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#endif

extension PDFKitView {
    static func make(_ url: URL, _ page: Int) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        // Erst springen, wenn die Ansicht ihre Größe kennt – sonst bleibt sie bei Seite 1 stehen
        if let target = view.document?.page(at: max(0, page - 1)) {
            DispatchQueue.main.async { view.go(to: target) }
        }
        return view
    }
}
