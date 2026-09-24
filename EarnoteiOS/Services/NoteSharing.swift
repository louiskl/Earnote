import EarnoteCore
import SwiftUI
import UIKit

/// Lernzettel als PDF – derselbe Aufbau wie am Mac (NoteDocument): Kicker mit Bereich, Titel, rote Linie, Notiz,
/// Fußzeile „Erstellt mit Earnote · earnote.dev“ und Seitenzahl. Gesetzt über HTML, damit iOS die Seiten umbricht.
enum NotePDF {
    @MainActor
    static func make(title: String, kicker: String?, meta: String, markdown: String) throws -> URL {
        let formatter = UIMarkupTextPrintFormatter(markupText: html(title: title, kicker: kicker, meta: meta, markdown: markdown))
        let renderer = FooterRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 56, dy: 60), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, [kCGPDFContextCreator as String: "Earnote"])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(title) + ".pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        return cleaned.isEmpty ? "Earnote" : String(cleaned.prefix(80))
    }

    private static func html(title: String, kicker: String?, meta: String, markdown: String) -> String {
        var body = ""
        var list: String?
        // `list` merkt sich das offene Element samt Klasse, geschlossen wird nur der Name
        func close() { if let tag = list { body += "</\(tag.split(separator: " ")[0])>"; list = nil } }
        func open(_ tag: String) { if list != tag { close(); body += "<\(tag)>"; list = tag } }
        for block in NoteMarkdown.blocks(markdown) {
            switch block {
            case .heading(_, let level, let text, _):
                close(); body += "<h\(min(3, level + 1))>\(inline(text))</h\(min(3, level + 1))>"
            case .paragraph(_, let text):
                close(); body += "<p>\(inline(text))</p>"
            case .bullet(_, let text, _):
                open("ul"); body += "<li>\(inline(text))</li>"
            case .numbered(_, _, let text, _):
                open("ol"); body += "<li>\(inline(text))</li>"
            case .task(_, let text, let isDone, _):
                open("ul class=\"tasks\""); body += "<li><span class=\"box\(isDone ? " done" : "")\"></span>\(inline(text))</li>"
            case .flashcard(_, let question, let answer):
                close(); body += "<div class=\"card\"><b>\(inline(question))</b><br>\(inline(answer))</div>"
            case .quote(_, let text):
                close(); body += "<blockquote>\(inline(text))</blockquote>"
            }
        }
        close()
        return """
        <html><head><style>
        body { font-family: -apple-system, 'Helvetica Neue'; font-size: 11pt; line-height: 1.45; color: #1c1c1e; }
        .kicker { color: #E8453B; font-size: 8.5pt; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
        h1 { font-size: 22pt; margin: 4pt 0 2pt; }
        .meta { color: #6e6e73; font-size: 9.5pt; }
        .bar { width: 42pt; height: 3pt; background: #E8453B; border-radius: 2pt; margin: 10pt 0 14pt; }
        h2 { font-size: 14pt; margin: 16pt 0 4pt; } h3 { font-size: 12pt; margin: 12pt 0 3pt; }
        ul, ol { padding-left: 16pt; } li { margin: 2pt 0; } li::marker { color: #E8453B; }
        ul.tasks { list-style: none; padding-left: 0; }
        .box { display: inline-block; width: 8pt; height: 8pt; border: 1pt solid #8e8e93; border-radius: 2pt; margin-right: 7pt; vertical-align: -1pt; }
        .box.done { background: #E8453B; border-color: #E8453B; }
        .card { border-left: 3pt solid #E8453B; padding: 4pt 8pt; margin: 6pt 0; background: #fbf1f0; }
        blockquote { border-left: 3pt solid #d1d1d6; margin: 6pt 0; padding-left: 8pt; color: #3a3a3c; font-style: italic; }
        </style></head><body>
        \(kicker.map { "<div class=\"kicker\">\(escape($0))</div>" } ?? "")
        <h1>\(escape(title))</h1><div class="meta">\(escape(meta))</div><div class="bar"></div>
        \(body)
        </body></html>
        """
    }

    /// Fett, kursiv und Code innerhalb einer Zeile
    private static func inline(_ text: String) -> String {
        var s = escape(text)
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<b>$1</b>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![*\w])\*(?!\s)(.+?)\*"#, with: "<i>$1</i>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`(.+?)`"#, with: "<code>$1</code>", options: .regularExpression)
        return s
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Fußzeile auf jeder Seite
private final class FooterRenderer: UIPrintPageRenderer {
    override var footerHeight: CGFloat { get { 30 } set {} }

    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        let gray = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)
        let font = UIFont.systemFont(ofSize: 8.5)
        let left = NSMutableAttributedString(string: String(localized: "Erstellt mit Earnote · "),
                                             attributes: [.font: font, .foregroundColor: gray])
        left.append(NSAttributedString(string: "earnote.dev", attributes: [.font: font, .foregroundColor: UIColor(red: 0.91, green: 0.27, blue: 0.23, alpha: 1),
                                                                             .link: URL(string: "https://earnote.dev")!]))
        let right = NSAttributedString(string: String(localized: "Seite \(pageIndex + 1) von \(numberOfPages)"),
                                       attributes: [.font: font, .foregroundColor: gray])
        let y = footerRect.midY - font.lineHeight / 2
        left.draw(at: CGPoint(x: 56, y: y))
        right.draw(at: CGPoint(x: footerRect.maxX - 56 - right.size().width, y: y))
    }
}

/// Karteikarten als CSV für Anki (erste Spalte Vorderseite, zweite Rückseite)
enum AnkiExport {
    static func file(title: String, cards: [Flashcard]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(NotePDF.fileName(title) + " – Anki.csv")
        try Flashcards.csv(cards).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Teilen-Blatt für eine erzeugte Datei (PDF, Anki)
struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
