// App-Store-Bilder aus rohen Screenshots (docs/APPSTORE.md, „Screenshots“).
// Alle Bilder eines Geräts entstehen aus EINEM breiten Panorama: Farbflächen und ein Band laufen über die Bildgrenzen,
// so gehen die Bilder im App Store beim Wischen ineinander über. Jedes Bild: Überschrift oben, darunter das Gerät mit
// Rahmen, unten angeschnitten.
//
// Rohbilder:  dist/screenshots/raw/<sprache>/<gerät>/1.png … 6.png   (sprache: de, en · gerät: iphone, ipad)
// Ergebnis:   dist/screenshots/<sprache>/<gerät>/1.png …              (iPhone 6,9″ 1320×2868 · iPad 13″ 2064×2752)
//             dist/screenshots/<sprache>/<gerät>/panorama.png           (Vorschau: alle nebeneinander)
// Aufruf:     swift scripts/make_appstore_screenshots.swift
// Fehlt eine Sprache oder ein Gerät bei den Rohbildern, wird es übersprungen. Rohbilder vom echten Gerät oder einem
// Simulator mit iOS 27 (iOS 26.3 im Simulator zeigt „?“ statt Emojis).
import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Überschriften in der Reihenfolge der Bilder. Was zwischen *Sternchen* steht, wird rot.
let captions: [String: [String]] = [
    "de": ["Vorlesung rein.\n*Notiz raus.*", "Jede Vorlesung,\n*sauber sortiert.*", "Lernen mit\n*Karteikarten.*",
           "Was kommt in\nder *Klausur*?", "Auf dem iPhone.\n*Ohne Internet.*", "Ein Bereich\n*pro Fach.*"],
    "en": ["Lecture in.\n*Notes out.*", "Every lecture,\n*neatly sorted.*", "Study with\n*flashcards.*",
           "What's on\nthe *exam*?", "On your iPhone.\n*No internet.*", "One area\n*per subject.*"],
]
/// iPad: eigene Bilder (Notiz, Notiz neben dem Transkript, Klausur-Radar)
let ipadCaptions: [String: [String]] = [
    "de": ["Vorlesung rein.\n*Notiz raus.*", "Notiz und Transkript\n*nebeneinander.*", "Was kommt in\nder *Klausur*?"],
    "en": ["Lecture in.\n*Notes out.*", "Notes and transcript,\n*side by side.*", "What's on\nthe *exam*?"],
]

struct Device {
    let name: String
    let width: Int, height: Int
    /// Breite des Bildschirms im Bild, Eckenradius des Bildschirms (Anteil seiner Breite), Rahmenstärke (Anteil)
    let screenWidth: CGFloat, screenCorner: CGFloat, bezel: CGFloat
    let island: Bool
}
let devices = [
    Device(name: "iphone", width: 1320, height: 2868, screenWidth: 0.76, screenCorner: 0.125, bezel: 0.028, island: true),
    Device(name: "ipad", width: 2064, height: 2752, screenWidth: 0.80, screenCorner: 0.035, bezel: 0.022, island: false),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/screenshots")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}
let brand = rgb(0xE8453B), ink = rgb(0x1C1C1E)

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

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// MARK: Hintergrund über alle Bilder

/// Weicher Verlauf, große unscharfe Farbflächen an den Bildgrenzen und ein geschwungenes Band quer durch alle Bilder
func panoramaBackground(width: Int, height: Int, panels: Int) -> CGImage {
    let w = CGFloat(width), h = CGFloat(height), panel = w / CGFloat(panels)
    let base = context(width, height)
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(0xFFF1EC), rgb(0xFFFAF7)] as CFArray, locations: [0, 1])!
    base.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

    // Farbflächen: jede sitzt auf einer Bildgrenze, damit sie in zwei Bildern zu sehen ist
    let blobs = context(width, height)
    let colors: [UInt32] = [0xFF8A73, 0xFFC27A, 0xF06292, 0xFF9E80, 0xB39DDB, 0xFFB199, 0xFF7A6B]
    for i in 0...panels {
        let x = panel * CGFloat(i) + (i.isMultiple(of: 2) ? -0.08 : 0.08) * panel
        let y = h * (i.isMultiple(of: 2) ? 0.62 : 0.30)
        let r = panel * (i.isMultiple(of: 2) ? 0.55 : 0.45)
        blobs.setFillColor(rgb(colors[i % colors.count], 0.55))
        blobs.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    let blurred = CIImage(cgImage: blobs.makeImage()!).clampedToExtent()
        .applyingGaussianBlur(sigma: Double(panel) * 0.12).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    let ci = CIContext()
    base.draw(ci.createCGImage(blurred, from: blurred.extent)!, in: CGRect(x: 0, y: 0, width: w, height: h))

    // Band: eine weiche Welle (eine Schwingung über zwei Bilder), die von Bild zu Bild weiterläuft
    let band = CGMutablePath()
    let steps = panels * 40
    for step in 0...steps {
        let x = -panel * 0.1 + (w + panel * 0.2) * CGFloat(step) / CGFloat(steps)
        let y = h * 0.44 + h * 0.10 * sin(x / panel * .pi + 0.6)
        step == 0 ? band.move(to: CGPoint(x: x, y: y)) : band.addLine(to: CGPoint(x: x, y: y))
    }
    base.saveGState()
    base.addPath(band)
    base.setLineWidth(panel * 0.16)
    base.setLineCap(.round)
    base.replacePathWithStrokedPath()
    base.clip()
    let bandGradient = CGGradient(colorsSpace: space, colors: [rgb(0xE8453B, 0.85), rgb(0xFF8A5B, 0.85), rgb(0xF06292, 0.85),
                                                               rgb(0xE8453B, 0.85)] as CFArray, locations: [0, 0.35, 0.7, 1])!
    base.drawLinearGradient(bandGradient, start: .zero, end: CGPoint(x: w, y: 0), options: [])
    base.restoreGState()
    return base.makeImage()!
}

