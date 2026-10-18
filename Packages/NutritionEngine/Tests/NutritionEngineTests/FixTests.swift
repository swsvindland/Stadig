import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

@Suite("Swaps and one-tap fixes")
struct FixTests {
    static let protein = "Greek yogurt, skyr, eggs or cottage cheese give the same protein as whole food."
    static let bar = "Fruit and a handful of nuts, or Greek yogurt if it's the protein you're after."
    static let drink = "Water, sparkling water or milk: drinks are the easiest calories to cut, and don't fill you up."
    static let sweet = "Fruit, or yogurt with honey, for the sweet spot."
    static let salty = "A handful of nuts, or popcorn you pop yourself, for the salty crunch."
    static let meal = "The same meal cooked from whole foods: meat or fish, rice or potatoes, and vegetables. Cooked in a batch, it's as quick."
    static let meat = "Chicken, eggs or fish cooked plain do the same job with less salt."
    static let breakfast = "Oats with fruit fill the same spot, with fiber that keeps you full until lunch."
    static let bread = "A bakery loaf, or potatoes and rice for the starch."

    /// A food as logged: a serving's calories, protein and sugar, the rest left to fat and carbs.
    static func food(_ kcal: Double, protein: Double, sugar: Double?) -> Nutrients {
        Nutrients(kcal: kcal, protein: protein, carbs: max(0, (kcal - protein * 4) / 8), fat: max(0, (kcal - protein * 4) / 18), sugar: sugar)
    }

    // Names whose letters hide another tip's key ("chocolate" holds "cola", "barbecue" and
    // "rhubarb" a "bar", "bundt" a "bun", "crispy" a "crisp", "chipotle" a "chip") get their own
    // tip, at nutrients like the real food's.
    static let swaps: [(name: String, nutrients: Nutrients, advice: String)] = [
        ("Milk chocolate", food(235, protein: 3, sugar: 24), sweet),
        ("Chocolate chip cookies", food(160, protein: 2, sugar: 11), sweet),
        ("Barbecue potato chips", food(150, protein: 2, sugar: 2), salty),
        ("Rhubarb pie", food(300, protein: 3, sugar: 30), sweet),
        ("Bundt cake", food(420, protein: 5, sugar: 41), sweet),
        ("Crispy chicken sandwich", food(700, protein: 28, sugar: 9), meal),
        ("Chipotle chicken burrito", food(1000, protein: 50, sugar: 6), meal),
        ("Pastrami", food(147, protein: 22, sugar: 0), meat),
        ("Sliced ham", food(107, protein: 17, sugar: 1), meat),
        ("Cola", food(140, protein: 0, sugar: 39), drink),
        ("Diet Coke", food(1, protein: 0, sugar: 0), drink),
        ("Chocolate protein shake", food(160, protein: 30, sugar: 2), protein),
        ("Granola bars", food(190, protein: 4, sugar: 12), bar),
        ("Protein bar", food(200, protein: 20, sugar: 2), protein),
        ("Frosted Pop-Tarts", food(370, protein: 4, sugar: 30), breakfast),
        ("White bread", food(70, protein: 2, sugar: 1), bread),
        ("Bagels", food(270, protein: 10, sugar: 5), bread),
        ("Candies", food(100, protein: 0, sugar: 20), sweet),
        ("Ready meal", food(400, protein: 20, sugar: 8), meal),
        ("Fruit gummies", food(80, protein: 0, sugar: 11), sweet),
        ("Instant noodles", food(380, protein: 8, sugar: 2), meal),
    ]

    @Test("an ultra-processed food's swap goes by whole words in its name, then by what's in it", arguments: swaps.indices)
    func swap(_ index: Int) {
        let (name, nutrients, advice) = Self.swaps[index]
        #expect(QualitySwap.advice(name: name, nutrients: nutrients) == advice, "\(name)")
    }

