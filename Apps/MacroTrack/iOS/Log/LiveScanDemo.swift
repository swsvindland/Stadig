#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import FoodDatabase
import FoodIntelligence
import SystemCore

/// A live scan without a camera, for the simulator (-liveScanDemo): a rendered package front, then
/// a nutrition or Supplement Facts panel taller than the screen, panned slowly from top to bottom
/// and read frame by frame by the same OCR the camera's frames go through. A barcode the catalogs
/// don't know is "seen" on the way.
enum LiveScanDemo {
    static var enabled: Bool { LaunchOptions.current.has("-liveScanDemo") }
    /// A valid UPC-A that neither catalog has.
    /// A code the catalogs don't know, so the label is read; `-liveScanBarcode 898248001411` (siggi's
    /// skyr) is one they do, for the found food's card.
    static var barcode: String { LaunchOptions.current.value(after: "-liveScanBarcode") ?? "098765432105" }

    @MainActor
    static func run(_ scan: LiveScan) async {
        let frames = scan.kind == .food ? foodFrames() : supplementFrames()
        for (i, frame) in frames.enumerated() {
            guard !Task.isCancelled, !scan.finished else { return }
            let text = try? await LabelOCR.frame(frame)
            // The picture and what was read in it change together.
            scan.still = frame
            if let text { scan.add(text, parsed: .read(text, as: scan.kind), aspect: Double(frame.width) / Double(frame.height)) }
            if i == 2 { scan.barcodeSeen(barcode, .upcA) }
            try? await Task.sleep(for: .milliseconds(450))
        }
    }

    /// Phone-shaped frames (9:16): the front three times, then the panel, which is taller than a
    /// frame, a slice at a time with a little hand shake.
    static let width = 700
    static var frameHeight: Int { width * 16 / 9 }

    static func foodFrames() -> [CGImage] {
        let front = render(
            rows: [
                ("Oat Crunch", nil, 120, true), ("HONEY ALMOND", nil, 52, true), ("20g PROTEIN", nil, 52, false),
                ("Whole grain oats", nil, 44, false),
            ], minHeight: frameHeight)
        let panel = render(
            rows: [
                ("Nutrition Facts", nil, 60, true), ("8 servings per container", nil, 38, false), ("Serving size 2/3 cup (55g)", nil, 38, true),
                ("Amount per serving", nil, 32, true), ("Calories", "230", 54, true), ("% Daily Value*", nil, 32, true),
                ("Total Fat 8g", "10%", 44, true), ("Saturated Fat 1g", "5%", 44, false), ("Trans Fat 0g", nil, 44, false),
                ("Cholesterol 0mg", "0%", 44, true), ("Sodium 160mg", "7%", 44, true), ("Total Carb. 37g", "13%", 44, true),
                ("Dietary Fiber 4g", "14%", 44, false), ("Total Sugars 12g", nil, 44, false), ("Protein 3g", nil, 44, true),
                ("Vitamin D 2mcg", "10%", 44, false), ("Calcium 260mg", "20%", 44, false), ("Iron 8mg", "45%", 44, false),
            ], spacing: 2.7)
        return [front, front, front] + pan(panel)
    }

    static func supplementFrames() -> [CGImage] {
        let front = render(
            rows: [
                ("Fish Oil", nil, 120, true), ("1200 mg", nil, 60, true), ("Heart health", nil, 44, false),
                ("100 softgels", nil, 40, false),
            ], minHeight: frameHeight)
        let panel = render(
            rows: [
                ("Supplement Facts", nil, 58, true), ("Serving Size 2 Softgels", nil, 40, true), ("Servings Per Container 50", nil, 38, false),
                ("Amount Per Serving", "% DV", 34, true), ("Calories 20", nil, 44, false), ("Total Fat 2 g", "3%", 44, false),
                ("Vitamin D3 25 mcg", "125%", 44, false), ("Fish Oil 2,400 mg", "†", 44, false), ("EPA 650 mg", "†", 44, false),
                ("DHA 450 mg", "†", 44, false), ("Other Omega-3s 120 mg", "†", 44, false), ("Vitamin E 13.5 mg", "90%", 44, false),
                ("Lemon Oil 10 mg", "†", 44, false), ("Rosemary Extract 2 mg", "†", 44, false), ("† Daily Value not established.", nil, 30, false),
                ("Other ingredients: Gelatin, Glycerin.", nil, 30, false),
            ], spacing: 2.9)
        return [front, front, front] + pan(panel)
    }

    /// Frame-sized slices of a tall image, top to bottom in steps of under half a frame.
    static func pan(_ image: CGImage) -> [CGImage] {
        let height = Double(image.height)
        let window = min(height, Double(frameHeight))
        let steps = max(3, Int(((height - window) / (window * 0.3)).rounded(.up)) + 1)
        var frames: [CGImage] = []
        for step in 0..<steps {
            let top = Double(step) * (height - window) / Double(steps - 1)
            for shake in [0.0, 10.0] {
                let y = max(0, min(height - window, top + shake))
                if let slice = image.cropping(to: CGRect(x: 0, y: y, width: Double(image.width), height: window)) { frames.append(slice) }
            }
        }
        return frames
    }

    /// Black text on a cream package, a row per line, with an optional value at the right edge.
    static func render(rows: [(String, String?, CGFloat, Bool)], minHeight: Int = 0, spacing: CGFloat = 1.75) -> CGImage {
        let height = max(minHeight, Int(rows.map { $0.2 * spacing }.reduce(0, +)) + 160)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool, alignRight: Bool = false) {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: text,
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
                    ]))
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: alignRight ? x - lineWidth : x, y: y)
            CTLineDraw(line, context)
        }
        var y = CGFloat(height) - 110
        for (text, right, size, bold) in rows {
            draw(text, x: 40, y: y, size: size, bold: bold)
            if let right { draw(right, x: CGFloat(width) - 40, y: y, size: size, bold: bold, alignRight: true) }
            y -= size * spacing
        }
        return context.makeImage()!
    }
}
#endif
