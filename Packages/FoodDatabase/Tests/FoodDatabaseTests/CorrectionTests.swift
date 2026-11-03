import Foundation
import SystemCore
import Testing

@testable import FoodDatabase

@Suite("Correcting a food's numbers")
struct CorrectionTests {
    func unit(_ food: Food, _ id: String) throws -> PortionUnit { try #require(FoodUnits.units(for: food).first { $0.id == id }) }

    @Test("numbers typed for a portion become the food's per 100 g, and read back the same")
    func perPortion() throws {
        let bread = UnitsTests.bread
        let slice = try unit(bread, "portion:0")
        let corrected = try #require(bread.correcting(kcal: 70, protein: 2.5, carbs: 13, fat: 1, count: 1, unit: slice))

        #expect(abs(corrected.nutrients.kcal - 250) < 1e-9)
        #expect(abs(corrected.nutrients.protein - 2.5 * 100 / 28) < 1e-9)
        let back = FoodUnits.nutrients(corrected, count: 1, unit: try unit(corrected, "portion:0"))
        #expect(abs(back.kcal - 70) < 1e-9 && abs(back.protein - 2.5) < 1e-9 && abs(back.carbs - 13) < 1e-9 && abs(back.fat - 1) < 1e-9)
        // Two slices are twice one.
        #expect(abs(FoodUnits.nutrients(corrected, count: 2, unit: slice).kcal - 140) < 1e-9)
    }

    @Test("what wasn't corrected stays: fiber, sodium, portions, the id and the barcode")
    func keepsTheRest() throws {
        let food = UnitsTests.food
        let corrected = try #require(food.correcting(kcal: 60, protein: 3, carbs: 6, fat: 2, count: 30, unit: try unit(food, "g")))

        #expect(abs(corrected.nutrients.kcal - 200) < 1e-9)
        #expect(corrected.nutrients.sodium == 125)
        #expect(corrected.nutrients.fiber == nil, "unknown stays unknown, not zero")
        #expect(corrected.portions == food.portions)
        #expect(corrected.id == food.id && corrected.barcode == food.barcode && corrected.source == food.source)
    }

    @Test("a food counted in servings takes the numbers per serving")
    func perServing() throws {
        var bar = UnitsTests.food
        bar.basis = .serving
        bar.nutrients = Nutrients(kcal: 190, protein: 20, carbs: 22, fat: 7)
        let serving = try #require(FoodUnits.units(for: bar).first { $0.kind == .serving })
        let corrected = try #require(bar.correcting(kcal: 420, protein: 42, carbs: 44, fat: 16, count: 2, unit: serving))

        #expect(abs(corrected.nutrients.kcal - 420 / (2 * serving.amount)) < 1e-9)
        #expect(abs(FoodUnits.nutrients(corrected, count: 1, unit: serving).protein - 21) < 1e-9)
    }

    @Test("no amount, an amount in calories or a negative number corrects nothing")
    func refused() throws {
        let bread = UnitsTests.bread
        let grams = try unit(bread, "g")
        #expect(bread.correcting(kcal: 70, protein: 2, carbs: 13, fat: 1, count: 0, unit: grams) == nil)
        #expect(bread.correcting(kcal: 70, protein: 2, carbs: 13, fat: 1, count: 100, unit: try unit(bread, "kcal")) == nil)
        #expect(bread.correcting(kcal: -5, protein: 2, carbs: 13, fat: 1, count: 28, unit: grams) == nil)
        #expect(bread.correcting(kcal: .nan, protein: 2, carbs: 13, fat: 1, count: 28, unit: grams) == nil)
    }
}
