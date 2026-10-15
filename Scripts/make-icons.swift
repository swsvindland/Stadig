// Draws the app icon set (iOS light/dark/tinted, and the Watch).
// Run from the repo root: swift Scripts/make-icons.swift
// The glyph is drawn by hand: SF Symbols may not be used in app icons.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Apps/LiftTrack/iOS/Resources/Assets.xcassets")
let watchAssets = root.appending(path: "Apps/LiftTrack/Watch/Assets.xcassets")

enum Variant { case light, dark, tinted }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ variant: Variant, size: Int = 1024, inset: CGFloat = 0, corner: CGFloat = 0) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)
    // Work in a top-left origin, 1024-point canvas.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    let canvas = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    if corner > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.clip()
    }

    // Background
    switch variant {
    case .light:
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [color(0x6E8BFF).cgColor, color(0x2433C9).cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: canvas.minX, y: canvas.minY),
                               end: CGPoint(x: canvas.maxX * 0.7, y: canvas.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [NSColor.white.withAlphaComponent(0.28).cgColor,
                                       NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: canvas.minX + canvas.width * 0.25, y: canvas.minY + canvas.height * 0.15),
                               startRadius: 0, endCenter: CGPoint(x: canvas.minX + canvas.width * 0.25, y: canvas.minY + canvas.height * 0.15),
                               endRadius: canvas.width * 0.75, options: [])
    case .dark:
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [color(0x18203F).cgColor, color(0x080A14).cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])
    case .tinted:
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(canvas)
    }

    // Glyph, laid out in the inner canvas.
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: canvas.minX + canvas.width * x / 1024, y: canvas.minY + canvas.height * y / 1024)
    }
    let k = canvas.width / 1024
    let ink: NSColor = switch variant {
    case .dark: color(0x9DB0FF)
    case .tinted: .white
    default: .white
    }

    // A barbell: the bar, then plates from big to small on each side, rounded like rubber
    // bumpers. One transparency layer, so the shadow falls from the whole shape at once.
    if variant == .light {
        ctx.setShadow(offset: CGSize(width: 0, height: 16 * k), blur: 34 * k, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(ink.cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(origin: p(170, 486), size: CGSize(width: 684 * k, height: 52 * k)),
                       cornerWidth: 26 * k, cornerHeight: 26 * k, transform: nil))
    for (offset, width, height) in [(196.0, 64.0, 360.0), (272.0, 52.0, 270.0), (336.0, 40.0, 180.0)] {
        for side in [-1.0, 1.0] {
            let x = 512 + side * offset - width / 2
            ctx.addPath(CGPath(roundedRect: CGRect(origin: p(x, 512 - height / 2), size: CGSize(width: width * k, height: height * k)),
                               cornerWidth: 22 * k, cornerHeight: 22 * k, transform: nil))
        }
    }
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    let url = assets.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

let info = #""info" : { "author" : "xcode", "version" : 1 }"#

// iOS: single size with dark and tinted appearances.
try write(render(.light), "AppIcon.appiconset/icon-ios.png")
try write(render(.dark), "AppIcon.appiconset/icon-ios-dark.png")
try write(render(.tinted), "AppIcon.appiconset/icon-ios-tinted.png")
let appIcon = """
{
  "images" : [
    { "filename" : "icon-ios.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "icon-ios-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "icon-ios-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  \(info)
}
"""
try write(Data(appIcon.utf8), "AppIcon.appiconset/Contents.json")

// watchOS: one round-cropped 1024 image.
let watchIcon = watchAssets.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: watchIcon, withIntermediateDirectories: true)
try render(.light).write(to: watchIcon.appending(path: "icon-watch.png"))
try Data(#"{ "images" : [ { "filename" : "icon-watch.png", "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024" } ], "info" : { "author" : "xcode", "version" : 1 } }"#.utf8)
    .write(to: watchIcon.appending(path: "Contents.json"))
print("Icons written to \(assets.path) and \(watchAssets.path)")
