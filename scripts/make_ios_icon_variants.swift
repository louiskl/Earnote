// App-Symbole für das Dankeschön-Paket: dasselbe Motiv wie das iPhone-Icon (Maße vom Original abgemessen), andere Farben.
// Erzeugt je Variante ein AppIcon-<Name>.appiconset (1024) und ein IconPreview-<Name>.imageset (für die Auswahl in der App).
// Aufruf: swift scripts/make_ios_icon_variants.swift EarnoteiOS/Resources/Assets.xcassets
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Variant {
    let name: String
    let background: (UInt32, UInt32)   // Verlauf oben → unten
    let page: UInt32
    let wave: (UInt32, UInt32)         // Balken oben → unten
    let fold: UInt32
    let shadow: CGFloat
    var barColors: [UInt32]? = nil    // je Balken eine eigene Farbe statt des Verlaufs
    var stripes: [UInt32]? = nil      // Hintergrund in waagerechten Streifen statt Verlauf
    var barGlow: UInt32? = nil        // Leuchten um die Balken (Terminal)
}

let variants = [
    Variant(name: "Ozean", background: (0x4FB3FF, 0x2563EB), page: 0xFFFFFF, wave: (0x3B8BF5, 0x2563EB), fold: 0xCFE4FF, shadow: 0.35),
    Variant(name: "Salbei", background: (0x6FD6A0, 0x1E9468), page: 0xFFFFFF, wave: (0x33B37D, 0x1E9468), fold: 0xD3F2E2, shadow: 0.35),
    Variant(name: "Lavendel", background: (0xC4A3FF, 0x7C4DEB), page: 0xFFFFFF, wave: (0xA07AF7, 0x7C4DEB), fold: 0xE9DDFF, shadow: 0.35),
    Variant(name: "Mitternacht", background: (0x343A4A, 0x0E1118), page: 0xFFFFFF, wave: (0xFF7758, 0xE8364E), fold: 0xC9CEDA, shadow: 0.6),
    Variant(name: "Hell", background: (0xFFFFFF, 0xF1EDEA), page: 0xEE4B4E, wave: (0xFFFFFF, 0xFFFFFF), fold: 0xFFB3A6, shadow: 0.18),
    Variant(name: "Regenbogen", background: (0, 0), page: 0xFFFFFF, wave: (0, 0), fold: 0xE6E6EA, shadow: 0.3,
            barColors: [0xE8453B, 0xF5891F, 0xF2C230, 0x2FA84F, 0x2F7CF6, 0x5B4BDB, 0x9B3FC8],
            stripes: [0xE8453B, 0xF5891F, 0xF2C230, 0x2FA84F, 0x2F7CF6, 0x8A3FC8]),
    Variant(name: "Retro", background: (0xF2B33D, 0xD2601A), page: 0xFFF4DE, wave: (0, 0), fold: 0xF3D9A8, shadow: 0.3,
            barColors: [0x7A3B1D, 0xD2601A, 0xE8A92E, 0x7A3B1D, 0xD2601A, 0xE8A92E, 0x7A3B1D]),
    Variant(name: "Terminal", background: (0x0C130E, 0x000000), page: 0x0F1D13, wave: (0x6DFF95, 0x2BC957), fold: 0x1F3A27, shadow: 0.8,
            barGlow: 0x3DDC6B),
]

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha])!
}

// Maße des Originals (Ursprung oben links)
let page = CGRect(x: 257, y: 195, width: 511, height: 634)
let foldSize: CGFloat = 154
let bars: [(x: CGFloat, top: CGFloat, bottom: CGFloat)] = [
    (309, 532, 593), (370, 497, 628), (431, 455, 670), (492, 511, 614), (553, 426, 698), (614, 482, 642), (674, 525, 599),
]
let barWidth: CGFloat = 40

func render(_ v: Variant, to url: URL, pixels: Int) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let s = CGFloat(pixels) / CGFloat(size)
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)   // ab hier: y von oben, wie abgemessen

    if let stripes = v.stripes {
        let height = CGFloat(size) / CGFloat(stripes.count)
        for (i, stripe) in stripes.enumerated() {
            ctx.setFillColor(color(stripe))
            ctx.fill(CGRect(x: 0, y: CGFloat(i) * height, width: CGFloat(size), height: height + 1))
        }
    } else {
        let background = CGGradient(colorsSpace: space, colors: [color(v.background.0), color(v.background.1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    }

    // Blatt mit Eselsohr und weichem Schatten
    let outline = CGMutablePath()
    outline.move(to: CGPoint(x: page.minX, y: page.minY))
    outline.addLine(to: CGPoint(x: page.maxX - foldSize, y: page.minY))
    outline.addLine(to: CGPoint(x: page.maxX, y: page.minY + foldSize))
    outline.addLine(to: CGPoint(x: page.maxX, y: page.maxY))
    outline.addLine(to: CGPoint(x: page.minX, y: page.maxY))
    outline.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 36, color: color(0x000000, v.shadow))
    ctx.addPath(outline)
    ctx.setFillColor(color(v.page))
    ctx.fillPath()
    ctx.restoreGState()

    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: page.maxX - foldSize, y: page.minY))
    fold.addLine(to: CGPoint(x: page.maxX - foldSize, y: page.minY + foldSize))
    fold.addLine(to: CGPoint(x: page.maxX, y: page.minY + foldSize))
    fold.closeSubpath()
    ctx.addPath(fold)
    ctx.setFillColor(color(v.fold))
    ctx.fillPath()

    // Schallwelle: je Balken eine Farbe oder ein Verlauf über alle Balken
    func barPath(_ bar: (x: CGFloat, top: CGFloat, bottom: CGFloat)) -> CGPath {
        CGPath(roundedRect: CGRect(x: bar.x, y: bar.top, width: barWidth, height: bar.bottom - bar.top),
               cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    }
    if let glow = v.barGlow {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 28, color: color(glow, 0.9))
        ctx.setFillColor(color(glow))
        bars.forEach { ctx.addPath(barPath($0)) }
        ctx.fillPath()
        ctx.restoreGState()
    }
    if let barColors = v.barColors {
        for (bar, barColor) in zip(bars, barColors) {
            ctx.addPath(barPath(bar))
            ctx.setFillColor(color(barColor))
            ctx.fillPath()
        }
    } else {
        ctx.saveGState()
        bars.forEach { ctx.addPath(barPath($0)) }
        ctx.clip()
        let wave = CGGradient(colorsSpace: space, colors: [color(v.wave.0), color(v.wave.1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(wave, start: CGPoint(x: 0, y: 426), end: CGPoint(x: 0, y: 698), options: [])
        ctx.restoreGState()
    }

    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func write(_ json: String, to dir: URL) {
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try! json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
for v in variants {
    let icon = catalog.appendingPathComponent("AppIcon-\(v.name).appiconset")
    write("""
    {
      "images" : [
        { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """, to: icon)
    render(v, to: icon.appendingPathComponent("icon-1024.png"), pixels: 1024)

    let preview = catalog.appendingPathComponent("IconPreview-\(v.name).imageset")
    write("""
    {
      "images" : [
        { "filename" : "preview.png", "idiom" : "universal", "scale" : "3x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """, to: preview)
    render(v, to: preview.appendingPathComponent("preview.png"), pixels: 180)
}
