import AppKit
import EarnoteCore
import PDFKit

/// Die Notiz als Lernzettel: gesetzte Seiten zum Drucken, als PDF und zum Teilen.
/// Gesetzt wird mit denselben Blöcken wie im Fenster (`NoteMarkdown.blocks`), nur in Druckgrößen.
@MainActor
enum NoteDocument {
    /// Kopf über der Notiz: Datum, Dauer, Bereich
    static func subtitle(for recording: Recording, categoryName: String?) -> String {
        [MainWindowFormat.dateAndTime(recording.startedAt),
         MainWindowFormat.duration(recording.duration),
         categoryName].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Aktionen

    /// Druckt die Notiz (der Druckdialog von macOS bietet auch „Als PDF sichern“ an).
    static func printNote(_ id: UUID, library: LibraryStore) {
        Task { @MainActor in
            guard let page = await pageOrComplain(id, library: library) else { return }
            let info = printInfo()
            let operation = NSPrintOperation(view: textView(page.text, info: info, title: page.title), printInfo: info)
            operation.jobTitle = page.title
            operation.run()
        }
    }

    /// Schreibt ein PDF und fragt, wohin es gehört.
    static func savePDF(_ id: UUID, library: LibraryStore) {
        Task { @MainActor in
            guard let page = await pageOrComplain(id, library: library) else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = fileName(for: page.title)
            panel.allowedContentTypes = [.pdf]
            panel.message = "Lernzettel als PDF sichern"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try writePDF(page.text, title: page.title, to: url)
            } catch {
                library.lastError = "Das PDF konnte nicht gesichert werden: \(error.localizedDescription)"
            }
        }
    }

    /// PDF im temporären Ordner – zum Teilen über das Teilen-Menü von macOS.
    static func temporaryPDF(_ id: UUID, library: LibraryStore) async -> URL? {
        guard let page = await pageOrComplain(id, library: library) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(for: page.title))
        do {
            try writePDF(page.text, title: page.title, to: url)
            return url
        } catch {
            Log.error("PDF erzeugen: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Satz

    /// Wie `page`, sagt aber Bescheid, wenn es nicht klappt. Vorher passierte beim Drucken oder
    /// Sichern in diesem Fall schlicht gar nichts – kein Fenster, keine Meldung, kein Hinweis.
    @MainActor
    private static func pageOrComplain(_ id: UUID, library: LibraryStore) async -> (title: String, text: NSAttributedString)? {
        do {
            if let page = try await page(id, library: library) { return page }
            library.lastError = String(localized: "Diese Aufnahme hat noch keine Notiz – es gibt also nichts zu drucken oder zu sichern.")
        } catch {
            library.lastError = String(localized: "Die Notiz konnte nicht aufbereitet werden. Versuch es noch einmal.")
            Log.error("Notiz aufbereiten: \(error)")
        }
        return nil
    }

    private static func page(_ id: UUID, library: LibraryStore) async throws -> (title: String, text: NSAttributedString)? {
        guard let recording = library.recording(id), let note = await library.summary(id) else { return nil }
        let title = recording.hasAutoTitle ? note.title : recording.title
        let category = library.category(recording.categoryID)
        let subtitle = [MainWindowFormat.dateAndTime(recording.startedAt),
                        recording.duration < 1 ? nil : MainWindowFormat.duration(recording.duration)]
            .compactMap { $0 }.joined(separator: " · ")
        let accent = category.flatMap { ColorRGB(hex: $0.colorHex) }.map { rgb in
            let readable = CategoryColor.readable(rgb, dark: false)
            return NSColor(srgbRed: readable.red, green: readable.green, blue: readable.blue, alpha: 1)
        }
        return (title, attributed(title: title, subtitle: subtitle, markdown: note.markdown,
                                  kicker: category?.name ?? String(localized: "Notiz"), accent: accent ?? PageStyle.brand))
    }

    /// Ruhige, feste Farben: Das PDF ist immer hell, auch wenn der Mac gerade dunkel ist.
    enum PageStyle {
        /// Die Farbe von earnote.dev
        static let brand = NSColor(srgbRed: 0xE8 / 255, green: 0x45 / 255, blue: 0x3B / 255, alpha: 1)
        static let text = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        static let secondary = NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1)
        static let tertiary = NSColor(srgbRed: 0.6, green: 0.6, blue: 0.62, alpha: 1)
        static var body: NSFont { .systemFont(ofSize: 11) }
    }

    /// Setzt Titel, Kopfzeile und die Blöcke der Notiz – minimalistisch: eine Akzentfarbe (die des Bereichs),
    /// ein kurzer Strich unter dem Kopf, farbige Aufzählungszeichen, sonst Typografie und Weißraum.
    static func attributed(title: String, subtitle: String, markdown: String,
                           kicker: String? = nil, accent: NSColor = PageStyle.brand) -> NSAttributedString {
        let page = NSMutableAttributedString()
        if let kicker, !kicker.isEmpty {
            let small = NSMutableAttributedString(attributedString: line(kicker.uppercased(), font: .systemFont(ofSize: 8.5, weight: .semibold),
                                                                         color: accent, spacingAfter: 5))
            small.addAttribute(.kern, value: 1.2, range: NSRange(location: 0, length: small.length))
            page.append(small)
        }
        page.append(line(title, font: .systemFont(ofSize: 22, weight: .bold), spacingAfter: 3))
        page.append(line(subtitle, font: .systemFont(ofSize: 9.5), color: PageStyle.secondary, spacingAfter: 10))
        page.append(accentBar(accent))

        for block in NoteMarkdown.blocks(markdown) {
            switch block {
            case .paragraph(_, let text):
                page.append(paragraph(text, font: PageStyle.body))
            case .heading(_, let level, let text, let timestamp):
                let heading = NSMutableAttributedString(attributedString: line(
                    text, font: .systemFont(ofSize: level == 3 ? 12 : 14.5, weight: .semibold),
                    spacingBefore: level == 3 ? 10 : 18, spacingAfter: 5))
                if let timestamp {
                    // Zeitmarke leise hinter der Überschrift, vor dem Zeilenumbruch
                    heading.insert(NSAttributedString(string: "  \(timestamp)", attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                        .foregroundColor: PageStyle.tertiary]), at: heading.length - 1)
                }
                page.append(heading)
            case .bullet(_, let text, let indent):
                page.append(listItem("•", text, indent: indent, accent: accent))
            case .numbered(_, let number, let text, let indent):
                page.append(listItem("\(number).", text, indent: indent, accent: accent))
            case .task(_, let text, let isDone, _):
                page.append(listItem(isDone ? "☑" : "☐", text, indent: 0, accent: accent))
            case .flashcard(_, let question, let answer):
                page.append(line(question, font: .systemFont(ofSize: 11, weight: .semibold), spacingBefore: 4, spacingAfter: 2))
                page.append(line(answer, font: PageStyle.body, color: PageStyle.secondary, indent: 12, spacingAfter: 8))
            case .quote(_, let text):
                page.append(paragraph(text, font: PageStyle.body.italic, color: PageStyle.secondary, indent: 16))
            }
        }
        return page
    }

