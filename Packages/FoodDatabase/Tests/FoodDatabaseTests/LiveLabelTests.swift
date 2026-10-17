import Foundation
import SystemCore
import Testing
@testable import FoodDatabase

@Suite("Live label scanning")
struct LiveLabelTests {
    /// One camera frame's text, a line per row, as OCR returns it once levelled.
    func frame(_ lines: [String]) -> LabelFrame {
        NutritionLabel.frame(boxes: lines.enumerated().map { LabelTextBox(text: $1, x: 0.05, y: 0.1 + Double($0) * 0.06, width: 0.9, height: 0.05) })
    }

    // A panel too tall for one frame: the camera sees the top, the middle, then the bottom.
    let top = ["Nutrition Facts", "8 servings per container", "Serving size 2/3 cup (55g)", "Amount per serving", "Calories 230",
               "% Daily Value*", "Total Fat 8g 10%", "Saturated Fat 1g 5%"]
    let middle = ["Saturated Fat 1g 5%", "Trans Fat 0g", "Cholesterol 0mg 0%", "Sodium 160mg 7%", "Total Carbohydrate 37g 13%"]
    let bottom = ["Total Carbohydrate 37g 13%", "Dietary Fiber 4g 14%", "Total Sugars 12g", "Includes 10g Added Sugars 20%",
                  "Protein 3g", "Vitamin D 2mcg 10%", "Calcium 260mg 20%", "Iron 8mg 45%"]

    @Test func aTallLabelIsPutTogetherFromFramesThatEachSeePartOfIt() throws {
        var live = LiveLabel()
        // No single frame has calories and protein together.
        #expect(NutritionLabel.frame(boxes: []).amounts.isEmpty)
        for part in [top, top, middle, middle, bottom, bottom] { live.add(frame(part)) }
        #expect(live.frames == 6 && live.panelFrames == 6)
        #expect(live.value("kcal") == .locked(230))
        #expect(live.value("protein") == .locked(3))
        #expect(live.value("sodium") == .locked(160))
        #expect(live.value("vitaminD") == .locked(2))
        #expect(live.missingCore.isEmpty && live.ready)
        let reading = try #require(live.reading)
        #expect(reading.nutrients.kcal == 230 && reading.nutrients.fat == 8 && reading.nutrients.carbs == 37 && reading.nutrients.protein == 3)
        #expect(reading.nutrients.fiber == 4 && reading.nutrients.sugar == 12 && reading.nutrients.sodium == 160)
        #expect(reading.servingGrams == 55 && reading.servingLabel == "2/3 cup")
        #expect(reading.extras["calcium"] == 260)
        // Cholesterol, trans fat and added sugars aren't tracked, so they're neither shown nor kept.
        #expect(reading.extras["addedSugar"] == nil && reading.extras["cholesterol"] == nil)
        #expect(!live.keys.contains("cholesterol") && !live.keys.contains("transFat") && !live.keys.contains("addedSugar"))
        #expect(reading.warnings.isEmpty && !reading.estimatedCalories)
    }

    @Test func oneMisreadFrameIsOutvoted() {
        var live = LiveLabel()
        live.add(frame(top))
        live.add(frame(["Nutrition Facts", "Calories 280", "Total Fat 9g 10%"]))
        // Seen once each way: nothing's sure yet.
        #expect(live.value("kcal") == .reading(230) || live.value("kcal") == .reading(280))
        #expect(!live.value("fat").isLocked)
        live.add(frame(top))
        live.add(frame(top))
        #expect(live.value("kcal") == .locked(230))
        #expect(live.value("fat") == .locked(8))
    }

    @Test func aValueReadOnceIsShownButNotTrusted() {
        var live = LiveLabel()
        for part in [top, top, middle, middle, bottom] { live.add(frame(part)) }
        #expect(live.value("protein") == .reading(3))
        #expect(live.missingCore == ["protein"])
        // Calories and two macros are enough to review.
        #expect(live.ready)
        var macrosOnly = LiveLabel()
        for part in [middle, middle] { macrosOnly.add(frame(part)) }
        #expect(!macrosOnly.ready && macrosOnly.missingCore == ["kcal", "fat", "protein"])
    }

    @Test func thePackageFrontIsIgnored() {
        var live = LiveLabel()
        let front = frame(["HONEY NUT", "Cheerios", "20g PROTEIN", "Calories 150 per bowl", "Whole grain oats"])
        #expect(!front.isPanel)
        for _ in 0..<5 { live.add(front) }
        #expect(live.frames == 5 && live.panelFrames == 0 && live.reading == nil && live.value("kcal") == .missing)
    }

    @Test func caloriesAreWorkedOutWhenOnlyTheMacrosWereSeen() throws {
        var live = LiveLabel()
        for part in [middle, middle, bottom, bottom, ["Total Fat 8g 10%", "Saturated Fat 1g 5%", "Trans Fat 0g"],
                     ["Total Fat 8g 10%", "Saturated Fat 1g 5%", "Trans Fat 0g"]] { live.add(frame(part)) }
        #expect(live.ready && live.value("kcal") == .missing)
        let reading = try #require(live.reading)
        #expect(reading.estimatedCalories && reading.nutrients.kcal == 9 * 8 + 4 * 37 + 4 * 3)
    }

