import AppKit
import EarnoteCore

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
            guard let page = try? await page(id, library: library) else { return }
            let info = printInfo()
            let operation = NSPrintOperation(view: textView(page.text, info: info), printInfo: info)
            operation.jobTitle = page.title
            operation.run()
        }
    }

    /// Schreibt ein PDF und fragt, wohin es gehört.
    static func savePDF(_ id: UUID, library: LibraryStore) {
        Task { @MainActor in
            guard let page = try? await page(id, library: library) else { return }
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
        guard let page = try? await page(id, library: library) else { return nil }
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

    private static func page(_ id: UUID, library: LibraryStore) async throws -> (title: String, text: NSAttributedString)? {
        guard let recording = library.recording(id), let note = await library.summary(id) else { return nil }
        let title = recording.hasAutoTitle ? note.title : recording.title
        let subtitle = subtitle(for: recording, categoryName: library.category(recording.categoryID)?.name)
        return (title, attributed(title: title, subtitle: subtitle, markdown: note.markdown))
    }

    /// Setzt Titel, Kopfzeile und die Blöcke der Notiz.
    static func attributed(title: String, subtitle: String, markdown: String) -> NSAttributedString {
        let page = NSMutableAttributedString()
        page.append(line(title, font: .systemFont(ofSize: 21, weight: .bold), spacingAfter: 2))
        page.append(line(subtitle, font: .systemFont(ofSize: 10), color: .secondaryLabelColor, spacingAfter: 14))

        for block in NoteMarkdown.blocks(markdown) {
            switch block {
            case .paragraph(_, let text):
                page.append(paragraph(text, font: .systemFont(ofSize: 11)))
            case .heading(_, let level, let text, let timestamp):
                let heading = timestamp.map { "\(text)  \($0)" } ?? text
                page.append(line(heading, font: .systemFont(ofSize: level == 3 ? 12 : 14, weight: .semibold),
                                 spacingBefore: level == 3 ? 8 : 14, spacingAfter: 4))
            case .bullet(_, let text, let indent):
                page.append(listItem("•", text, indent: indent))
            case .numbered(_, let number, let text, let indent):
                page.append(listItem("\(number).", text, indent: indent))
            case .task(_, let text, let isDone, _):
                page.append(listItem(isDone ? "☑" : "☐", text, indent: 0))
            case .quote(_, let text):
                page.append(paragraph(text, font: .systemFont(ofSize: 11).italic, color: .secondaryLabelColor, indent: 16))
            }
        }
        return page
    }

    private static func paragraph(_ text: String, font: NSFont, color: NSColor = .labelColor,
                                  indent: CGFloat = 0) -> NSAttributedString {
        line(text, font: font, color: color, indent: indent, spacingAfter: 8)
    }

    private static func listItem(_ marker: String, _ text: String, indent: Int) -> NSAttributedString {
        let left = CGFloat(indent) * 16 + 16
        let style = NSMutableParagraphStyle()
        style.headIndent = left
        style.firstLineHeadIndent = left - 14
        style.paragraphSpacing = 3
        style.lineSpacing = 1.5
        style.tabStops = [NSTextTab(textAlignment: .left, location: left)]
        let item = NSMutableAttributedString(string: "\(marker)\t",
                                             attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                          .foregroundColor: NSColor.labelColor])
        item.append(inline(text, font: .systemFont(ofSize: 11), color: .labelColor))
        item.append(NSAttributedString(string: "\n"))
        item.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: item.length))
        return item
    }

    private static func line(_ text: String, font: NSFont, color: NSColor = .labelColor, indent: CGFloat = 0,
                             spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        style.lineSpacing = 1.5
        let result = NSMutableAttributedString(attributedString: inline(text, font: font, color: color))
        result.append(NSAttributedString(string: "\n"))
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Fett, kursiv und Code innerhalb einer Zeile – wie im Fenster, nur in Druckgrößen.
    private static func inline(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: text,
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
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 56
        info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    /// Textansicht in Seitenbreite; die Höhe ergibt sich aus dem umbrochenen Text.
    private static func textView(_ text: NSAttributedString, info: NSPrintInfo) -> NSTextView {
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
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
        let operation = NSPrintOperation(view: textView(text, info: info), printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func fileName(for title: String) -> String { NoteDocument.fileName(title, extension: "pdf") }

    /// Dateiname ohne Zeichen, die im Finder Ärger machen
    static func fileName(_ title: String, extension ext: String) -> String {
        let clean = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        return (clean.isEmpty ? String(localized: "Notiz") : String(clean.prefix(80))) + "." + ext
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
        Task {
            guard let recording = library.recording(recordingID),
                  let note = await library.summary(recordingID) else { return }
            let cards = Flashcards.parse(note.markdown)
            guard !cards.isEmpty else {
                library.lastError = String(localized: "Diese Notiz hat noch keine Karteikarten. Erzeuge sie zuerst.")
                return
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