    /// Der kurze farbige Strich unter dem Kopf – das eine Schmuckelement
    private static func accentBar(_ accent: NSColor) -> NSAttributedString {
        let size = NSSize(width: 32, height: 3)
        let image = NSImage(size: size, flipped: false) { rect in
            accent.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(origin: .zero, size: size)
        let bar = NSMutableAttributedString(attachment: attachment)
        bar.append(NSAttributedString(string: "\n"))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 16
        bar.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: bar.length))
        return bar
    }

    private static func paragraph(_ text: String, font: NSFont, color: NSColor = PageStyle.text,
                                  indent: CGFloat = 0) -> NSAttributedString {
        line(text, font: font, color: color, indent: indent, spacingAfter: 8)
    }

    private static func listItem(_ marker: String, _ text: String, indent: Int, accent: NSColor) -> NSAttributedString {
        let left = CGFloat(indent) * 16 + 16
        let style = NSMutableParagraphStyle()
        style.headIndent = left
        style.firstLineHeadIndent = left - 14
        style.paragraphSpacing = 4
        style.lineSpacing = 2.5
        style.tabStops = [NSTextTab(textAlignment: .left, location: left)]
        let item = NSMutableAttributedString(string: "\(marker)\t",
                                             attributes: [.font: PageStyle.body, .foregroundColor: accent])
        item.append(inline(text, font: PageStyle.body, color: PageStyle.text))
        item.append(NSAttributedString(string: "\n"))
        item.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: item.length))
        return item
    }

    private static func line(_ text: String, font: NSFont, color: NSColor = PageStyle.text, indent: CGFloat = 0,
                             spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        style.lineSpacing = 2.5
        let result = NSMutableAttributedString(attributedString: inline(text, font: font, color: color))
        result.append(NSAttributedString(string: "\n"))
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Fett, kursiv und Code innerhalb einer Zeile – wie im Fenster, nur in Druckgrößen.
    private static func inline(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: NoteMarkdown.protectingMath(text),
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let result = NSMutableAttributedString(parsed)
        let whole = NSRange(location: 0, length: result.length)
        result.addAttributes([.font: font, .foregroundColor: color], range: whole)
        result.enumerateAttribute(.inlinePresentationIntent, in: whole) { value, range, _ in
            guard let raw = value as? UInt else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            var styled = font
            if intent.contains(.stronglyEmphasized) { styled = styled.bold }
            if intent.contains(.emphasized) { styled = styled.italic }
            if intent.contains(.code) { styled = .monospacedSystemFont(ofSize: font.pointSize - 0.5, weight: .regular) }
            result.addAttribute(.font, value: styled, range: range)
        }
        return result
    }

    // MARK: Druck

    private static func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.topMargin = 60
        info.bottomMargin = 64
        info.leftMargin = 60
        info.rightMargin = 60
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    /// Textansicht in Seitenbreite; die Höhe ergibt sich aus dem umbrochenen Text.
    private static func textView(_ text: NSAttributedString, info: NSPrintInfo, title: String) -> NSTextView {
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = PageView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.title = title
        // Immer hell setzen – im Dunkelmodus käme sonst weiße Schrift aufs weiße Papier
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = false
        view.isEditable = false
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(text)
        if let layout = view.layoutManager, let container = view.textContainer {
            layout.ensureLayout(for: container)
            view.frame = NSRect(x: 0, y: 0, width: width, height: ceil(layout.usedRect(for: container).height) + 1)
        }
        return view
    }

    /// Schreibt die gesetzten Seiten als PDF – über den Druckweg, damit lange Notizen sauber umbrechen.
    static func writePDF(_ text: NSAttributedString, title: String, to url: URL) throws {
        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: textView(text, info: info, title: title), printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
        linkFooters(in: url, paper: info.paperSize, margins: info)
    }

    /// Macht „earnote.dev“ in der Fußzeile jeder Seite anklickbar. Die Fußzeile wird gezeichnet, nicht gesetzt –
    /// deshalb kommt der Link hinterher als PDF-Anmerkung dazu. Klappt das nicht, bleibt das PDF, wie es ist.
    private static func linkFooters(in url: URL, paper: NSSize, margins info: NSPrintInfo) {
        guard let document = PDFDocument(url: url), let target = URL(string: "https://earnote.dev") else { return }
        let rect = PageView.linkRect(paper: paper, leftMargin: info.leftMargin, bottomMargin: info.bottomMargin)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let link = PDFAnnotation(bounds: rect, forType: .link, withProperties: nil)
            link.url = target
            page.addAnnotation(link)
        }
        document.write(to: url)
    }

    private static func fileName(for title: String) -> String { NoteDocument.fileName(title, extension: "pdf") }

    /// Dateiname ohne Zeichen, die im Finder Ärger machen
    static func fileName(_ title: String, extension ext: String) -> String {
        let clean = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        return (clean.isEmpty ? String(localized: "Notiz") : String(clean.prefix(80))) + "." + ext
    }
}

