import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// The amount screen's quick choices: half, one, one and a half and two of the usual amount, read
/// in the unit chosen.
@MainActor
struct PortionChoiceTests {
    @Test func poundsComeInTenths() throws {
        let banana = try #require(Catalogs.food.food(id: Foods.bananaID))
        let pound = try #require(FoodUnits.units(for: banana).first { $0.id == "lb" })
        let choices = AmountChoices.quick(base: 1, unit: pound)
        #expect(choices == [0.5, 1, 1.5, 2], "not 1, 1, 2, 2: half a pound is a portion")
        #expect(choices.map { AmountChoices.label($0, unit: pound) } == ["0.5 lb", "1 lb", "1.5 lb", "2 lb"])

        // 200 g, picked in grams and switched to pounds, is 0.4 lb.
        let grams = try #require(FoodUnits.units(for: banana).first { $0.id == "g" })
        let base = FoodUnits.convert(200, from: grams, to: pound)
        #expect(base == 0.4)
        #expect(
            AmountChoices.quick(base: base, unit: pound).map { AmountChoices.label($0, unit: pound) } == [
                "0.2 lb", "0.4 lb", "0.6 lb", "0.8 lb",
            ])
    }

    @Test func portionsComeInQuartersAndGramsWhole() throws {
        let banana = try #require(Catalogs.food.food(id: Foods.bananaID))
        let units = FoodUnits.units(for: banana)
        let grams = try #require(units.first { $0.id == "g" })
        #expect(AmountChoices.quick(base: 118, unit: grams) == [59, 118, 177, 236])
        #expect(AmountChoices.label(59, unit: grams) == "59 g")
        let portion = try #require(units.first { $0.kind == .portion })
        #expect(AmountChoices.quick(base: 1, unit: portion) == [0.5, 1, 1.5, 2])
        #expect(AmountChoices.label(1.5, unit: portion) == Format.number(1.5, digits: 2), "a count, without its unit")
    }
}

/// A new amount on an entry already logged: from its food where there is one, as a multiple where
/// there isn't, and only when the amount changed.
@MainActor
struct RescaledTests {
    @Test func aFoodRepricesFromTheFood() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let entry = try model.entry(foodID: Foods.bananaID, grams: 100)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")

        let bigger = model.rescaled(entry, food: banana, unit: grams, count: 200)

        #expect(abs(bigger.nutrients.kcal - entry.nutrients.kcal * 2) < 0.5)
        #expect(bigger.grams == 200)
        #expect(bigger.count == 200)
        #expect(bigger.unitID == "g")
        #expect(bigger.amountLabel == "200 g")
    }

    @Test func aDrinksFluidAndCaffeineScaleWithIt() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let coffee = try model.requireFood(Foods.coffeeID)
        let grams = try model.requireUnit(coffee, "g")
        var entry = try model.entry(foodID: Foods.coffeeID, grams: 200)
        entry.fluid = 200
        entry.micros = ["caffeine": 80]

        let bigger = model.rescaled(entry, food: coffee, unit: grams, count: 400)

        #expect(bigger.fluid == 400)
        #expect(bigger.micros?["caffeine"] != nil)
    }

    @Test func aFoodlessEntryScalesAsAMultiple() {
        let model = TestEnvironment().model()
        model.onboard()
        let estimate = FoodEntry(
            name: "Restaurant pasta", amountLabel: "1 plate", grams: 300, nutrients: Nutrients(kcal: 800, protein: 30, carbs: 90, fat: 30),
            micros: ["sodium": 900], fluid: 10, source: .description)

        let half = model.rescaled(estimate, food: nil, unit: nil, count: 0.5)

        #expect(half.nutrients.kcal == 400)
        #expect(half.grams == 150)
        #expect(half.micros?["sodium"] == 450)
        #expect(half.fluid == 5)
        #expect(half.amountLabel == "0.5 × 1 plate")
    }

    @Test func aMultipleOfOneChangesNothing() {
        let model = TestEnvironment().model()
        model.onboard()
        let estimate = FoodEntry(
            name: "Pasta", amountLabel: "1 plate", nutrients: Nutrients(kcal: 800, protein: 30, carbs: 90, fat: 30), source: .description)
        #expect(model.rescaled(estimate, food: nil, unit: nil, count: 1) == estimate)
    }
}
