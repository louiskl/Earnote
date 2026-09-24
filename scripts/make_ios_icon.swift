// iPhone-Icon aus dem Mac-Icon: randloser Verlauf mit dem Motiv, ohne Ecken (iOS rundet selbst).
// Aufruf: swift scripts/make_ios_icon.swift Earnote/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png EarnoteiOS/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let srcRef = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let src = CGImageSourceCreateImageAtIndex(srcRef, 0, nil)!
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let scale = CGFloat(size) / 824
// 1. Kachel des Mac-Icons (100…924) auf die volle Fläche – nur, um ihre Farben im selben Farbraum abzulesen
ctx.draw(src.cropping(to: CGRect(x: 100, y: 100, width: 824, height: 824))!, in: CGRect(x: 0, y: 0, width: size, height: size))
let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
func color(atTop y: Int) -> CGColor {   // y von oben, Spalte Mitte
    let i = (y * size + size / 2) * 4
    return CGColor(colorSpace: space, components: [CGFloat(pixels[i]) / 255, CGFloat(pixels[i + 1]) / 255, CGFloat(pixels[i + 2]) / 255, 1])!
}
let top = color(atTop: 40), bottom = color(atTop: 984)
// 2. Randloser Verlauf mit genau diesen Farben (Speicher beginnt oben, CG-Koordinaten unten)
let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size - 40), end: CGPoint(x: 0, y: 40),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// 3. Motiv (Dokument mit Schatten) an dieselbe Stelle; die runden Ecken des Mac-Icons bleiben draußen, iOS rundet selbst
let motif = CGRect(x: 270, y: 225, width: 485, height: 585)
ctx.draw(src.cropping(to: motif)!, in: CGRect(x: (motif.minX - 100) * scale, y: CGFloat(size) - (motif.maxY - 100) * scale,
                                             width: motif.width * scale, height: motif.height * scale))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