// MARK: Überschrift

/// Zweizeilige Überschrift, mittig; *markierte* Teile in Earnote-Rot. Schrumpft, bis sie passt.
func drawCaption(_ text: String, in rect: CGRect, maxSize: CGFloat, ctx: CGContext) {
    var size = maxSize
    while true {
        let base = NSFont.systemFont(ofSize: size, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 0.95
        let attributed = NSMutableAttributedString()
        for (i, part) in text.components(separatedBy: "*").enumerated() {
            attributed.append(NSAttributedString(string: part, attributes: [
                .font: font, .paragraphStyle: paragraph, .kern: -size * 0.02,
                .foregroundColor: NSColor(cgColor: i.isMultiple(of: 2) ? ink : brand)!,
            ]))
        }
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                                                               CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil)
        if fit.height <= rect.height || size < 40 {
            let box = CGRect(x: rect.minX, y: rect.midY - fit.height / 2, width: rect.width, height: ceil(fit.height) + 2)
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: box, transform: nil), nil), ctx)
            return
        }
        size -= 4
    }
}

// MARK: Gerät

/// Gerät mit Rahmen: dunkler Rand, schmaler heller Saum, Bildschirm, beim iPhone die Dynamic Island
func drawDevice(_ shot: CGImage, screen: CGRect, device: Device, ctx: CGContext) {
    let bezel = screen.width * device.bezel
    let screenRadius = screen.width * device.screenCorner
    let body = screen.insetBy(dx: -bezel, dy: -bezel)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: screenRadius + bezel, cornerHeight: screenRadius + bezel, transform: nil)

    // Schatten
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -body.width * 0.03), blur: body.width * 0.09, color: rgb(0x5A1E14, 0.30))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x1B1B1D))
    ctx.fillPath()
    ctx.restoreGState()
    // Seitentasten
    ctx.setFillColor(rgb(0x2A2A2C))
    let key = bezel * 0.55
    for (y, l) in [(0.80, 0.06), (0.71, 0.10), (0.59, 0.10)] {
        ctx.fill(CGRect(x: body.minX - key * 0.6, y: body.minY + body.height * CGFloat(y), width: key, height: body.height * CGFloat(l)))
    }
    ctx.fill(CGRect(x: body.maxX - key * 0.4, y: body.minY + body.height * 0.68, width: key, height: body.height * 0.14))
    // Titan-Saum
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(rgb(0x6E6E73))
    ctx.setLineWidth(bezel * 0.14)
    ctx.strokePath()
    // Bildschirm
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shot, in: screen)
    ctx.restoreGState()
    if device.island {
        let iw = screen.width * 0.285, ih = screen.width * 0.083
        ctx.addPath(CGPath(roundedRect: CGRect(x: screen.midX - iw / 2, y: screen.maxY - screen.width * 0.032 - ih,
                                               width: iw, height: ih), cornerWidth: ih / 2, cornerHeight: ih / 2, transform: nil))
        ctx.setFillColor(rgb(0x000000))
        ctx.fillPath()
    }
}

// MARK: Zusammensetzen

var made = 0
for language in captions.keys.sorted() {
    for device in devices {
        let texts = (device.name == "ipad" ? ipadCaptions : captions)[language] ?? []
        let raw = root.appendingPathComponent("raw/\(language)/\(device.name)")
        let shots = texts.indices.map { load(raw.appendingPathComponent("\($0 + 1).png")) }
        let present = shots.compactMap { $0 }.count
        guard present > 0 else { continue }
        let n = texts.count, w = CGFloat(device.width), h = CGFloat(device.height)
        let background = panoramaBackground(width: device.width * n, height: device.height, panels: n)
        let pano = context(device.width * n, device.height)
        pano.draw(background, in: CGRect(x: 0, y: 0, width: w * CGFloat(n), height: h))

        for (index, shot) in shots.enumerated() {
            guard let shot else { continue }
            let x0 = w * CGFloat(index)
            let caption = texts[index]
            let header = h * 0.22
            drawCaption(caption, in: CGRect(x: x0 + w * 0.07, y: h - header, width: w * 0.86, height: header * 0.78),
                        maxSize: w * 0.105, ctx: pano)
            let sw = w * device.screenWidth
            let sh = sw * CGFloat(shot.height) / CGFloat(shot.width)
            let screen = CGRect(x: x0 + (w - sw) / 2, y: h - header - h * 0.02 - sh, width: sw, height: sh)
            drawDevice(shot, screen: screen, device: device, ctx: pano)
        }
        let full = pano.makeImage()!
        let dir = root.appendingPathComponent("\(language)/\(device.name)")
        for index in shots.indices where shots[index] != nil {
            let crop = full.cropping(to: CGRect(x: device.width * index, y: 0, width: device.width, height: device.height))!
            // Ohne Transparenz speichern – App Store Connect lehnt Bilder mit Alphakanal ab
            let flat = CGContext(data: nil, width: device.width, height: device.height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            flat.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            save(flat.makeImage()!, to: dir.appendingPathComponent("\(index + 1).png"))
            made += 1
        }
        save(full, to: dir.appendingPathComponent("panorama.png"))
        print("✓ \(language)/\(device.name): \(present) Bilder + panorama.png")
    }
}
print(made == 0 ? "Keine Rohbilder gefunden unter \(root.path)/raw/<de|en>/<iphone|ipad>/1.png …" : "\(made) Bilder fertig.")
