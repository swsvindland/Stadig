import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// Today's composer: what's typed read into foods and amounts, the person's own foods offered ahead
/// of the catalog's, and what goes with a food just logged.
@Suite("Adding food by typing")
struct AddFoodTests {
    func one(_ text: String) -> AddFoodPart {
        let parts = AddFoodText.parse(text)
        #expect(parts.count == 1, "\(text) is one part: \(parts)")
        return parts[0]
    }

    @Test("a bare number after the words is the amount, and the words are the search")
    func numberAfterWords() {
        let part = one("chick 200")
        #expect(part.kind == .food)
        #expect(part.words == ["chick"])
        #expect(part.amount == AddFoodAmount(count: 200, unit: nil, multiplier: false))
        // Weighed food: 200 is grams. Counted food: more than a dozen is grams too.
        #expect(part.amount?.portion(counted: false) == .basis(200))
        #expect(part.amount?.portion(counted: true) == .basis(200))
    }

    @Test("commas make several foods, and a part with nothing after its comma is still being typed")
    func commas() {
        let parts = AddFoodText.parse("2 eggs, toast, coff")
        #expect(parts.map(\.words) == [["eggs"], ["toast"], ["coff"]])
        #expect(parts[0].amount == AddFoodAmount(count: 2, unit: .egg, multiplier: false))
        #expect(parts[0].amount?.portion(counted: true) == .pieces(nil, 2))
        #expect(parts[1].amount == nil)

        let typing = AddFoodText.parse("2 eggs, ")
        #expect(typing.map(\.kind) == [.food, .typing])
        #expect(AddFoodText.loggable(typing).count == 1)
        // Empty parts between commas are nothing.
        #expect(AddFoodText.parse("toast,, coffee").map(\.words) == [["toast"], ["coffee"]])
        #expect(AddFoodText.parse("").isEmpty)
        #expect(AddFoodText.parse("   ").isEmpty)
    }

    @Test(
        "units stuck to their number or apart, in either order",
        arguments: [
            ("200g chicken", 200.0, AddFoodUnit.gram, ["chicken"]),
            ("chicken 200 g", 200, .gram, ["chicken"]),
            ("1.5kg potatoes", 1.5, .kilogram, ["potatoes"]),
            ("330ml cola", 330, .millilitre, ["cola"]),
            ("1/2 cup oats", 0.5, .cup, ["oats"]),
            ("½ cup oats", 0.5, .cup, ["oats"]),
            ("1½ cups rice", 1.5, .cup, ["rice"]),
            ("2 tbsp peanut butter", 2, .tablespoon, ["peanut", "butter"]),
            ("1 tsp honey", 1, .teaspoon, ["honey"]),
            ("6 oz steak", 6, .ounce, ["steak"]),
            ("2 slices toast", 2, .slice, ["toast"]),
            ("1 scoop whey", 1, .scoop, ["whey"]),
            ("2 servings chili", 2, .serving, ["chili"]),
            ("two eggs", 2, .egg, ["eggs"]),
        ])
    func units(text: String, count: Double, unit: AddFoodUnit, words: [String]) {
        let part = one(text)
        #expect(part.amount?.count == count)
        #expect(part.amount?.unit == unit)
        #expect(part.words == words)
    }

    @Test("what each unit means for a food")
    func portions() {
        func portion(_ text: String, counted: Bool = false) -> AddFoodPortion? { one(text).amount?.portion(counted: counted) }
        #expect(portion("1.5 kg potatoes") == .basis(1500))
        #expect(portion("0.5 l milk") == .basis(500))
        #expect(portion("6 oz steak") == .measure("oz", 6))
        #expect(portion("1 cup rice") == .measure("cup", 1))
        #expect(portion("2 slices bread", counted: true) == .pieces("slice", 2))
        #expect(portion("1 scoop whey", counted: true) == .pieces("scoop", 1))
        // A small bare number of something weighed is that many of the usual amount, not 2 grams.
        #expect(portion("2 yogurt") == .times(2))
        #expect(portion("banana 1", counted: true) == .pieces(nil, 1))
    }

    @Test("x and × multiply the usual amount, before or after the food")
    func multipliers() {
        for text in ["yogurt x2", "yogurt ×2", "2x yogurt", "2 x yogurt", "yogurt x 2", "2× yogurt"] {
            let part = one(text)
            #expect(part.words == ["yogurt"], "\(text)")
            #expect(part.amount == AddFoodAmount(count: 2, unit: nil, multiplier: true), "\(text)")
            #expect(part.amount?.portion(counted: true) == .times(2))
        }
    }