/// Die Seite beim Drucken: der Text, dazu je Seite eine leise Fußzeile („Erstellt mit Earnote · earnote.dev“,
/// Seitenzahl) und ab Seite 2 oben der Titel. PDFs werden gern an Kommilitonen weitergegeben.
private final class PageView: NSTextView {
    var title = ""

    private static var footerFont: NSFont { .systemFont(ofSize: 8) }

    /// Fußzeile links: „Erstellt mit Earnote · earnote.dev“
    private static var credit: NSAttributedString {
        let gray: [NSAttributedString.Key: Any] = [.font: footerFont, .foregroundColor: NoteDocument.PageStyle.tertiary]
        let text = NSMutableAttributedString(string: String(localized: "Erstellt mit") + " ", attributes: gray)
        text.append(NSAttributedString(string: "Earnote", attributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: NoteDocument.PageStyle.secondary]))
        text.append(NSAttributedString(string: " · ", attributes: gray))
        text.append(NSAttributedString(string: "earnote.dev", attributes: [
            .font: footerFont, .foregroundColor: NoteDocument.PageStyle.brand]))
        return text
    }

    /// Abstand der Fußzeile vom unteren Papierrand
    private static func footerBaseline(bottomMargin: CGFloat) -> CGFloat { bottomMargin / 2 }

    /// Wo „earnote.dev“ steht – in PDF-Koordinaten (Ursprung unten links), für den Link
    static func linkRect(paper: NSSize, leftMargin: CGFloat, bottomMargin: CGFloat) -> NSRect {
        let full = credit
        let before = full.attributedSubstring(from: NSRange(location: 0, length: full.length - "earnote.dev".count)).size().width
        let size = NSAttributedString(string: "earnote.dev", attributes: [.font: footerFont]).size()
        return NSRect(x: leftMargin + before, y: footerBaseline(bottomMargin: bottomMargin) - 2,
                      width: size.width, height: size.height + 4)
    }

    override func drawPageBorder(with borderSize: NSSize) {
        super.drawPageBorder(with: borderSize)
        guard let operation = NSPrintOperation.current else { return }
        let info = operation.printInfo
        let saved = frame
        setFrameOrigin(.zero)
        setFrameSize(borderSize)
        defer { setFrameOrigin(saved.origin); setFrameSize(saved.size) }

        let left = info.leftMargin
        let right = borderSize.width - info.rightMargin
        // Der Seitenrand wird ungespiegelt gezeichnet (y wächst nach oben) – anders als der Text selbst
        let baseline = Self.footerBaseline(bottomMargin: info.bottomMargin)
        let credit = Self.credit
        let height = credit.size().height

        NoteDocument.PageStyle.tertiary.withAlphaComponent(0.4).setFill()
        NSRect(x: left, y: baseline + height + 6, width: right - left, height: 0.5).fill()
        credit.draw(at: NSPoint(x: left, y: baseline))

        let page = operation.currentPage
        let total = operation.pageRange.length
        let number = total >= page && total > 1
            ? String(localized: "Seite \(page) von \(total)") : String(localized: "Seite \(page)")
        let pageText = NSAttributedString(string: number, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NoteDocument.PageStyle.tertiary])
        pageText.draw(at: NSPoint(x: right - pageText.size().width, y: baseline))

        // Ab Seite 2 oben leise der Titel – ausgedruckt weiß man so, wozu das Blatt gehört
        if page > 1, !title.isEmpty {
            let head = NSAttributedString(string: title, attributes: [
                .font: Self.footerFont, .foregroundColor: NoteDocument.PageStyle.tertiary])
            head.draw(with: NSRect(x: left, y: borderSize.height - info.topMargin / 2 - head.size().height / 2, width: right - left,
                                   height: head.size().height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
    var italic: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask) }
}

