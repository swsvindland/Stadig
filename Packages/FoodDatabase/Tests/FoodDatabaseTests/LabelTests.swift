import Foundation
import SystemCore
import Testing
@testable import FoodDatabase

/// Text boxes laid out like OCR output: text, x, y and a common line height.
private func boxes(_ rows: [(String, Double, Double, Double?)], height: Double = 0.03) -> [LabelTextBox] {
    rows.map { LabelTextBox(text: $0.0, x: $0.1, y: $0.2, width: 0.3, height: $0.3 ?? height) }
}

private func boxes(_ rows: [(String, Double, Double)], height: Double = 0.03) -> [LabelTextBox] {
    boxes(rows.map { ($0.0, $0.1, $0.2, nil) }, height: height)
}

@Suite("Nutrition labels")
struct LabelTests {
    @Test("the 2016 label layout, with calories and serving size split from their values")
    func layout2016() throws {
        let read = NutritionLabel.read(boxes([
            ("Nutrition Facts", 0.03, 0.01, 0.06),
            ("8 servings per container", 0.03, 0.08, nil),
            ("Serving size", 0.02, 0.115, nil),
            ("2/3 cup (55g)", 0.55, 0.118, nil),
            ("Amount per serving", 0.03, 0.19, nil),
            ("Calories", 0.03, 0.219, 0.042),
            ("230", 0.71, 0.206, 0.057),
            ("% Daily Value*", 0.62, 0.289, nil),
            ("Total Fat 8g", 0.03, 0.327, nil),
            ("10%", 0.85, 0.327, nil),
            ("Saturated Fat 1g", 0.09, 0.366, nil),
            ("Trans Fat 0g", 0.09, 0.407, nil),
            ("Cholesterol 0mg", 0.03, 0.447, nil),
            ("Sodium 160mg", 0.03, 0.485, nil),
            ("Total Carbohydrate 37g", 0.03, 0.524, nil),
            ("Dietary Fiber 4g", 0.09, 0.568, nil),
            ("Total Sugars 12g", 0.09, 0.607, nil),
            ("Includes 10g Added Sugars", 0.15, 0.646, nil),
            ("Protein 3g", 0.03, 0.68, nil),
            ("a serving of food contributes to a daily diet. 2,000 calories", 0.05, 0.937, nil),
        ]))
        #expect(read.amounts == ["kcal": 230, "fat": 8, "carbs": 37, "protein": 3, "fiber": 4, "sodium": 160, "saturatedFat": 1,
                                 "transFat": 0, "cholesterol": 0, "sugar": 12, "addedSugar": 10])
        #expect(read.servingLabel == "2/3 cup")
        #expect(read.servingAmount == 55 && read.servingUnit == "g")
        #expect(!read.estimatedCalories && read.warnings.isEmpty)
        #expect(read.found)
        let reading = read.reading
        #expect(reading.nutrients == Nutrients(kcal: 230, protein: 3, carbs: 37, fat: 8, fiber: 4, sugar: 12, saturatedFat: 1, sodium: 160))
        // Read for the checks, but not kept: Macro Track doesn't track them.
        #expect(reading.extras.isEmpty)
        #expect(reading.servingLabel == "2/3 cup" && reading.servingGrams == 55 && reading.servingMilliliters == nil)
        #expect(reading.fieldsRead == 11)
        #expect(reading.missing == ["vitaminD", "calcium", "iron", "potassium"])
    }

    @Test("the same label from plain lines, a value on the line after its name")
    func lines() throws {
        let reading = try #require(NutritionLabel.parse(lines: [
            "Nutrition Facts", "8 servings per container", "Serving size", "2/3 cup (55g)", "Amount per serving", "Calories", "230",
            "% Daily Value*", "Total Fat 8g", "10%", "Saturated Fat 1g", "Trans Fat 0g", "Cholesterol 0mg", "Sodium 160mg",
            "Total Carbohydrate 37g", "Dietary Fiber 4g", "Total Sugars 12g", "Includes 10g Added Sugars", "Protein 3g",
        ]))
        #expect(reading.nutrients == Nutrients(kcal: 230, protein: 3, carbs: 37, fat: 8, fiber: 4, sugar: 12, saturatedFat: 1, sodium: 160))
        #expect(reading.servingLabel == "2/3 cup" && reading.servingGrams == 55)
        #expect(reading.extras["addedSugar"] == nil)
        // A footer limit on the next line is not this food's sodium.
        let footer = try #require(NutritionLabel.parse(lines: ["Calories 250", "Total Fat 12g", "Protein 5g", "Sodium", "Less than 2,400mg"]))
        #expect(footer.missing.contains("sodium"))
        #expect(NutritionLabel.parse(lines: ["SANDWICH BREAD", "Ingredients: Wheat Flour, Water, Sugar"]) == nil)
    }

    @Test("the vitamins and minerals a US label lists, but not % Daily Value alone")
    func micronutrients() {
        let reading = NutritionLabel.read(boxes([
            ("Calories 230", 0.03, 0.2), ("Total Fat 8g", 0.03, 0.3), ("Total Carbohydrate 37g", 0.03, 0.4),
            ("Total Sugars 1g", 0.09, 0.45), ("Sugar Alcohol 9g", 0.09, 0.47), ("Protein 3g", 0.03, 0.5),
            ("Vitamin D 2mcg 10%", 0.03, 0.6), ("Calcium 260mg 20%", 0.03, 0.64), ("Iron 8mg 45%", 0.03, 0.68),
            ("Potassium 235mg 6%", 0.03, 0.72),
        ])).amounts
        #expect([reading["sugar"], reading["vitaminD"], reading["calcium"], reading["iron"], reading["potassium"]] == [1, 2, 260, 8, 235])
        // Older labels give only a share of the Daily Value, which isn't an amount.
        let old = NutritionLabel.read(boxes([
            ("Calories 110", 0.03, 0.2), ("Total Fat 1g", 0.03, 0.3), ("Protein 2g", 0.03, 0.5), ("Vitamin D 19%", 0.03, 0.6),
            ("Iron 10%", 0.03, 0.64), ("Sat. Fat 3g", 0.03, 0.7),
        ]))
        #expect(old.amounts["vitaminD"] == nil)
        #expect(old.amounts["iron"] == nil)
        #expect(old.amounts["saturatedFat"] == 3)
        #expect(old.warnings == [.partOverTotal])
    }

    @Test("a two-column can label merges neighbors and skips traps that are not amounts")
    func twoColumns() {
        let reading = NutritionLabel.read(boxes([
            ("Nutrition", 0.21, 0.417), ("Amount/serving", 0.4, 0.411), ("Total Fat 16g", 0.4, 0.459), ("25% Total Carb. 1g", 0.54, 0.451),
            ("Serv. Size 2 oz. (56g)", 0.21, 0.508), ("Sat. Fat 6g", 0.42, 0.502), ("Fiber Og", 0.6, 0.5), ("Servings: 6", 0.21, 0.551),
            ("Calories 180", 0.21, 0.593), ("Cholest. 40mg 13% Protein 7g", 0.4, 0.586), ("Fat Cal. 140", 0.22, 0.629),
            ("Sodium 580mg 24%", 0.4, 0.633), ("based on a 2,000 calorie diet.", 0.22, 0.697),
            ("SODIUM CONTENT HAS BEEN LOWERED FROM 790mg TO 580mg", 0.21, 0.731),
            ("Calories per gram: Fat 9 • Carbohydrate 4 • Protein 4", 0.21, 0.8),
        ]))
        let amounts = reading.amounts
        #expect(amounts["kcal"] == 180)
        #expect(amounts["fat"] == 16)
        #expect(amounts["carbs"] == 1)
        #expect(amounts["protein"] == 7)
        #expect(amounts["fiber"] == 0, "OCR's O is a zero")
        #expect(amounts["sodium"] == 580)
        #expect(reading.servingLabel == "2 oz.")
        #expect(reading.servingAmount == 56)
    }

    @Test("a skewed bag without calories estimates them and repairs the serving weight")
    func skewed() {
        let reading = NutritionLabel.read(boxes([
            ("Amount/Serving", 0.36, 0.33, 0.11), ("Total Fat 28g", 0.37, 0.42, 0.11), ("Sodium 400mg", 0.74, 0.3, 0.09),
            ("Total Carbohydrate 47g", 0.76, 0.32, 0.13), ("Dietary Fiber 4g", 0.78, 0.39, 0.1), ("Protein 5g", 0.74, 0.51, 0.07),
            // "(94g/3.3 oz)" read as "g4g/3.3 oz)": a 4 g serving can't hold 80 g of macros.
            ("erving Size 1 Package", -0.015, 0.628, 0.223), ("g4g/3.3 oz)", -0.017, 0.738, 0.167),
            ("carvings Per Contain-", -0.003, 0.755, 0.218),
        ]))
        #expect(reading.amounts["kcal"] == Double(9 * 28 + 4 * 47 + 4 * 5))
        #expect(reading.estimatedCalories)
        #expect(reading.servingLabel == "1 Package")
        #expect(reading.servingAmount == 93.6, "3.3 oz")
        #expect(reading.servingUnit == "g")
        #expect(reading.found)
        var missing = reading
        missing.amounts["fat"] = nil
        missing.amounts["carbs"] = nil
        #expect(!missing.found, "estimated calories alone aren't a label")
        #expect(reading.reading.fieldsRead == 5)
    }

    @Test("column layouts, implied units, bilingual labels and small amounts")
    func columns() {
        let drink = NutritionLabel.read(boxes([
            ("Supplement Facts", 0.03, 0.01), ("Serving Size 8.0 fl.oz. (240 mL)", 0.03, 0.089), ("Calories", 0.03, 0.248),
            ("100", 0.57, 0.252), ("Total Carb", 0.03, 0.301), ("27g", 0.57, 0.302), ("9%*", 0.84, 0.298), ("Sodium", 0.03, 0.609),
            ("180mg", 0.5, 0.606), ("Taurine", 0.03, 0.662), ("1000mg", 0.47, 0.654),
        ]))
        #expect([drink.amounts["kcal"], drink.amounts["carbs"], drink.amounts["sodium"], drink.amounts["fat"], drink.amounts["protein"]]
            == [100, 27, 180, nil, nil])
        #expect(drink.servingAmount == 240 && drink.servingUnit == "ml")
        // Unknown values stay unknown instead of becoming zero.
        #expect(!drink.estimatedCalories)

        let cereal = NutritionLabel.read(boxes([
            ("SERVING SIZE: 1 OZ.", 0.07, 0.06), ("(28.4 g, ABOUT 1 CUP)", 0.43, 0.085), ("CALORIES.", 0.07, 0.236), ("100", 0.56, 0.234),
            ("140*", 0.77, 0.232), ("PROTEIN, g", 0.07, 0.261), ("2", 0.6, 0.262), ("6", 0.82, 0.262), ("CARBOHYDRATE, g.", 0.07, 0.289),
            ("24", 0.58, 0.289), ("SODIUM, mg.", 0.07, 0.424), ("290", 0.56, 0.424),
        ]))
        #expect([cereal.amounts["kcal"], cereal.amounts["protein"], cereal.amounts["carbs"], cereal.amounts["sodium"]] == [100, 2, 24, 290])
        #expect(cereal.servingAmount == 28.4)

        let agave = NutritionLabel.read(boxes([
            ("Serving Size/Tamaño de Porción (1.06 oz)/30 g", 0.53, 0.444), ("Calories 90", 0.53, 0.47),
            ("Total Fat / Grasa Total 09", 0.53, 0.507), ("Sodium / Sodio 0.1g", 0.53, 0.52), ("Total Carb. / Carb. Totales 23g", 0.53, 0.546),
            ("Dietary Fiber <1g", 0.59, 0.555), ("Protein / Proteína 0g", 0.53, 0.57),
        ], height: 0.01))
        #expect([agave.amounts["kcal"], agave.amounts["fat"], agave.amounts["sodium"], agave.amounts["carbs"], agave.amounts["fiber"],
                 agave.amounts["protein"]] == [90, 0, 100, 23, 0.5, 0])
        #expect(agave.servingAmount == 30)
        #expect(agave.servingLabel == "", "a measure without a number is not shown")
    }

    @Test("thousands commas next to a unit, and footer limits that are not amounts")
    func commas() {
        let soup = NutritionLabel.read(boxes([
            ("Serving size 1 cup (245g)", 0.03, 0.1), ("Calories 90", 0.03, 0.2), ("Total Fat 2g 3%", 0.03, 0.3),
            ("Sodium 1,160mg 50%", 0.03, 0.4), ("Total Carbohydrate 14g 5%", 0.03, 0.5), ("Protein 3g", 0.03, 0.6),
        ]))
        #expect(soup.amounts["sodium"] == 1160)
        #expect(soup.amounts["kcal"] == 90)

        let split = NutritionLabel.read(boxes([("Sodium", 0.03, 0.4), ("1,160mg", 0.6, 0.401), ("50%", 0.85, 0.4)]))
        #expect(split.amounts["sodium"] == 1160)

        // A 1990s label whose sodium row was cut off still prints the daily limits underneath.
        let footer = NutritionLabel.read(boxes([
            ("Calories 250", 0.03, 0.1), ("Total Fat 12g", 0.03, 0.2), ("Protein 5g", 0.03, 0.3), ("Calories: 2,000 2,500", 0.03, 0.7),
            ("Total Fat Less than 65g 80g", 0.03, 0.75), ("Sodium Less than 2,400mg 2,400mg", 0.03, 0.8), ("Sodium", 0.03, 0.85),
            ("Less than 2,400mg", 0.4, 0.85),
        ]))
        #expect([footer.amounts["kcal"], footer.amounts["fat"], footer.amounts["sodium"]] == [250, 12, nil])

        let small = NutritionLabel.read(boxes([("Sodium less than 5mg", 0.03, 0.1), ("Protein 0,125g", 0.03, 0.2)]))
        #expect(small.amounts["sodium"] == 2.5, "a real small amount is still read")
        #expect(small.amounts["protein"] == 0.125, "a leading zero means a decimal comma")
    }

    @Test("inconsistent values are flagged and a photo without a label is rejected")
    func rejected() {
        let reading = NutritionLabel.read(boxes([
            ("Calories 900", 0.03, 0.1), ("Total Fat 8g", 0.03, 0.2), ("Total Carbohydrate 37g", 0.03, 0.3), ("Protein 3g", 0.03, 0.4),
        ]))
        #expect(reading.warnings == [.caloriesMismatch])
        #expect(NutritionLabel.parse(boxes: boxes([
            ("SANDWICH BREAD", 0.1, 0.2), ("Ingredients: Wheat Flour, Water, Sugar", 0.1, 0.5),
        ])) == nil)
        #expect(NutritionLabel.parse(boxes: []) == nil)
        #expect(NutritionLabel.parse(lines: []) == nil)
    }

    @Test("per-serving label values become a per-100 g food with the serving as a portion")
    func customFood() {
        let nutrients = Nutrients(kcal: 230, protein: 3, carbs: 37, fat: 8, fiber: 4)
        let reading = LabelReading(servingLabel: "2/3 cup", servingGrams: 55, servingMilliliters: nil, nutrients: nutrients,
                                   extras: ["calcium": 260], fieldsRead: 6)
        let food = reading.food(name: " Granola ", brand: "Store", barcode: "036000291452")
        #expect(food.name == "Granola")
        #expect(food.brand == "Store")
        #expect(food.barcode == "00036000291452")
        #expect(food.basis == .g)
        #expect(food.source == .label)
        #expect(food.id.hasPrefix("custom:"))
        #expect(food.portions == [Portion(label: "1 serving (2/3 cup)", amount: 55)])
        #expect(abs(food.nutrients.kcal - 230 * 100 / 55) < 1e-9)
        #expect(food.nutrients.sodium == nil)
        #expect(abs(food.extras["calcium"]! - 260 * 100 / 55) < 1e-9)
        // Logging one serving gives back the label's own numbers.
        let one = food.nutrients(for: 55)
        #expect(abs(one.kcal - 230) < 1e-9 && abs(one.protein - 3) < 1e-9)
        // A serving by volume is a food per 100 ml; one without a weight stays per serving.
        var can = reading
        can.servingGrams = nil
        can.servingMilliliters = 355
        #expect(can.food(name: "Soda", brand: nil, barcode: nil).basis == .ml)
        var bar = reading
        bar.servingGrams = nil
        bar.servingLabel = "1 bar"
        let noWeight = bar.food(name: "Bar", brand: nil, barcode: nil)
        #expect(noWeight.basis == .serving && noWeight.nutrients.kcal == 230)
        #expect(noWeight.portions == [Portion(label: "1 serving (1 bar)", amount: 1)])
        #expect(FoodUnits.units(for: noWeight).map(\.label) == ["serving", "kcal"])
    }
}