    @Test("the swap for a report's source reads its name and the entry it was last logged as")
    func swapForSource() {
        let entry = FoodEntry(
            date: Date(timeIntervalSince1970: 1_773_000_000), name: "Pastrami", foodID: "x", amountLabel: "2 slices",
            nutrients: Self.food(147, protein: 22, sugar: 0), processing: .ultraProcessed, source: .search)
        let source = QualityReport.Source(name: "Pastrami", foodID: "x", kcal: 147, share: 0.1, entry: entry)
        #expect(QualitySwap.advice(for: source) == Self.meat)
    }

    struct Portion: Equatable {
        var name: String
        var kcal: Double
        var amount = 0.0
        var yours = false
    }

    @Test("a fix's portion: the usual one unless it's a meal's worth, then the one nearest a snack's 150 kcal")
    func portions() {
        let cup = Portion(name: "cup", kcal: 220)
        let bottle = Portion(name: "bottle", kcal: 610)
        let grams100 = Portion(name: "100 g", kcal: 95)
        let grams150 = Portion(name: "150 g", kcal: 142)
        let spoon = Portion(name: "tbsp", kcal: 12)
        let cases: [(usual: Portion?, others: [Portion], expected: String?)] = [
            (cup, [grams100, grams150], "cup"),
            (bottle, [grams100, grams150, spoon], "150 g"),
            (bottle, [Portion(name: "half", kcal: 305)], nil),
            (Portion(name: "nothing", kcal: 0), [spoon], "tbsp"),
            (nil, [grams100, Portion(name: "slice", kcal: 200)], "slice"),
            (nil, [Portion(name: "a", kcal: 100), Portion(name: "b", kcal: 200)], "a"),
            (Portion(name: "just a meal", kcal: 300), [grams150], "just a meal"),
            (nil, [], nil),
        ]
        for (usual, others, expected) in cases {
            #expect(FoodFix.portion(usual: usual, others: others, kcal: \.kcal)?.name == expected, "\(String(describing: usual)) \(others)")
        }
    }

    @Test("the best nutrient fix is the most per calorie, with the person's own foods a little ahead")
    func bestFix() {
        let lentils = Portion(name: "lentils", kcal: 230, amount: 15.6)
        let raspberries = Portion(name: "raspberries", kcal: 64, amount: 8)
        let yourOats = Portion(name: "your oats", kcal: 150, amount: 4, yours: true)
        let yourPear = Portion(name: "your pear", kcal: 100, amount: 5.5, yours: true)
        let cases: [(options: [Portion], expected: String?)] = [
            ([lentils, raspberries], "raspberries"),
            ([lentils, yourOats], "lentils"),
            ([raspberries, yourPear], "raspberries"),
            ([Portion(name: "theirs", kcal: 100, amount: 6), Portion(name: "yours", kcal: 100, amount: 5, yours: true)], "yours"),
            ([], nil),
        ]
        for (options, expected) in cases {
            #expect(FoodFix.best(options, amount: \.amount, kcal: \.kcal, yours: \.yours)?.name == expected, "\(options.map(\.name))")
        }
        #expect(FoodFix.covers(5, target: 30) && !FoodFix.covers(4.9, target: 30), "a sixth of the target at least")
        #expect(!FoodFix.fits(kcal: 0) && FoodFix.fits(kcal: 300) && !FoodFix.fits(kcal: 301))
    }

    @Test("every watched nutrient has staples to offer, and the fermented ones count as fermented")
    func staples() {
        for info in Micronutrients.all where info.watched && info.goal == .atLeast {
            #expect(!(FoodFix.nutrientStaples[info.key] ?? []).isEmpty, "\(info.key)")
        }
        #expect(Set(FoodFix.nutrientStaples.keys).isSubset(of: Set(Micronutrients.all.map(\.key))))
        #expect(FoodFix.fermentedStaples.allSatisfy(Fermented.isFermented), "\(FoodFix.fermentedStaples)")
        #expect(FoodFix.fermentedStaples.first == "plain greek yogurt", "plain first: flavoured yogurts are often ultra-processed")
    }
}
