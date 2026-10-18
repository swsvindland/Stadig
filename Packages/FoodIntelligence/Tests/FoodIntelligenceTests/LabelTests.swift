import CoreGraphics
import FoodDatabase
import Foundation
import SystemCore
import Testing

@testable import FoodIntelligence

@Suite("Labels")
struct LabelTests {
    typealias Box = LabelOCR.TextBox

    @Test func boxesOnOnePrintedRowAreJoinedLeftToRight() {
        let boxes = [
            Box(text: "230", x: 0.7, y: 0.305, width: 0.1, height: 0.04),
            Box(text: "Nutrition Facts", x: 0.1, y: 0.1, width: 0.6, height: 0.06),
            Box(text: "Calories", x: 0.1, y: 0.3, width: 0.3, height: 0.05),
            Box(text: "Total Fat 8g", x: 0.1, y: 0.4, width: 0.4, height: 0.03),
            Box(text: "10%", x: 0.8, y: 0.401, width: 0.1, height: 0.03),
        ]
        #expect(LabelOCR.rows(boxes) == ["Nutrition Facts", "Calories 230", "Total Fat 8g 10%"])
        #expect(LabelOCR.rows([]).isEmpty)
    }

    @Test func aTiltedLabelStillReadsRowByRow() {
        // Rows tilted by 6°: a row's right end sits lower than the next row's left end.
        let tilt = 6 * Double.pi / 180
        func box(_ text: String, _ x: Double, _ y: Double, _ width: Double) -> Box {
            let (dx, dy) = (cos(tilt) * width, sin(tilt) * width)
            let (hx, hy) = (-sin(tilt) * 0.03, cos(tilt) * 0.03)
            let top = (x: x, y: y + x * tan(tilt))
            return Box(
                text: text, topLeft: top, topRight: (top.x + dx, top.y + dy), bottomLeft: (top.x + hx, top.y + hy),
                bottomRight: (top.x + dx + hx, top.y + dy + hy))
        }
        let boxes = [
            box("Calories", 0.05, 0.30, 0.3), box("230", 0.8, 0.30, 0.1),
            box("Total Fat 8g", 0.05, 0.345, 0.4), box("10%", 0.8, 0.345, 0.1),
        ]
        #expect(LabelOCR.rows(boxes) == ["Calories 230", "Total Fat 8g 10%"])
    }

    @Test func aTiltedFramesRegionsStayOnTheText() throws {
        // A portrait camera frame held 10° off level, with boxes in height units (x scaled by the aspect).
        let aspect = 0.5625
        let tilt = 10 * Double.pi / 180
        func box(_ text: String, centre: (x: Double, y: Double), width: Double, height: Double = 0.03) -> Box {
            let (ux, uy) = (cos(tilt) * width / 2, sin(tilt) * width / 2)
            let (vx, vy) = (-sin(tilt) * height / 2, cos(tilt) * height / 2)
            let c = (x: centre.x * aspect, y: centre.y)
            return Box(
                text: text, topLeft: (c.x - ux - vx, c.y - uy - vy), topRight: (c.x + ux - vx, c.y + uy - vy),
                bottomLeft: (c.x - ux + vx, c.y - uy + vy), bottomRight: (c.x + ux + vx, c.y + uy + vy), aspect: aspect)
        }
        let text = FrameText([box("Total Fat 8g", centre: (0.5, 0.5), width: 0.3), box("Protein 3g", centre: (0.8, 0.9), width: 0.15)])
        let middle = try #require(text.regions.first)
        #expect(abs(middle.midX - 0.5) < 0.005 && abs(middle.midY - 0.5) < 0.005, "\(middle)")
        let corner = try #require(text.regions.last)
        #expect(abs(corner.midX - 0.8) < 0.005 && abs(corner.midY - 0.9) < 0.005, "\(corner)")
        #expect(text.regions.allSatisfy { $0.minX >= 0 && $0.maxX <= 1 })
        // The parser still gets the rows level.
        #expect(text.lines == ["Total Fat 8g", "Protein 3g"])
        // An empty frame reads as nothing.
        let empty = FrameText([])
        #expect(empty.boxes.isEmpty && empty.lines.isEmpty && empty.regions.isEmpty && empty.headline == nil)
    }

