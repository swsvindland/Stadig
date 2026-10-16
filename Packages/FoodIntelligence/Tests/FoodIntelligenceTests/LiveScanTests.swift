import CoreGraphics
import CoreText
import FoodDatabase
import Foundation
import SystemCore
import Testing
@testable import FoodIntelligence

/// A live scan as the camera sees it: a label taller than one frame, read a slice at a time by
/// real Vision OCR, with the package's front in between.
@Suite("Live scanning")
struct LiveScanTests {
    let panel: [(String, String?)] = [
        ("Nutrition Facts", nil), ("8 servings per container", nil), ("Serving size 2/3 cup (55g)", nil), ("Calories", "230"),
        ("Total Fat 8g", "10%"), ("Saturated Fat 1g", "5%"), ("Trans Fat 0g", nil), ("Cholesterol 0mg", "0%"),
        ("Sodium 160mg", "7%"), ("Total Carbohydrate 37g", "13%"), ("Dietary Fiber 4g", "14%"), ("Total Sugars 12g", nil),
        ("Includes 10g Added Sugars", "20%"), ("Protein 3g", nil), ("Vitamin D 2mcg", "10%"), ("Calcium 260mg", "20%"),
        ("Iron 8mg", "45%"),
    ]

    /// Slices of the label from `from` to `to` (0–1 of its height), as frames a slow pan gives.
    func slices(_ image: CGImage, _ ranges: [(Double, Double)]) -> [CGImage] {
        ranges.compactMap { from, to in
            image.cropping(to: CGRect(x: 0, y: Double(image.height) * from, width: Double(image.width), height: Double(image.height) * (to - from)))
        }
    }

    @Test func aPannedLabelFillsInFrameByFrame() async throws {
        let label = renderLabel(panel, sideways: false)
        // No slice holds both calories and protein.
        let frames = slices(label, [(0, 0.4), (0.02, 0.42), (0.3, 0.7), (0.32, 0.72), (0.6, 1), (0.58, 0.98)])
        var live = LiveLabel()
        var lines: [String] = []
        for frame in frames {
            let text = try await LabelOCR.frame(frame)
            lines += text.lines
            live.add(NutritionLabel.frame(boxes: text.boxes))
        }
        #expect(live.panelFrames == frames.count, "\(lines)")
        for (key, value) in [("kcal", 230.0), ("fat", 8), ("carbs", 37), ("protein", 3), ("sodium", 160), ("fiber", 4)] {
            #expect(live.value(key) == .locked(value), "\(key): \(live.value(key)) \(lines)")
        }
        #expect(live.ready)
        let reading = try #require(live.reading)
        #expect(reading.servingGrams == 55)
        #expect(reading.extras["calcium"] == 260)
    }

    @Test func thePackageFrontGivesTheNameAndNoValues() async throws {
        let front = renderFront(title: "Oat Crunch", lines: ["HONEY ALMOND", "20g PROTEIN", "Whole grain oats"])
        let text = try await LabelOCR.frame(front)
        #expect(text.headline == "Oat Crunch", "\(text.lines)")
        #expect(!NutritionLabel.frame(boxes: text.boxes).isPanel)
        #expect(!text.regions.isEmpty)
    }

    /// A box's front: a big name, then small claims.
    func renderFront(title: String, lines: [String]) -> CGImage {
        let (width, height) = (900, 900)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func draw(_ text: String, y: CGFloat, size: CGFloat) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]))
            context.textPosition = CGPoint(x: 60, y: y)
            CTLineDraw(line, context)
        }
        draw(title, y: 700, size: 120)
        for (i, line) in lines.enumerated() { draw(line, y: CGFloat(520 - i * 90), size: 44) }
        return context.makeImage()!
    }
}