    @Test("a number of calories is a quick add, named by any other words")
    func quickAdd() {
        #expect(one("500 kcal").kind == .quickAdd(kcal: 500))
        #expect(one("500kcal").kind == .quickAdd(kcal: 500))
        #expect(one("300 cal").kind == .quickAdd(kcal: 300))
        #expect(one("120 calories").kind == .quickAdd(kcal: 120))
        let named = one("pizza 800 kcal")
        #expect(named.kind == .quickAdd(kcal: 800))
        #expect(named.words == ["pizza"])
        // In a list, with foods.
        #expect(AddFoodText.parse("toast, 200 kcal").map(\.kind) == [.food, .quickAdd(kcal: 200)])
    }

    @Test("filler words and a number with no food leave nothing to search")
    func fillers() {
        #expect(one("a bowl of oats").words == ["bowl", "oats"])
        #expect(one("some granola").words == ["granola"])
        let number = one("200")
        #expect(number.words.isEmpty)
        #expect(AddFoodText.loggable([number]).isEmpty)
        // A number inside a word is part of the name.
        #expect(one("7up").words == ["7up"])
        #expect(one("7up").amount == nil)
    }

    @Test("a typed word matches the start of a word of the name, plurals included")
    func prefixMatching() {
        #expect(AddFoodRanking.matches(["chick"], name: "Chicken breast, roasted"))
        #expect(AddFoodRanking.matches(["chick", "bre"], name: "Chicken breast, roasted"))
        #expect(!AddFoodRanking.matches(["hick"], name: "Chicken breast, roasted"))
        #expect(AddFoodRanking.matches(["eggs"], name: "Egg, whole, scrambled"))
        #expect(AddFoodRanking.matches(["tomatoes"], name: "Tomato, raw"))
        #expect(AddFoodRanking.matches(["berries"], name: "Blueberry muffin") == false)
        #expect(AddFoodRanking.matches(["creme"], name: "Crème fraîche"))
        #expect(!AddFoodRanking.matches([], name: "Anything"))
    }

    struct Candidate: Equatable {
        var name: String
        var own: Double?
    }

    @Test("the person's own foods come ahead of the catalog's for the same words, best first")
    func ownFirst() {
        let catalog = [
            Candidate(name: "Chickpeas, canned"), Candidate(name: "Chicken thigh, roasted"),
            Candidate(name: "Chicken breast, roasted", own: 2.5), Candidate(name: "Peas and chick mix"),
            Candidate(name: "Chicken nuggets", own: 0.4), Candidate(name: "Kale chips"),
        ]
        let ranked = AddFoodRanking.rank(catalog, words: ["chick"], name: \.name, own: \.own)
        #expect(
            ranked.map(\.name) == [
                "Chicken breast, roasted", "Chicken nuggets", "Chickpeas, canned", "Chicken thigh, roasted", "Peas and chick mix", "Kale chips",
            ])
        // An own food that doesn't match the words doesn't jump the catalog's that do.
        let off = AddFoodRanking.rank([Candidate(name: "Oats"), Candidate(name: "Banana", own: 9)], words: ["oat"], name: \.name, own: \.own)
        #expect(off.map(\.name) == ["Oats", "Banana"])
    }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return c
    }()

    func food(_ name: String, _ day: Day, _ hour: Int, _ minute: Int = 0, source: EntrySource = .search) -> FoodEntry {
        let date = day.at(hour: hour, minute: minute, calendar: Self.calendar)
        return FoodEntry(
            date: date, day: day, name: name, foodID: "usda:\(name.lowercased())", amountLabel: "1 serving",
            nutrients: Nutrients(kcal: 100, protein: 5, carbs: 10, fat: 3), source: source, updatedAt: date)
    }

    @Test("what goes with a food is what's been eaten in the same moment with it, often and lately first")
    func goesWith() {
        let today = Day(year: 2026, month: 11, day: 11)
        var entries: [FoodEntry] = []
        for back in 1...14 {
            let day = today.adding(days: -back)
            entries += [food("Yogurt", day, 8), food("Honey", day, 8, 1)]
            if back <= 3 { entries.append(food("Blueberries", day, 8, 2)) }
            if back > 10 { entries.append(food("Granola", day, 8, 2)) }
            // Lunch is another moment: it doesn't go with yogurt.
            entries += [food("Chicken", day, 12, 30), food("Rice", day, 12, 31)]
            if back == 2 { entries.append(food("Quick add", day, 8, 3, source: .quickAdd)) }
        }
        let now = today.at(hour: 8, minute: 5, calendar: Self.calendar)
        let logged = food("Yogurt", today, 8, 4)
        let ranked = GoesWith.rank(with: [logged], entries: entries + [logged], now: now, calendar: Self.calendar)
        #expect(ranked.map(\.template.name) == ["Honey", "Blueberries", "Granola"])
        #expect(ranked[0].timesLogged == 14)
        // Today's own moment isn't the history: nothing goes with a food never eaten before.
        #expect(GoesWith.rank(with: [food("Pho", today, 8)], entries: entries, now: now, calendar: Self.calendar).isEmpty)
        #expect(GoesWith.rank(with: [], entries: entries, now: now, calendar: Self.calendar).isEmpty)
    }
}
