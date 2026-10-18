// Draws Macro Track's app icon set (iOS light/dark/tinted).
// Run from the repo root: swift Scripts/make-macro-icons.swift
// The glyph is drawn by hand: SF Symbols may not be used in app icons.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Apps/MacroTrack/iOS/Resources/Assets.xcassets")

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
            colors: [color(0x4FD69A).cgColor, color(0x0E8A5F).cgColor] as CFArray, locations: [0, 1])!
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
            colors: [color(0x10301F).cgColor, color(0x06110B).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
    case .tinted:
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(canvas)
    }

    // A macro donut: protein, carbs and fat as three arcs of one ring.
    let ink: NSColor = variant == .dark ? color(0x7CF0B8) : .white
    if variant == .light {
        ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 34, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setLineCap(.round)
    ctx.setLineWidth(118)
    let center = CGPoint(x: 512, y: 512)
    let radius = 300.0
    var start = -90.0
    // Round caps reach into the gaps, so each arc is drawn shorter than its share.
    for (sweep, alpha) in [(150.0, CGFloat(1)), (120, 0.8), (90, 0.6)] {
        let a0 = (start + 21) * .pi / 180
        let a1 = (start + sweep - 21) * .pi / 180
        ctx.setStrokeColor(ink.withAlphaComponent(alpha).cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.strokePath()
        start += sweep
    }
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
