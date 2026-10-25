// Draws Stadig Macro's app icon set (iOS light/dark/tinted, macOS, visionOS, and the Watch).
// Run from the repo root: swift Scripts/make-macro-icons.swift
// The glyph is drawn by hand: SF Symbols may not be used in app icons.
import AppKit
import SwiftUI

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Apps/MacroTrack/iOS/Resources/Assets.xcassets")
let watchAssets = root.appending(path: "Apps/MacroTrack/Watch/Assets.xcassets")

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
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    if corner > 0 {
        // The tile is Apple's continuous-corner shape, painted in one transparency layer so the shadow
        // falls from the finished tile and doesn't darken its edge. Shadows live in the bitmap's own
        // space, which the scale and flip above don't reach: y points up, and sizes scale by hand.
        let tile = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: tile).cgPath)
        ctx.clip()
    }
    // The art is drawn on the full 1024 canvas, then scaled down onto the tile.
    let k = (1024 - inset * 2) / 1024
    ctx.translateBy(x: inset, y: inset)
    ctx.scaleBy(x: k, y: k)
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    if layers.contains(.background) {
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
    }

    // A macro donut: protein, carbs and fat as three arcs of one ring. On its own (visionOS) the
    // glyph has no shadow: the system casts one from the layer.
    if layers.contains(.glyph) {
        let ink: NSColor = variant == .dark ? color(0x7CF0B8) : .white
        if variant == .light && layers.contains(.background) {
            ctx.setShadow(
                offset: CGSize(width: 0, height: 16 * k * s), blur: 34 * k * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
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
try write(
    Data(
        """
        {
          "images" : [
            { "filename" : "icon-ios.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
            { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "icon-ios-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
            { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "icon-ios-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
            \(macImages.joined(separator: ",\n    "))
          ],
          \(info)
        }
        """.utf8), "AppIcon.appiconset/Contents.json")

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
    #"{ "images" : [ { "filename" : "icon-watch.png", "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024" } ], \#(info) }"#.utf8
)
.write(to: watchIcon.appending(path: "Contents.json"))
print("Icons written to \(assets.path) and \(watchAssets.path)")