    @Test func aLabelsBoxesAndLinesComeFromOneRecognition() throws {
        let boxes = [
            Box(text: "Nutrition Facts", x: 0.05, y: 0.05, width: 0.6, height: 0.06),
            Box(text: "Serving size 2/3 cup (55g)", x: 0.05, y: 0.15, width: 0.7, height: 0.03),
            Box(text: "Calories", x: 0.05, y: 0.25, width: 0.3, height: 0.05), Box(text: "230", x: 0.8, y: 0.25, width: 0.15, height: 0.05),
            Box(text: "Total Fat 8g", x: 0.05, y: 0.35, width: 0.4, height: 0.03), Box(text: "10%", x: 0.85, y: 0.35, width: 0.1, height: 0.03),
            Box(text: "Total Carbohydrate 37g", x: 0.05, y: 0.42, width: 0.6, height: 0.03),
            Box(text: "Protein 3g", x: 0.05, y: 0.49, width: 0.3, height: 0.03),
        ]
        let result = LabelOCR.parse(boxes)
        #expect(result.lines.contains("Calories 230"))
        let reading = try #require(result.reading)
        #expect(reading.nutrients.kcal == 230 && reading.nutrients.fat == 8 && reading.nutrients.carbs == 37 && reading.nutrients.protein == 3)
        #expect(reading.servingGrams == 55)
        #expect(result.suggestedName == nil && result.brand == nil)
    }

    @Test func aThinParseIsFilledOnlyWithPrintedNumbers() throws {
        let lines = [
            "Nutrition Facts", "Serving size 2/3 cup (55g)", "Calories 230", "Total Fat 8g 10%", "Sodium 1,160mg 50%",
            "Total Carbohydrate 37g", "Protein 3g",
        ]
        let guess = LabelGuess(
            name: "Granola", brand: "none", servingSize: "2/3 cup (55g)", servingGrams: 55,
            values: [.kcal: 230, .fat: 8, .carbs: 37, .protein: 3, .sodium: 1160, .fiber: 4, .sugar: 12])
        #expect(guess.brand == nil)
        let read = try #require(LabelAssist.fill(nil, with: guess, lines: lines))
        #expect(read.nutrients.kcal == 230)
        #expect(read.nutrients.sodium == 1160)
        #expect(read.nutrients.fiber == nil, "4 g of fiber isn't printed, so it isn't taken")
        #expect(read.nutrients.sugar == nil)
        #expect(read.servingGrams == 55)
        #expect(read.servingLabel == "2/3 cup (55g)")
        // An existing parse keeps its values and gains only what it lacked.
        let parsed = LabelReading(
            servingLabel: "2/3 cup", servingGrams: nil, servingMilliliters: nil,
            nutrients: Nutrients(kcal: 230, protein: 0, carbs: 37, fat: 9), fieldsRead: 3,
            missing: ["protein", "fiber", "sugar", "saturatedFat", "sodium"])
        let filled = try #require(LabelAssist.fill(parsed, with: guess, lines: lines))
        #expect(filled.nutrients.fat == 9)
        #expect(filled.nutrients.protein == 3)
        #expect(filled.nutrients.sodium == 1160)
        #expect(filled.servingGrams == 55)
        #expect(filled.servingLabel == "2/3 cup")
        #expect(filled.fieldsRead == 3 + 3)
        #expect(filled.missing == ["fiber", "sugar", "saturatedFat"])
        // A calorie estimate gives way to the printed number.
        var estimated = parsed
        (estimated.nutrients.kcal, estimated.estimatedCalories) = (210, true)
        let printed = try #require(LabelAssist.fill(estimated, with: guess, lines: lines))
        #expect(printed.nutrients.kcal == 230 && !printed.estimatedCalories)
        // Nothing usable is not a label.
        #expect(LabelAssist.fill(nil, with: LabelGuess(name: "x", brand: nil, values: [.fat: 99]), lines: lines) == nil)
        #expect(LabelAssist.isThin(nil) && LabelAssist.isThin(parsed) && !LabelAssist.isThin(filled))
    }

