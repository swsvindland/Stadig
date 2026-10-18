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

    @Test(.needsVisionOCR) func aPannedLabelFillsInFrameByFrame() async throws {
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

    @Test(.needsVisionOCR) func thePackageFrontGivesTheNameAndNoValues() async throws {
        let front = renderFront(title: "Oat Crunch", lines: ["HONEY ALMOND", "20g PROTEIN", "Whole grain oats"])
        let text = try await LabelOCR.frame(front)
        #expect(text.headline == "Oat Crunch", "\(text.lines)")
        #expect(!NutritionLabel.frame(boxes: text.boxes).isPanel)
        #expect(!text.regions.isEmpty)
    }

    @Test func aModelsCheckKeepsOnlyNumbersPrintedOnThePanel() {
        let panel = ["Nutrition Facts", "Serving size 2/3 cup (55g)", "Calories 230", "Total Fat 8g 10%", "Protein 3g"]
        // The model "read" 12 g of carbs, which isn't printed anywhere: it's dropped.
        let guess = LabelGuess(name: "Oat crunch", brand: "None", servingSize: "2/3 cup (55g)", servingGrams: 55,
                               values: [.kcal: 230, .fat: 8, .protein: 3, .carbs: 12])
        let check = LiveCheck.label(guess, panel: panel)
        #expect(check.values == ["kcal": 230, "fat": 8, "protein": 3])
        #expect(check.servingLabel == "2/3 cup" && check.servingGrams == 55)
        #expect(check.name == "Oat crunch" && check.brand == nil)
        // A serving given only as a weight has no measure.
        #expect(LiveCheck.label(LabelGuess(name: nil, brand: nil, servingSize: "55g"), panel: ["Serving size 55g"]).servingLabel == nil)
    }

    @Test func aModelsCheckKeepsAValueOnlyFromItsOwnRow() {
        let panel = ["Nutrition Facts", "8 servings per container", "Serving size 2/3 cup (55g)", "Calories 230", "Total Fat 8g 10%",
                     "Saturated Fat 1g 5%", "Sodium 160mg 7%", "Total Carbohydrate 37g 13%", "Dietary Fiber 4g 14%", "Total Sugars 12g",
                     "Includes 10g Added Sugars 20%", "Protein 3g"]
        // Sugar from the added-sugars row, sodium from a % Daily Value, fiber from the servings
        // count and fat from saturated fat's row are all mix-ups.
        let mixed = LabelGuess(name: nil, brand: nil, values: [.sugar: 10, .sodium: 7, .fiber: 8, .fat: 1, .protein: 3, .kcal: 230])
        #expect(LiveCheck.label(mixed, panel: panel).values == ["protein": 3, "kcal": 230])
        let right = LabelGuess(name: nil, brand: nil, values: [.sugar: 12, .sodium: 160, .fiber: 4, .fat: 8, .saturatedFat: 1, .carbs: 37])
        #expect(LiveCheck.label(right, panel: panel).values == ["sugar": 12, "sodium": 160, "fiber": 4, "fat": 8, "saturatedFat": 1, "carbs": 37])
        // Rows OCR joined, or a number on the line under its label, still count.
        let joined = ["Total Fat 8g 10% Saturated Fat 1g 5%", "Calories", "230", "Calories per gram: Fat 9 Carbohydrate 4 Protein 4"]
        let check = LiveCheck.label(LabelGuess(name: nil, brand: nil, values: [.fat: 8, .saturatedFat: 1, .kcal: 230, .carbs: 4]), panel: joined)
        #expect(check.values == ["fat": 8, "saturatedFat": 1, "kcal": 230])
        #expect(!LiveCheck.Printed(joined).contains(1, as: .fat))
    }

    @Test func aModelsCheckReadsBilingualLinearAndOldFormatRows() {
        func kept(_ values: [LabelGuess.Field: Double], _ panel: [String]) -> [String: Double] {
            LiveCheck.label(LabelGuess(name: nil, brand: nil, values: values), panel: panel).values
        }
        // A row's Spanish label is still its own row.
        #expect(kept([.kcal: 230, .fat: 8, .protein: 3], ["Calories/Calorías 230", "Total Fat/Grasa Total 8g 10%", "Protein/Proteínas 3g"])
            == ["kcal": 230, "fat": 8, "protein": 3])
        // A linear label's % DV is skipped, not the row, and "Incl. 10g Added Sugars" is another row.
        let linear = ["Amount per serving: Calories 190, Total Fat 7g (9% DV), Sat. Fat 2.5g (13% DV),",
                      "Sodium 150mg (7% DV), Total Carb. 22g (8% DV), Fiber 3g (11% DV), Total Sugars 12g (Incl. 10g Added Sugars, 20% DV),",
                      "Protein 10g. *Percent Daily Values are based on a 2,000 calorie diet."]
        let all: [LabelGuess.Field: Double] = [.kcal: 190, .fat: 7, .saturatedFat: 2.5, .sodium: 150, .carbs: 22, .fiber: 3, .sugar: 12, .protein: 10]
        #expect(kept(all, linear) == ["kcal": 190, "fat": 7, "saturatedFat": 2.5, "sodium": 150, "carbs": 22, "fiber": 3, "sugar": 12, "protein": 10])
        #expect(kept([.sugar: 10, .fat: 9, .kcal: 2000], linear).isEmpty)
        // The old format printed calories from fat on the calories row.
        let old = ["Calories 250 Calories from Fat 110", "Total Fat 12g 18%"]
        #expect(kept([.kcal: 250], old) == ["kcal": 250])
        #expect(kept([.kcal: 110], old).isEmpty)
    }

    @Test func aModelsSupplementCheckDropsADailyValueAndANonBrand() {
        let panel = ["Supplement Facts", "Serving Size 1 Softgel", "Vitamin D3 25 mcg 125%"]
        let reply = SupplementReply(name: "Vitamin D3", brand: "N/A", servingSize: "1 softgel",
                                    lines: [.init(name: "Vitamin D3", amount: 125, unit: "mcg")])
        let check = LiveCheck.supplement(reply, panel: panel)
        #expect(check.facts.ingredients.isEmpty, "125 is the % Daily Value, not the amount")
        #expect(check.brand == nil)
    }

    @Test func aModelsSupplementCheckKeepsTrackedPrintedLines() throws {
        let panel = ["Supplement Facts", "Serving Size Two Softgels", "Vitamin D3 25 mcg 125%", "Fish Oil 2,400 mg †", "EPA 650 mg †",
                     "DHA 450 mg †", "Lemon Oil 10 mg †"]
        let reply = SupplementReply(name: "Fish Oil 1200 mg", brand: "", servingSize: "Two Softgels", lines: [
            .init(name: "Vitamin D3", amount: 25, unit: "mcg"), .init(name: "Fish Oil", amount: 2400, unit: "mg"),
            .init(name: "EPA", amount: 650, unit: "mg"), .init(name: "DHA", amount: 450, unit: "mg"),
            .init(name: "Lemon Oil", amount: 10, unit: "mg"), .init(name: "Vitamin C", amount: 90, unit: "mg"),
        ])
        let check = LiveCheck.supplement(reply, panel: panel)
        // Fish oil and lemon oil aren't tracked; vitamin C's 90 mg isn't printed.
        #expect(check.facts.ingredients.map(\.name) == ["Vitamin D3", "EPA", "DHA"])
        #expect(check.facts.servingLabel == "2 softgels")
        #expect(check.name == "Fish Oil 1200 mg" && check.brand == nil)
        #expect(abs((check.facts.amounts["omega3"] ?? 0) - 1.1) < 0.001)
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