/// Karteikarten als Anki-Datei sichern (CSV: Vorderseite, Rückseite).
@MainActor
enum FlashcardExport {
    static func save(_ recordingID: UUID, library: LibraryStore) {
        guard !library.makingFlashcards.contains(recordingID) else { return }
        Task {
            guard let recording = library.recording(recordingID),
                  let note = await library.summary(recordingID) else { return }
            var cards = Flashcards.parse(note.markdown)
            if cards.isEmpty {
                guard let generated = await library.makeFlashcards(recordingID) else { return }
                cards = generated
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = NoteDocument.fileName(recording.displayTitle, extension: "csv")
            panel.message = String(localized: "In Anki über „Datei › Importieren“ öffnen – erste Spalte Frage, zweite Antwort.")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try Flashcards.csv(cards).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                library.lastError = String(localized: "Karteikarten sichern: \(error.localizedDescription)")
            }
        }
    }
}

/// Kurzprotokoll zum Weiterschicken: öffnet einen Mail-Entwurf mit Titel und Notiz.
/// Geschickt wird nichts – der Entwurf steht im Mailprogramm und wartet auf den Nutzer.
@MainActor
enum FollowUpMail {
    /// Mehr passt in einen mailto-Link nicht zuverlässig hinein
    static let maxLength = 4_000

    /// `short` = nur Kurzfassung, Ergebnisse und Aufgaben
    static func compose(_ recordingID: UUID, library: LibraryStore, short: Bool = false) {
        Task {
            guard let recording = library.recording(recordingID),
                  let note = await library.summary(recordingID) else {
                library.lastError = String(localized: "Für diese Aufnahme gibt es noch keine Notiz.")
                return
            }
            let subject = recording.displayTitle
            var body = short
                ? NoteMarkdown.shortMinutes(title: subject, markdown: note.markdown)
                : NoteMarkdown.shareText(title: subject, markdown: note.markdown)
            if body.count > maxLength {
                body = String(body.prefix(maxLength)) + "\n\n" + String(localized: "… (gekürzt)")
            }
            var comps = URLComponents(string: "mailto:")!
            comps.queryItems = [URLQueryItem(name: "subject", value: subject),
                                URLQueryItem(name: "body", value: body)]
            // mailto verträgt kein „+“ als Leerzeichen – sonst steht es im Entwurf
            let link = comps.url?.absoluteString.replacingOccurrences(of: "+", with: "%2B")
            guard let link, let url = URL(string: link), NSWorkspace.shared.open(url) else {
                library.lastError = String(localized: "Der Mail-Entwurf konnte nicht geöffnet werden.")
                return
            }
        }
    }
}

/// Kurzprotokoll in die Zwischenablage – zum Einfügen in Mail, Slack oder Teams.
@MainActor
enum ShortMinutes {
    static func copy(_ recordingID: UUID, library: LibraryStore) {
        Task {
            guard let recording = library.recording(recordingID),
                  let note = await library.summary(recordingID) else {
                library.lastError = String(localized: "Für diese Aufnahme gibt es noch keine Notiz.")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(NoteMarkdown.shortMinutes(title: recording.displayTitle,
                                                                     markdown: note.markdown), forType: .string)
        }
    }
}
