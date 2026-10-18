// Draws Mind Track's app icon set (iOS light/dark/tinted).
// Run from the repo root: swift Scripts/make-mind-icons.swift
// The glyph is drawn by hand: SF Symbols may not be used in app icons.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Apps/MindTrack/iOS/Resources/Assets.xcassets")

enum Variant { case light, dark, tinted }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ variant: Variant, size: Int = 1024) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    switch variant {
    case .light:
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(0xA77BFF).cgColor, color(0x5B2BD1).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(
            gradient, start: .zero, end: CGPoint(x: 720, y: 1024),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glow = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [NSColor.white.withAlphaComponent(0.3).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1])!
        ctx.drawRadialGradient(
            glow, startCenter: CGPoint(x: 256, y: 150), startRadius: 0, endCenter: CGPoint(x: 256, y: 150),
            endRadius: 770, options: [])
    case .dark:
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(0x22143F).cgColor, color(0x0C0717).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
    case .tinted:
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(canvas)
    }

    // Spaced repetition drawn: three forgetting curves, each reviewed back up a little higher and
    // fading a little slower, ending in a dot.
    let ink: NSColor = variant == .dark ? color(0xC7A8FF) : .white
    if variant == .light {
        ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 34, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(ink.cgColor)
    ctx.setFillColor(ink.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(64)
    let path = CGMutablePath()
    var top = CGPoint(x: 128, y: 676)
    path.move(to: top)
    for i in 0..<3 {
        let drop = CGFloat(150 - i * 45)
        let end = CGPoint(x: top.x + 190, y: top.y + drop)
        path.addCurve(to: end, control1: CGPoint(x: top.x + 50, y: top.y + drop * 0.85), control2: CGPoint(x: end.x - 80, y: end.y))
        top = CGPoint(x: end.x + 14, y: end.y - drop - 150)
        path.addLine(to: top)
    }
    ctx.addPath(path)
    ctx.strokePath()
    ctx.fillEllipse(in: CGRect(x: top.x + 58, y: top.y - 52, width: 104, height: 104))
    ctx.endTransparencyLayer()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The same image without an alpha channel: App Store Connect rejects app icons that have one,
/// even when every pixel is opaque.
func opaque(_ png: Data) -> Data {
    let image = NSBitmapImageRep(data: png)!.cgImage!
    let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    let url = assets.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (path.hasSuffix(".png") ? opaque(data) : data).write(to: url)
}

try write(render(.light), "AppIcon.appiconset/icon-ios.png")
try write(render(.dark), "AppIcon.appiconset/icon-ios-dark.png")
try write(render(.tinted), "AppIcon.appiconset/icon-ios-tinted.png")
try write(
    Data(
        """
        {
          "images" : [
            { "filename" : "icon-ios.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
            { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "icon-ios-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
            { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "icon-ios-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """.utf8), "AppIcon.appiconset/Contents.json")
print("Icons written to \(assets.path)")
