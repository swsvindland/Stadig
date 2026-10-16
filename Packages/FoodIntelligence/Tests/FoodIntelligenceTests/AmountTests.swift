import FoodDatabase
import Testing
@testable import FoodIntelligence

@Suite("Amounts")
struct AmountTests {
    func resolve(_ seen: SeenFood, _ food: Food) -> ResolvedAmount { Amounts.resolve(seen, food: food) }

    @Test func cataloguePortionsAreCheckedAgainstTheModelsWeight() {
        let egg = food(portions: [("1 cup", 243), ("1 large", 46)])
        #expect(resolve(seen("egg", quantity: 2, grams: 100), egg)
            == ResolvedAmount(amount: 92, unit: .portion(index: 1, label: "large", perUnit: 46), count: 2, exact: true))
        // A lettuce "piece" is a leaf's weight, not the catalog's whole head.
        let lettuce = food(portions: [("1 head, large", 755)])
        #expect(resolve(seen("lettuce", grams: 20), lettuce).amount == 20)
        #expect(!resolve(seen("lettuce", grams: 20), lettuce).exact)
        // The portion named after the food wins: a chicken breast is one "breast".
        let breast = food(portions: [("1 unit (yield from 1 lb ready-to-cook chicken)", 52), ("0.5 breast, bone and skin removed", 86)])
        let chicken = resolve(seen("chicken breast", grams: 170), breast)
        #expect(chicken.amount == 172)
        #expect(chicken.count == 1)
        #expect(chicken.unit == .portion(index: 1, label: "breast", perUnit: 172))
        // Named units match the portion's own noun, not a word inside it.
        let mushrooms = food(portions: [("1 cup pieces", 156), ("1 mushroom", 12)])
        #expect(resolve(seen("mushroom", quantity: 3, grams: 30), mushrooms).amount == 36)
        let rolls = food(portions: [("1 oz", 28.35), ("1 roll 1 serving", 44)])
        #expect(resolve(seen("bun", grams: 55), rolls).unit == .portion(index: 1, label: "roll", perUnit: 44))
        // A bacon "strip" is the catalog's "slice".
        let bacon = food(portions: [("1 slice", 8.1), ("1 cup", 120)])
        #expect(resolve(seen("bacon", quantity: 3, unit: "strip", grams: 30), bacon).amount == 24.3)
    }

    @Test func aServingOfAFoodWithItsOwnPortionIsThatPortion() {
        let croissant = food("Croissants, butter", portions: [("1 croissant, mini", 28), ("1 croissant, medium", 57), ("1 oz", 28.35)])
        #expect(resolve(seen("croissant", unit: "serving", grams: 150), croissant).amount == 57)
        #expect(resolve(seen("croissant", grams: 150), croissant).amount == 57)
        // The model's weight for a cookie in a photo is often far off; the cookie's own portion isn't.
        let cookie = food("Cookies, fortune", portions: [("1 cookie", 8), ("1 oz", 28.35)])
        #expect(resolve(seen("Cookie", grams: 150), cookie).amount == 8)
        // A handful is not one almond.
        let almonds = food("Nuts, almonds", portions: [("1 cup, whole", 143), ("1 almond", 1.2)])
        #expect(resolve(seen("almonds", unit: "handful", grams: 30), almonds).amount == 30)
        // Without a portion named for it, a serving is the model's weight.
        #expect(resolve(seen("pasta salad", unit: "serving", grams: 150), food(portions: [("1 large", 300)])).amount == 150)
    }

    @Test func weightsAndVolumesConvertDirectly() {
        let steak = resolve(seen("steak", quantity: 8, unit: "oz"), food())
        #expect(steak.amount == 226.8)
        #expect(steak.unit == .measure("oz", perUnit: 28.3495))
        #expect(steak.count == 8)
        #expect(steak.exact)
        #expect(resolve(seen("steak", unit: "lbs"), food()).amount == 453.6)
        #expect(resolve(seen("milk", unit: "cup"), food(basis: .ml)).amount == 240)
        let cola = resolve(seen("cola", quantity: 12, unit: "fluid ounces"), food(basis: .ml))
        #expect(cola == ResolvedAmount(amount: 354.9, unit: .measure("floz", perUnit: 29.5735), count: 12, exact: true))
        // A drink logged by weight goes through water's density.
        #expect(resolve(seen("x", quantity: 12, unit: "oz"), food(basis: .ml)).amount == 340.2)
    }

    @Test func aVolumeOfAWeighedFoodUsesItsOwnDensity() {
        let milk = food("Milk, whole", portions: [("1 fl oz", 30.5), ("1 cup", 244), ("1 tbsp", 15), ("1 quart", 976)])
        // 1 fl oz of whole milk is 30.5 g, so 250 ml is 258 g.
        #expect(resolve(seen("Whole milk", quantity: 250, unit: "ml"), milk)
            == ResolvedAmount(amount: 257.8, unit: .measure("ml", perUnit: 30.5 / 29.5735), count: 250, exact: true))
        #expect(resolve(seen("Whole milk", quantity: 0.75, unit: "cup"), milk).amount == 183)
        for (quantity, unit, grams) in [(1.0, "l", 1000.0), (1, "liter", 1000), (0.5, "l", 500), (1, "pint", 473)] {
            let amount = resolve(seen("Whole milk", quantity: quantity, unit: unit), milk).amount
            #expect(abs(amount - grams) / grams < 0.05, "\(quantity) \(unit): \(amount) g")
        }
        // A glass is not a measure: the model's weight is kept.
        #expect(resolve(seen("Whole milk", unit: "glass", grams: 250), milk).amount == 250)
        // Without a volume portion, the model's weight, else water's density.
        let plain = food("Milk", portions: [("1 serving", 200)])
        #expect(resolve(seen("x", quantity: 330, unit: "ml"), plain).amount == 330)
        #expect(!resolve(seen("x", quantity: 330, unit: "ml"), plain).exact)
        #expect(resolve(seen("x", quantity: 330, unit: "ml", grams: 340), plain).amount == 340)
    }

    @Test func smallPiecesAndTheCap() {
        // Ten nigiri are small pieces, even when the fish's only unit is a 396 g fillet and the
        // model's weight is inflated.
        let salmon = food(portions: [("3 oz", 85), ("0.5 fillet", 198)])
        #expect(resolve(seen("salmon nigiri", quantity: 10, grams: 1100), salmon)
            == ResolvedAmount(amount: 750, unit: .basis, count: 750, exact: false))
        // Without portions or a weight, 100 g per unit is the last resort, and stays within 2 kg.
        let mystery = resolve(seen("mystery", quantity: 80), food())
        #expect(mystery.amount == 2000)
        #expect(!mystery.exact)
        // A portion that is only a weight names no unit.
        #expect(resolve(seen("beef patty", quantity: 2, grams: 220), food(portions: [("1 151.0g", 151)])).amount == 220)
    }

    @Test func anOunceIsAnOunceAndACupOfTheCookedFoodIsItsOwn() {
        let couscous = food(portions: [("1 cup, dry, yields", 528), ("1 cup, cooked", 157), ("1 oz, dry, yields", 86)])
        #expect(resolve(seen("couscous", quantity: 4, unit: "oz"), couscous)
            == ResolvedAmount(amount: 113.4, unit: .measure("oz", perUnit: 28.3495), count: 4, exact: true))
        #expect(resolve(seen("couscous", unit: "cup"), couscous)
            == ResolvedAmount(amount: 157, unit: .portion(index: 1, label: "cup, cooked", perUnit: 157), count: 1, exact: true))
    }

    @Test func aWeightOfAPerServingFoodBecomesServings() {
        let bar = food(basis: .serving, portions: [("1 bar", 1)])
        #expect(resolve(seen("bar", quantity: 2), bar) == ResolvedAmount(amount: 2, unit: .portion(index: 0, label: "bar", perUnit: 1), count: 2, exact: true))
        // No serving weight is known, so a weight is one serving, marked as a guess.
        let powder = food(basis: .serving, portions: [("1 serving (1 scoop)", 1)])
        #expect(resolve(seen("protein powder", quantity: 30, unit: "g", grams: 30), powder)
            == ResolvedAmount(amount: 1, unit: .measure("serving", perUnit: 1), count: 1, exact: false))
        #expect(resolve(seen("protein powder", quantity: 2, unit: "scoops"), powder).amount == 2)
        let weighed = resolve(seen("protein powder", quantity: 45, unit: "grams"), food(basis: .serving, portions: [("1 serving (30 g)", 1)]))
        #expect(weighed == ResolvedAmount(amount: 1.5, unit: .measure("g", perUnit: 1.0 / 30), count: 45, exact: true))
        let oats = food(basis: .serving, portions: [("1 serving (1/2 cup)", 1)])
        #expect(resolve(seen("oats", unit: "cup"), oats).amount == 2)
        #expect(resolve(seen("oats", quantity: 3, unit: "oz"), oats).amount == 1)
        for (label, quantity, unit, servings) in [("1 serving (1 1/2 cups)", 1.5, "cup", 1.0), ("1 serving (.5 cup)", 1, "cup", 2),
                                                  ("1 serving (12 fluid ounces)", 24, "fl oz", 2), ("1 serving (2 tbsp (32g))", 64, "g", 2),
                                                  ("1 serving (2 tbsp (32g))", 4, "tbsp", 2)] {
            let amount = resolve(seen("x", quantity: quantity, unit: unit), food(basis: .serving, portions: [(label, 1)])).amount
            #expect(amount == servings, "\(quantity) \(unit) of \(label)")
        }
    }

    @Test func theCatalogsOwnUnitIsUsedWhenItHasOne() {
        let egg = food("Egg", portions: [("1 cup", 243), ("1 large", 46)])
        let large = PortionUnit(id: "u:large", label: "large", kind: .portion, amount: 46)
        let grams = PortionUnit(id: "u:g", label: "g", kind: .mass, amount: 1)
        let resolved = resolve(seen("egg", quantity: 2, grams: 100), egg)
        let (unit, count) = Drafting.portionUnit(for: resolved, food: egg, units: [grams, large])
        #expect(unit == large)
        #expect(count == 2)
        // Without one, an equivalent unit is made.
        let (made, _) = Drafting.portionUnit(for: resolved, food: egg, units: [])
        #expect(made == PortionUnit(id: "portion:1", label: "large", kind: .portion, amount: 46))
        // The basis unit counts grams.
        let nigiri = resolve(seen("salmon nigiri", quantity: 10, grams: 1100), food(portions: [("0.5 fillet", 198)]))
        #expect(Drafting.portionUnit(for: nigiri, food: egg, units: [grams, large]) == (grams, 750))
        // A measure the catalog names is trusted for its size: its "cup" of milk is the person's cup.
        let milk = food("Milk", portions: [("1 cup", 244)])
        let cup = PortionUnit(id: "u:cup", label: "cup", kind: .volume, amount: 244)
        let (milkUnit, cups) = Drafting.portionUnit(for: resolve(seen("milk", unit: "cup"), milk), food: milk, units: [grams, cup])
        #expect(milkUnit == cup)
        #expect(cups == 1)
    }

    @Test func anAmountIsStatedWhenThePersonSaidHowMuch() {
        let said = "two eggs, toast with butter, 200g chicken, a can of diet coke and 2 slices of pizza"
        #expect(Drafting.stated(seen("Eggs", quantity: 2), in: said))
        #expect(Drafting.stated(seen("Chicken", quantity: 200, unit: "g"), in: said))
        #expect(Drafting.stated(seen("Diet coke", unit: "can"), in: said))
        #expect(Drafting.stated(seen("Pizza", quantity: 2, unit: "slice"), in: said))
        #expect(!Drafting.stated(seen("Toast", unit: "slice"), in: "eggs and toast"))
        #expect(!Drafting.stated(seen("Butter", unit: "tbsp"), in: said))
        #expect(Drafting.stated(seen("Banana"), in: "a protein shake with a large banana"))
        #expect(!Drafting.stated(seen("Eggs", quantity: 2), in: ""))
    }
}
