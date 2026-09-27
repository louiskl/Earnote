// App-Store-Bilder aus rohen Screenshots: Überschrift oben, darunter der Screenshot mit runden Ecken (docs/APPSTORE.md).
// Rohbilder:  dist/screenshots/raw/<sprache>/<gerät>/1.png … 6.png   (sprache: de, en · gerät: iphone, ipad)
// Ergebnis:   dist/screenshots/<sprache>/<gerät>/1.png …              (iPhone 6,9″ 1320×2868 · iPad 13″ 2064×2752)
// Aufruf:     swift scripts/make_appstore_screenshots.swift
// Fehlt eine Sprache oder ein Gerät bei den Rohbildern, wird es übersprungen. Rohbilder vom echten Gerät (Emojis!).
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Überschriften in der Reihenfolge der Bilder (dieselben Sätze wie in docs/APPSTORE.md, „Screenshots“)
let captions: [String: [String]] = [
    "de": ["Aufnehmen. Bildschirm aus.", "Danach ist die Notiz da.", "Lernen mit Karteikarten.",
           "Immer im Blick.", "Auf dem iPhone, mit dem Mac oder kostenlos mit Google.", "Ein Bereich pro Fach."],
    "en": ["Record. Screen off.", "Then your note is ready.", "Study with flashcards.",
           "Always in view.", "On your iPhone, with your Mac, or free with Google.", "One area per subject."],
]
/// Auf dem iPad heißt es „iPad“ statt „iPhone“
let ipadCaption = ["Auf dem iPhone": "Auf dem iPad", "On your iPhone": "On your iPad"]

struct Device {
    let name: String
    let width: Int, height: Int
    /// Anteil der Breite für den Screenshot, Ecken des Bildschirms relativ zur Breite des Screenshots
    let shotWidth: CGFloat, cornerRatio: CGFloat
}
let devices = [
    Device(name: "iphone", width: 1320, height: 2868, shotWidth: 0.80, cornerRatio: 0.13),
    Device(name: "ipad", width: 2064, height: 2752, shotWidth: 0.80, cornerRatio: 0.03),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/screenshots")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

func load(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func save(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// Überschrift zentriert in `rect` (CG-Koordinaten, Ursprung unten links); die Schrift wird kleiner, bis sie passt
func drawCaption(_ text: String, in rect: CGRect, maxSize: CGFloat, ctx: CGContext) {
    var size = maxSize
    while true {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)!
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafeBytes(of: &alignment) { bytes in
            CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment, valueSize: bytes.count,
                                                             value: bytes.baseAddress!)], 1)
        }
        let string = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: rgb(0x1C1C1E),
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ])
        let setter = CTFramesetterCreateWithAttributedString(string)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                                                               CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil)
        if fit.height <= rect.height || size < 30 {
            // Senkrecht mittig im Kopfbereich
            let box = CGRect(x: rect.minX, y: rect.midY - fit.height / 2, width: rect.width, height: ceil(fit.height))
            let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: box, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            return
        }
        size -= 4
    }
}

func render(_ shot: CGImage, caption: String, device: Device) -> CGImage {
    let w = CGFloat(device.width), h = CGFloat(device.height)
    let ctx = CGContext(data: nil, width: device.width, height: device.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Hintergrund: heller Verlauf im Earnote-Rot (#E8453B), oben kräftiger
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(0xFFE4DF), rgb(0xFFF7F5)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
    // Kopf: oberes Fünftel
    let header = h * 0.2
    drawCaption(caption, in: CGRect(x: w * 0.08, y: h - header, width: w * 0.84, height: header * 0.8),
                maxSize: w * (device.name == "iphone" ? 0.09 : 0.075), ctx: ctx)
    // Screenshot darunter, unten angeschnitten wie ein Gerät, das aus dem Bild ragt
    let shotW = w * device.shotWidth
    let shotH = shotW * CGFloat(shot.height) / CGFloat(shot.width)
    let rect = CGRect(x: (w - shotW) / 2, y: h - header - shotH, width: shotW, height: shotH)
    let path = CGPath(roundedRect: rect, cornerWidth: shotW * device.cornerRatio, cornerHeight: shotW * device.cornerRatio,
                      transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.01), blur: w * 0.04, color: rgb(0x000000, 0.18))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shot, in: rect)
    ctx.restoreGState()
    return ctx.makeImage()!
}

var made = 0
for (language, texts) in captions.sorted(by: { $0.key < $1.key }) {
    for device in devices {
        let raw = root.appendingPathComponent("raw/\(language)/\(device.name)")
        for (index, text) in texts.enumerated() {
            let input = raw.appendingPathComponent("\(index + 1).png")
            guard let shot = load(input) else { continue }
            var caption = text
            if device.name == "ipad" { for (from, to) in ipadCaption { caption = caption.replacingOccurrences(of: from, with: to) } }
            let output = root.appendingPathComponent("\(language)/\(device.name)/\(index + 1).png")
            save(render(shot, caption: caption, device: device), to: output)
            print("✓ \(language)/\(device.name)/\(index + 1).png – \(caption)")
            made += 1
        }
    }
}
print(made == 0 ? "Keine Rohbilder gefunden unter \(root.path)/raw/<de|en>/<iphone|ipad>/1.png …" : "\(made) Bilder fertig.")
