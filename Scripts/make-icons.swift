// Draws the app icon set (iOS light/dark/tinted, macOS, visionOS, and the Watch).
// Run from the repo root: swift Scripts/make-icons.swift
// The glyph is drawn by hand: SF Symbols may not be used in app icons.
import AppKit
import SwiftUI

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Apps/LiftTrack/iOS/Resources/Assets.xcassets")
let watchAssets = root.appending(path: "Apps/LiftTrack/Watch/Assets.xcassets")

enum Variant { case light, dark, tinted }

/// The parts of the icon, which visionOS takes as separate layers of an image stack.
struct Layers: OptionSet {
    let rawValue: Int
    static let background = Layers(rawValue: 1 << 0)
    static let glyph = Layers(rawValue: 1 << 1)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// With a `corner`, the art goes on a tile `inset` from the edges with a drop shadow, transparent
/// around it, the way macOS draws app icons.
func render(
    _ variant: Variant, size: Int = 1024, inset: CGFloat = 0, corner: CGFloat = 0, layers: Layers = [.background, .glyph]
) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
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
        // The tile is Apple's continuous-corner shape, painted in one transparency layer so the shadow
        // falls from the finished tile and doesn't darken its edge. Shadows live in the bitmap's own
        // space, which the scale and flip above don't reach: y points up, and sizes scale by hand.
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: canvas).cgPath)
        ctx.clip()
    }

    // Background
    if layers.contains(.background) {
        switch variant {
        case .light:
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [color(0x6E8BFF).cgColor, color(0x2433C9).cgColor] as CFArray,
                locations: [0, 1])!
            ctx.drawLinearGradient(
                gradient, start: CGPoint(x: canvas.minX, y: canvas.minY),
                end: CGPoint(x: canvas.minX + canvas.width * 0.7, y: canvas.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            let glow = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    NSColor.white.withAlphaComponent(0.28).cgColor,
                    NSColor.white.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1])!
            ctx.drawRadialGradient(
                glow, startCenter: CGPoint(x: canvas.minX + canvas.width * 0.25, y: canvas.minY + canvas.height * 0.15),
                startRadius: 0, endCenter: CGPoint(x: canvas.minX + canvas.width * 0.25, y: canvas.minY + canvas.height * 0.15),
                endRadius: canvas.width * 0.75, options: [])
        case .dark:
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [color(0x18203F).cgColor, color(0x080A14).cgColor] as CFArray,
                locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])
        case .tinted:
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(canvas)
        }
    }

    // Glyph, laid out in the inner canvas.
    if layers.contains(.glyph) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: canvas.minX + canvas.width * x / 1024, y: canvas.minY + canvas.height * y / 1024)
        }
        let k = canvas.width / 1024
        let ink: NSColor =
            switch variant {
            case .dark: color(0x9DB0FF)
            case .tinted: .white
            default: .white
            }

        // A barbell: the bar, then plates from big to small on each side, rounded like rubber
        // bumpers. One transparency layer, so the shadow falls from the whole shape at once. On its
        // own (visionOS) the glyph has no shadow: the system casts one from the layer.
        if variant == .light && layers.contains(.background) {
            ctx.setShadow(
                offset: CGSize(width: 0, height: 16 * k * s), blur: 34 * k * s, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(ink.cgColor)
        ctx.addPath(
            CGPath(
                roundedRect: CGRect(origin: p(170, 486), size: CGSize(width: 684 * k, height: 52 * k)),
                cornerWidth: 26 * k, cornerHeight: 26 * k, transform: nil))
        for (offset, width, height) in [(196.0, 64.0, 360.0), (272.0, 52.0, 270.0), (336.0, 40.0, 180.0)] {
            for side in [-1.0, 1.0] {
                let x = 512 + side * offset - width / 2
                ctx.addPath(
                    CGPath(
                        roundedRect: CGRect(origin: p(x, 512 - height / 2), size: CGSize(width: width * k, height: height * k)),
                        cornerWidth: 22 * k, cornerHeight: 22 * k, transform: nil))
            }
        }
        ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }

    if corner > 0 {
        ctx.endTransparencyLayer()
    }
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

/// PNGs are made `opaque` unless they're meant to be see-through: the Mac icons, and the visionOS
/// layers that sit over the background.
func write(_ data: Data, _ path: String, transparent: Bool = false) throws {
    let url = assets.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (path.hasSuffix(".png") && !transparent ? opaque(data) : data).write(to: url)
}

let info = #""info" : { "author" : "xcode", "version" : 1 }"#

// iOS: single size with dark and tinted appearances.
try write(render(.light), "AppIcon.appiconset/icon-ios.png")
try write(render(.dark), "AppIcon.appiconset/icon-ios-dark.png")
try write(render(.tinted), "AppIcon.appiconset/icon-ios-tinted.png")

// macOS: the art on a tile of Apple's icon grid (824 of 1024 points, a 185.4 corner), five sizes
// at 1x and 2x. Each is drawn at its own pixels rather than scaled down from the big one.
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try write(render(.light, size: pixels, inset: 100, corner: 185.4), "AppIcon.appiconset/icon-mac-\(pixels).png", transparent: true)
}
let macImages = [16, 32, 128, 256, 512].flatMap { points in
    [1, 2].map { scale in
        #"{ "filename" : "icon-mac-\#(points * scale).png", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#
    }
}
let appIcon = """
    {
      "images" : [
        { "filename" : "icon-ios.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "icon-ios-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "icon-ios-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        \(macImages.joined(separator: ",\n    "))
      ],
      \(info)
    }
    """
try write(Data(appIcon.utf8), "AppIcon.appiconset/Contents.json")

// visionOS: a stack of layers that the system parallaxes and lights itself, shadows included, so
// the background and the glyph go in flat and the middle layer is left empty. Only the back layer
// is opaque: a full square, which visionOS masks to a circle.
let stack = "AppIconVision.solidimagestack"
let visionLayers: [(name: String, layers: Layers)] = [("Front", .glyph), ("Middle", []), ("Back", .background)]
let stackLayers = visionLayers.map { #"{ "filename" : "\#($0.name).solidimagestacklayer" }"# }
try write(Data(#"{ "layers" : [ \#(stackLayers.joined(separator: ", ")) ], \#(info) }"#.utf8), "\(stack)/Contents.json")
for (name, layers) in visionLayers {
    let folder = "\(stack)/\(name).solidimagestacklayer"
    let file = "vision-\(name.lowercased()).png"
    try write(render(.light, layers: layers), "\(folder)/Content.imageset/\(file)", transparent: !layers.contains(.background))
    try write(Data("{ \(info) }".utf8), "\(folder)/Contents.json")
    try write(
        Data(#"{ "images" : [ { "filename" : "\#(file)", "idiom" : "vision", "scale" : "2x" } ], \#(info) }"#.utf8),
        "\(folder)/Content.imageset/Contents.json")
}

// watchOS: one round-cropped 1024 image.
let watchIcon = watchAssets.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: watchIcon, withIntermediateDirectories: true)
try opaque(render(.light)).write(to: watchIcon.appending(path: "icon-watch.png"))
try Data(
    #"{ "images" : [ { "filename" : "icon-watch.png", "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024" } ], "info" : { "author" : "xcode", "version" : 1 } }"#
        .utf8
)
.write(to: watchIcon.appending(path: "Contents.json"))
print("Icons written to \(assets.path) and \(watchAssets.path)")