    @Test func aSupplementPanelIsReadLineByLineAcrossFrames() throws {
        let head = ["Supplement Facts", "Serving Size 2 Softgels", "Amount Per Serving % DV", "Calories 20", "Total Fat 2 g 3%",
                    "Vitamin D3 (as cholecalciferol) 25 mcg 125%"]
        let tail = ["Vitamin D3 (as cholecalciferol) 25 mcg 125%", "Fish Oil 2,400 mg †", "EPA (Eicosapentaenoic Acid) 650 mg †",
                    "DHA (Docosahexaenoic Acid) 450 mg †", "Vitamin E 13.5 mg 90%", "Other ingredients: Gelatin, Glycerin"]
        var live = LiveSupplementLabel()
        live.add(SupplementLabel.parse(lines: head))
        live.add(SupplementLabel.parse(lines: ["EPA (Eicosapentaenoic Acid) 560 mg †", "DHA (Docosahexaenoic Acid) 450 mg †"]))
        live.add(SupplementLabel.parse(lines: head))
        live.add(SupplementLabel.parse(lines: tail))
        live.add(SupplementLabel.parse(lines: tail))
        live.add(SupplementLabel.parse(lines: ["Nature Made", "Fish Oil", "Heart health"]))
        #expect(live.frames == 6 && live.panelFrames == 5)
        let lines = live.readLines
        // "Fish Oil 2,400 mg" isn't a nutrient Macro Track tracks, so it never shows up.
        #expect(lines.map(\.ingredient.name) == ["Calories", "Total Fat", "Vitamin D3 (as cholecalciferol)",
                                                 "EPA (Eicosapentaenoic Acid)", "DHA (Docosahexaenoic Acid)", "Vitamin E"])
        #expect(lines.last?.ingredient.amount == 13.5)
        // EPA was misread as 560 once, then read as 650 twice.
        #expect(lines.first { $0.ingredient.name.hasPrefix("EPA") }?.ingredient.amount == 650)
        #expect(lines.allSatisfy { $0.locked })
        #expect(live.ready)
        let facts = try #require(live.facts)
        #expect(facts.servingLabel == "2 softgels")
        #expect(facts.amounts["vitaminD"] == 25 && abs(facts.amounts["omega3"]! - 1.1) < 0.001)
        #expect(facts.nutrients?.kcal == 20)
    }

    @Test func aModelCheckSettlesTiesAndFillsGapsButCantOverturnTheFrames() {
        var live = LiveLabel()
        live.add(frame(["Nutrition Facts", "Calories 230", "Total Fat 8g 10%"]))
        live.add(frame(["Nutrition Facts", "Calories 280", "Total Fat 8g 10%"]))
        #expect(!live.value("kcal").isLocked)
        // The model read 230 from the text and protein the frames missed.
        live.check(values: ["kcal": 230, "protein": 3])
        #expect(live.value("kcal") == .locked(230))
        #expect(live.value("protein") == .locked(3))
        #expect(live.isChecked)
        // Three frames agreeing outvote it.
        var sure = LiveLabel()
        for _ in 0..<3 { sure.add(frame(["Nutrition Facts", "Calories 230", "Total Fat 8g 10%"])) }
        sure.check(values: ["kcal": 280])
        #expect(sure.value("kcal") == .locked(230))
        // A new check replaces the last one rather than piling up: the tie now goes the other way,
        // and protein, which no frame read, is gone.
        live.check(values: ["kcal": 280])
        #expect(live.value("kcal") == .locked(280))
        #expect(live.value("protein") == .missing)
        // Nothing untracked gets in through a check either.
        live.check(values: ["cholesterol": 30])
        #expect(live.value("cholesterol") == .missing)
    }

    @Test func aModelCheckOfASupplementMatchesLinesByNutrientAndAddsWhatFramesMissed() throws {
        var live = LiveSupplementLabel()
        let panel = ["Supplement Facts", "Serving Size 2 Softgels", "Vitamin D3 (as cholecalciferol) 25 mcg 125%", "EPA 650 mg †",
                     "Net Wt. 12 oz (340 g)", "Take 2 softgels daily with food"]
        live.add(SupplementLabel.parse(lines: panel))
        // Directions and net weight never become lines.
        #expect(live.readLines.map(\.ingredient.name) == ["Vitamin D3 (as cholecalciferol)", "EPA"])
        #expect(live.lockedCount == 0)
        let model = SupplementFacts(id: "m", name: "Fish Oil", servingCount: 2, unit: "softgel", ingredients: [
            SupplementIngredient(name: "Vitamin D", amount: 25, unit: "mcg"),
            SupplementIngredient(name: "EPA", amount: 650, unit: "mg"),
            SupplementIngredient(name: "DHA", amount: 450, unit: "mg"),
        ], source: .label)
        live.check(model)
        let lines = live.readLines
        #expect(lines.map(\.ingredient.name) == ["Vitamin D3 (as cholecalciferol)", "EPA", "DHA"])
        #expect(lines.allSatisfy(\.locked) && live.ready)
        let facts = try #require(live.facts)
        #expect(facts.servingLabel == "2 softgels")
    }
}
