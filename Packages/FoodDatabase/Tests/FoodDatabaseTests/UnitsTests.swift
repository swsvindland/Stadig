import Foundation
import SystemCore
import Testing
@testable import FoodDatabase

@Suite("Portion units")
struct UnitsTests {
    static let food = Food(id: "custom:test", name: "Test food", barcode: "00036000291452", basis: .g,
                           nutrients: Nutrients(kcal: 180, protein: 10, carbs: 20, fat: 6, sodium: 125),
                           portions: [Portion(label: "1 serving", amount: 30)], source: .custom)
    static let bread = Food(id: "custom:bread", name: "Sandwich bread", basis: .g,
                            nutrients: Nutrients(kcal: 250, protein: 9, carbs: 47, fat: 3, fiber: 2.5),
                            portions: [Portion(label: "2 SLICES (56 g)", amount: 56)], source: .custom)

    static func with(_ portions: [(String, Double)], basis: FoodBasis = .g, kcal: Double = 250) -> Food {
        var food = bread
        food.basis = basis
        food.nutrients.kcal = kcal
        food.portions = portions.map { Portion(label: $0.0, amount: $0.1) }
        return food
    }

    func labels(_ food: Food) -> [String] { FoodUnits.units(for: food).map(\.label) }
    func unit(_ food: Food, _ id: String) throws -> PortionUnit { try #require(FoodUnits.units(for: food).first { $0.id == id }) }
    func suggested(_ food: Food) -> [String] {
        let (unit, count) = FoodUnits.suggested(for: food)
        return [unit.id, FoodUnits.format(count, unit)]
    }

    @Test("portion units offer weights, volumes the food converts, its own portions and kcal")
    func offered() throws {
        let bread = Self.bread
        #expect(labels(bread) == ["g", "oz", "lb", "slice", "kcal"])
        #expect(try unit(bread, "portion:0").amount == 28)
        #expect(try unit(bread, "portion:0").kind == .portion)
        // A cup of the food gives its density, so every volume converts.
        let rice = Self.with([("1 cup", 158), ("1 serving (approximate serving size)", 186)])
        #expect(labels(rice) == ["g", "oz", "lb", "ml", "fl oz", "cup", "tbsp", "tsp", "serving", "kcal"])
        #expect(try unit(rice, "cup").amount == 158)
        #expect(try unit(rice, "tbsp").amount == 158 / 16)
        // A per-serving label with a weight and a measure converts both.
        let bar = Self.with([("1 serving (2/3 cup (40 g))", 1), ("1 bar", 1)], basis: .serving)
        #expect(labels(bar) == ["g", "oz", "lb", "ml", "fl oz", "cup", "tbsp", "tsp", "serving", "bar", "kcal"])
        #expect(try unit(bar, "g").amount == 1.0 / 40)
        #expect(try unit(bar, "cup").amount == 1.5)
        #expect(try unit(bar, "serving").kind == .serving)
        // A drink counts in volumes and its own fluid ounces, and has no grams without a weight.
        let drink = Self.with([("12 f oz (360 ml)", 360)], basis: .ml)
        #expect(labels(drink) == ["ml", "fl oz", "cup", "tbsp", "tsp", "kcal"])
        #expect(suggested(drink) == ["floz", "12"])
        #expect(suggested(bread) == ["portion:0", "2"])
        #expect(suggested(Self.with([])) == ["g", "100"])
        #expect(suggested(Self.with([], basis: .serving)) == ["serving", "1"])
        #expect(!labels(Self.with([("12 f oz (360 ml)", 360)], basis: .ml, kcal: 0)).contains("kcal"))
        // A packaged food's weight-only portion names no unit, so it opens at that weight.
        #expect(suggested(Self.with([("80g", 80)])) == ["g", "80"])
        #expect(suggested(Self.with([("30 g", 30)])) == ["g", "30"])
    }

    @Test("portion units keep exact weights and name qualified measures in full")
    func exact() throws {
        func units(_ food: Food) -> [[String]] { FoodUnits.units(for: food).map { [$0.id, $0.label, "\($0.amount)"] } }
        // "1 oz, dry, yields" is what an ounce of dry couscous makes, so an ounce stays 28.35 g.
        let couscous = Self.with([("1 cup, dry, yields", 528), ("1 cup, cooked", 157), ("1 oz, dry, yields", 86)])
        #expect(Array(units(couscous).prefix(6)) == [
            ["g", "g", "1.0"], ["oz", "oz", "28.3495"], ["lb", "lb", "453.592"],
            ["portion:0", "cup, dry, yields", "528.0"], ["portion:1", "cup, cooked", "157.0"], ["portion:2", "oz, dry, yields", "86.0"],
        ])
        #expect(FoodUnits.entryLabel(for: couscous, count: 4, unit: try unit(couscous, "oz")) == "4 oz · 113 g")
        #expect(suggested(couscous) == ["portion:0", "1"])
        #expect(FoodUnits.entryLabel(for: couscous, count: 1, unit: try unit(couscous, "portion:0")) == "1 cup, dry, yields · 528 g")
        // Each way of cutting a cup is offered; an unqualified cup gives the density for volumes.
        let strawberries = Self.with([("1 cup, pureed", 232), ("1 cup, sliced", 166), ("1 cup", 144), ("1 large (1-3/8\" dia)", 18)])
        #expect(labels(strawberries) == ["g", "oz", "lb", "ml", "fl oz", "cup", "tbsp", "tsp", "cup, pureed", "cup, sliced", "large", "kcal"])
        #expect(FoodUnits.entryLabel(for: strawberries, count: 2, unit: try unit(strawberries, "portion:1")) == "2 cups, sliced · 332 g")
        #expect(FoodUnits.entryLabel(for: strawberries, count: 1, unit: try unit(strawberries, "cup")) == "1 cup · 144 g")
        // A label whose count disagrees with its weight ("4 oz. (28.349 g)") is left out, so the
        // food opens at the weight and an ounce stays an ounce.
        let tenders = Self.with([("4 oz. (28.349 g)", 28.349)])
        #expect(units(tenders) == [["g", "g", "1.0"], ["oz", "oz", "28.3495"], ["lb", "lb", "453.592"], ["kcal", "kcal", "0.4"]])
        #expect(suggested(tenders) == ["g", "28.35"])
        // A label ounce of 28 g is still one ounce.
        #expect(suggested(Self.with([("1 oz (28 g)", 28)])) == ["oz", "1"])
    }

    @Test("amount labels count units, keep the estimate mark and never say serving(s)")
    func amountLabels() throws {
        let bread = Self.bread
        let slice = try unit(bread, "portion:0")
        #expect(FoodUnits.entryLabel(for: bread, count: 2, unit: slice) == "2 slices · 56 g")
        #expect(FoodUnits.entryLabel(for: bread, count: 0.5, unit: slice) == "½ slice · 14 g")
        #expect(FoodUnits.entryLabel(for: bread, count: 1.5, unit: slice) == "1½ slices · 42 g")
        #expect(FoodUnits.entryLabel(for: bread, count: 120, unit: try unit(bread, "g")) == "120 g")
        #expect(FoodUnits.entryLabel(for: bread, count: 2, unit: try unit(bread, "oz")) == "2 oz · 57 g")
        #expect(FoodUnits.entryLabel(for: bread, count: 300, unit: try unit(bread, "kcal"), estimate: true) == "≈ 300 kcal · 120 g")
        let serving = Self.with([], basis: .serving)
        #expect(FoodUnits.entryLabel(for: serving, count: 0.5, unit: try unit(serving, "serving")) == "½ serving")
        #expect(FoodUnits.entryLabel(for: serving, count: 2, unit: try unit(serving, "serving")) == "2 servings")
        #expect(FoodUnits.entryLabel(for: serving, count: 375, unit: try unit(serving, "kcal")) == "375 kcal · 1½ servings")
        // The short labels.
        let cup = PortionUnit(id: "cup", label: "cup", kind: .volume, amount: 240)
        #expect(FoodUnits.label(count: 1.5, unit: cup) == "1½ cups")
        #expect(FoodUnits.label(count: 150, unit: PortionUnit(id: "g", label: "g", kind: .mass, amount: 1)) == "150 g")
        #expect(FoodUnits.label(count: 2, unit: PortionUnit(id: "portion:0", label: "large", kind: .portion, amount: 50)) == "2 large")
        #expect(FoodUnits.label(count: 3, unit: PortionUnit(id: "portion:0", label: "patty", kind: .portion, amount: 50)) == "3 patties")
        #expect(FoodUnits.label(count: 2, unit: PortionUnit(id: "portion:0", label: "peach", kind: .portion, amount: 50)) == "2 peaches")
        #expect(FoodUnits.label(count: 2, unit: PortionUnit(id: "floz", label: "fl oz", kind: .volume, amount: 29.5735)) == "2 fl oz")
    }

    @Test("amounts take fractions and mixed numbers", arguments: [
        ("2", 2.0), (".5", 0.5), ("2,5", 2.5), ("1/2", 0.5), ("1 1/2", 1.5), ("½", 0.5), ("1½", 1.5), ("1 ¾", 1.75), (" 2. ", 2),
    ])
    func parse(text: String, value: Double) {
        #expect(FoodUnits.parseCount(text) == value)
    }

    @Test("text that isn't an amount isn't read as one", arguments: ["", "abc", "1/0", "1 1", "-2", "2/"])
    func reject(text: String) {
        #expect(FoodUnits.parseCount(text) == nil)
    }

    @Test("amounts convert between units, rounded for the unit")
    func convert() throws {
        let bread = Self.bread
        func convert(_ count: Double, _ from: String, _ to: String) throws -> Double {
            FoodUnits.convert(count, from: try unit(bread, from), to: try unit(bread, to))
        }
        #expect(try convert(120, "g", "oz") == 4.2)
        #expect(try convert(4.2, "oz", "g") == 119)
        #expect(try convert(84, "g", "portion:0") == 3)
        #expect(try convert(100, "g", "portion:0") == 3.5, "counts round to the nearest quarter")
        #expect(try convert(1.5, "portion:0", "g") == 42)
        #expect(try convert(2, "portion:0", "kcal") == 140)
        #expect(try convert(300, "kcal", "g") == 120)
        // "300 kcal" of a food is the weight that has 300 kcal.
        let food = Self.food
        let kcal = try unit(food, "kcal")
        #expect(abs(FoodUnits.amount(300, kcal) - 500.0 / 3) < 1e-9)
        #expect(abs(FoodUnits.nutrients(food, count: 300, unit: kcal).kcal - 300) < 1e-9)
        #expect(FoodUnits.entryLabel(for: food, count: 300, unit: kcal) == "300 kcal · 167 g")
        #expect(FoodUnits.step(for: try unit(bread, "g")) == 10)
        #expect(FoodUnits.step(for: try unit(bread, "portion:0")) == 0.5)
    }

    @Test("logging again reopens at the last unit and count while the food still has that unit")
    func remembered() throws {
        let bread = Self.bread
        let last = FoodUnits.suggested(for: bread, lastUnitID: "g", lastCount: 56)
        #expect(last.unit.id == "g" && last.count == 56)
        let slices = FoodUnits.suggested(for: bread, lastUnitID: "portion:0", lastCount: 3)
        #expect(slices.unit.label == "slice" && slices.count == 3)
        // Without slices, the food's own default.
        let gone = FoodUnits.suggested(for: Self.with([]), lastUnitID: "portion:0", lastCount: 2)
        #expect(gone.unit.id == "g" && gone.count == 100)
        #expect(FoodUnits.suggested(for: bread, lastUnitID: "g", lastCount: 0).unit.id == "portion:0")
    }
}