    @Test func aThinParseTakesAValueOnlyFromItsOwnRow() throws {
        let lines = [
            "Nutrition Facts", "Serving size 1 bar (40g)", "Calories 190", "Total Fat 7g 9%", "Sodium 150mg 7%",
            "Total Carbohydrate 22g 8%", "Dietary Fiber 3g 11%", "Protein 10g 20%",
        ]
        // 9 is fat's % Daily Value and 7 is fat's own grams: neither is fiber, sodium or sugar.
        let guess = LabelGuess(
            name: "Bar", brand: "Unknown",
            values: [.kcal: 190, .fat: 7, .carbs: 22, .protein: 10, .fiber: 9, .sodium: 7, .sugar: 7])
        let read = try #require(LabelAssist.fill(nil, with: guess, lines: lines))
        #expect(read.nutrients.fiber == nil)
        #expect(read.nutrients.sodium == nil)
        #expect(read.nutrients.sugar == nil)
        #expect(read.nutrients.protein == 10)
        #expect(read.missing == ["saturatedFat", "fiber", "sugar", "sodium"])
        #expect(guess.brand == nil)
    }

    @Test(.needsVisionOCR) func ocrReadsARenderedPanelInEitherOrientation() async throws {
        let rows = sampleLabel
        for sideways in [false, true] {
            let lines = try await LabelOCR.lines(in: renderLabel(rows, sideways: sideways))
            #expect(lines.contains { $0.contains("Calories") && $0.contains("230") }, "\(sideways): \(lines)")
            #expect(lines.contains { $0.contains("Total Fat 8g") && $0.contains("10%") }, "\(sideways): \(lines)")
            #expect(lines.first?.contains("Nutrition") == true, "\(sideways): \(lines)")
        }
        #expect(try await LabelOCR.lines(in: blankImage()).isEmpty)
        let label = try await LabelOCR.label(in: renderLabel(rows, sideways: true))
        #expect(label.reading?.nutrients.kcal == 230, "\(label.lines)")
    }

    @Test(.needsVisionOCR) func aPhotographedSupplementPanelReadsIntoNutrients() async throws {
        let rows: [(String, String?)] = [
            ("Supplement Facts", nil), ("Serving Size 2 Softgels", nil), ("Amount Per Serving", "% DV"),
            ("Calories 20", nil), ("Total Fat 2 g", "3%*"), ("Vitamin D3", nil), ("(as cholecalciferol) 25 mcg", "125%"),
            ("Fish Oil 2,400 mg", "†"), ("EPA (Eicosapentaenoic Acid) 650 mg", "†"), ("DHA (Docosahexaenoic Acid) 450 mg", "†"),
            ("Other ingredients: Gelatin, Glycerin", nil),
        ]
        for sideways in [false, true] {
            let lines = try await LabelOCR.lines(in: renderLabel(rows, sideways: sideways))
            let facts = try #require(SupplementLabel.parse(lines: lines), "\(sideways): \(lines)")
            #expect(facts.servingLabel == "2 softgels", "\(sideways): \(lines)")
            #expect(facts.amounts["vitaminD"] == 25, "\(sideways): \(lines)")
            #expect(abs((facts.amounts["omega3"] ?? 0) - 1.1) < 0.001, "\(sideways): \(lines)")
            #expect(facts.nutrients?.kcal == 20, "\(sideways): \(lines)")
        }
    }
}
