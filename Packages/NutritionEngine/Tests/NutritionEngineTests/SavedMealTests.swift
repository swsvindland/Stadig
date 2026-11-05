import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// Saved meals: logging one as its foods, which meal the logger is adding to, ranking for now from
/// the log, finding one by its name or a food in it, and a name to start from.
@Suite("Saved meals")
struct SavedMealTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let calendar = Self.calendar
    let monday = Day(year: 2026, month: 3, day: 2)

    func at(_ day: Day, _ hour: Int, _ minute: Int = 0) -> Date { day.at(hour: hour, minute: minute, calendar: calendar) }

    func food(_ name: String, _ date: Date, kcal: Double = 100, id: String? = nil, source: EntrySource = .search) -> FoodEntry {
        FoodEntry(
            date: date, day: Day(date, calendar: calendar), name: name, foodID: id ?? "usda:\(name.lowercased())", amountLabel: "1 slice",
            grams: 30, unitID: "slice", count: 1, nutrients: Nutrients(kcal: kcal, protein: kcal / 10, carbs: kcal / 8, fat: kcal / 30),
            micros: ["potassium": kcal], processing: .processed, source: source, updatedAt: date)
    }

    /// Monday's sandwich at lunch, a minute between each food.
    /// A meal's foods on the days of this suite's calendar: a new entry takes its day from the device's.
    func eaten(_ meal: SavedMeal, at date: Date) -> [FoodEntry] {
        meal.entries(at: date).map { entry in
            var entry = entry
            entry.day = Day(entry.date, calendar: calendar)
            return entry
        }
    }

    func sandwich(_ day: Day, hour: Int = 12) -> [FoodEntry] {
        ["Bread, whole-wheat", "Turkey breast, deli", "Cheese, swiss", "Lettuce, romaine", "Mayonnaise"].enumerated().map { i, name in
            food(name, at(day, hour, i), kcal: [140, 60, 110, 5, 90][i])
        }
    }

    @Test("logging a meal makes new entries of its foods, in order, at the time asked, leaving out the ones skipped")
    func logging() {
        let meal = SavedMeal(name: "Turkey sandwich", from: sandwich(monday).reversed())
        #expect(meal.foods.map(\.name).first == "Bread, whole-wheat")
        #expect(meal.nutrients.kcal == 405)

        let tuesday = at(monday.adding(days: 1), 12, 30)
        let logged = meal.entries(at: tuesday)
        #expect(logged.count == 5)
        #expect(logged.map(\.date) == (0..<5).map { tuesday.addingTimeInterval(Double($0)) })
        #expect(logged.allSatisfy { $0.source == .recipe && $0.day == Day(tuesday) })
        #expect(Set(logged.map(\.id)).isDisjoint(with: meal.foods.map(\.id)))
        // Everything about each food as it was logged: the amount, the numbers, its quality.
        #expect(logged[0].foodID == "usda:bread, whole-wheat" && logged[0].unitID == "slice" && logged[0].count == 1)
        #expect(logged[0].nutrients == meal.foods[0].nutrients && logged[0].micros == meal.foods[0].micros)
        #expect(logged[0].processing == .processed)

        // No cheese today: the rest still a second apart.
        let skipped = meal.entries(at: tuesday, skipping: [meal.foods[2].id])
        #expect(skipped.map(\.name) == ["Bread, whole-wheat", "Turkey breast, deli", "Lettuce, romaine", "Mayonnaise"])
        #expect(skipped.last?.date == tuesday.addingTimeInterval(3))
    }

    @Test("the logger adds to the moment a food logged then would join, or starts one")
    func joining() {
        let lunch = sandwich(monday)
        let snack = food("Apple", at(monday, 15))
        let day = lunch + [snack]

        // Straight after the last food, and up to 45 minutes after.
        #expect(Timeline.moment(joining: at(monday, 12, 10), in: day)?.entries.count == 5)
        #expect(Timeline.moment(joining: at(monday, 12, 49), in: day)?.entries.count == 5)
        // Further on, a new moment.
        #expect(Timeline.moment(joining: at(monday, 13, 30), in: day) == nil)
        #expect(Timeline.moment(joining: at(monday, 15, 20), in: day)?.entries.map(\.name) == ["Apple"])
        // Before a moment, within the gap, it joins that one.
        #expect(Timeline.moment(joining: at(monday, 11, 30), in: day)?.entries.count == 5)
        // A food between two moments joins them into one, as the timeline would show it.
        let late = food("Banana", at(monday, 13, 20))
        #expect(Timeline.moment(joining: at(monday, 12, 40), in: lunch + [late])?.entries.count == 6)
        #expect(Timeline.moment(joining: at(monday, 8), in: []) == nil)
    }

    @Test("meals rank by when they're eaten, logged as a meal or food by food; never eaten comes last")
    func ranking() {
        let sandwichMeal = SavedMeal(name: "Turkey sandwich", from: sandwich(monday), updatedAt: at(monday, 13))
        let oats = SavedMeal(
            name: "Oats", from: [food("Oats", at(monday, 7)), food("Blueberries", at(monday, 7, 1)), food("Milk", at(monday, 7, 2))],
            updatedAt: at(monday, 8))
        let new = SavedMeal(name: "Smoothie", from: [food("Banana", at(monday, 9)), food("Whey", at(monday, 9))], updatedAt: at(monday, 20))

        // A week of lunches, the sandwich by hand with a drink beside it, then as the meal; oats on two mornings.
        var entries: [FoodEntry] = []
        for offset in 0..<5 {
            let day = monday.adding(days: offset)
            entries += offset < 2 ? sandwich(day) + [food("Coffee", at(day, 12, 6))] : eaten(sandwichMeal, at: at(day, 12, 15))
        }
        entries += eaten(oats, at: at(monday.adding(days: 2), 7)) + eaten(oats, at: at(monday.adding(days: 3), 7, 30))
        // Half a sandwich isn't the sandwich.
        entries += Array(sandwich(monday.adding(days: 5)).prefix(3))

        let noon = SavedMeals.rank([oats, new, sandwichMeal], entries: entries, now: at(monday.adding(days: 6), 12, 20), calendar: calendar)
        #expect(noon.map(\.meal.name) == ["Turkey sandwich", "Oats", "Smoothie"])
        #expect(noon[0].usualNow && !noon[1].usualNow && !noon[2].usualNow)
        #expect(noon[2].score == 0)
        // Once today's lunch is logged, it isn't offered again, though it still ranks first.
        let lunch = eaten(sandwichMeal, at: at(monday.adding(days: 6), 12, 5))
        let after = SavedMeals.rank([oats, sandwichMeal], entries: entries + lunch, now: at(monday.adding(days: 6), 12, 20), calendar: calendar)
        #expect(after.map(\.meal.name) == ["Turkey sandwich", "Oats"])
        #expect(!after[0].usualNow)
        // Also at the moment it's logged, with its last food still a few seconds ahead of the clock.
        let logging = SavedMeals.rank([sandwichMeal], entries: entries + lunch, now: lunch[0].date, calendar: calendar)
        #expect(!logging[0].usualNow)

        let morning = SavedMeals.rank([sandwichMeal, oats, new], entries: entries, now: at(monday.adding(days: 6), 7, 15), calendar: calendar)
        #expect(morning.map(\.meal.name) == ["Oats", "Turkey sandwich", "Smoothie"])
        #expect(morning[0].usualNow && !morning[1].usualNow)

        // Two never eaten: the newest saved first. Nothing eaten on a later day counts.
        let early = SavedMeals.rank([oats, new], entries: entries, now: at(monday, 6), calendar: calendar)
        #expect(early.map(\.meal.name) == ["Smoothie", "Oats"])
        #expect(early.allSatisfy { $0.score == 0 && !$0.usualNow })
        // Over a month ago it still ranks, but isn't offered as usual now.
        let later = SavedMeals.rank([sandwichMeal], entries: entries, now: at(monday.adding(days: 40), 12), calendar: calendar)
        #expect(later[0].score > 0 && !later[0].usualNow)
        #expect(SavedMeals.rank([], entries: entries, now: at(monday, 12), calendar: calendar).isEmpty)
    }

    @Test("a search finds meals by name, then by a food in them, every word typed")
    func matching() {
        let meals = [
            SavedMeal(name: "Turkey sandwich", from: sandwich(monday)),
            SavedMeal(name: "Club", from: [food("Turkey, roasted", at(monday, 18)), food("Bacon", at(monday, 18))]),
            SavedMeal(name: "Café breakfast", from: [food("Croissant", at(monday, 8)), food("Latte", at(monday, 8))]),
        ]
        #expect(SavedMeals.matching("turkey", in: meals).map(\.name) == ["Turkey sandwich", "Club"])
        #expect(SavedMeals.matching("SAND tur", in: meals).map(\.name) == ["Turkey sandwich"])
        #expect(SavedMeals.matching("cafe", in: meals).map(\.name) == ["Café breakfast"])
        #expect(SavedMeals.matching("swiss", in: meals).map(\.name) == ["Turkey sandwich"])
        #expect(SavedMeals.matching("pizza", in: meals).isEmpty)
        #expect(SavedMeals.matching("  ", in: meals).isEmpty)
    }

    @Test("the same foods are the same meal, whatever their order or amounts")
    func sameMeal() {
        let saved = SavedMeal(name: "Turkey sandwich", from: sandwich(monday))
        var again = sandwich(monday.adding(days: 1)).reversed().map { $0 }
        again[0].count = 2
        #expect(SavedMeals.meal(for: again, in: [saved])?.id == saved.id)
        #expect(SavedMeals.meal(for: Array(again.dropLast()), in: [saved]) == nil)
        #expect(SavedMeals.meal(for: again + [food("Apple", at(monday, 12, 9))], in: [saved]) == nil)
        #expect(SavedMeals.meal(for: [], in: [saved]) == nil)
        // Logged as it was saved, it's the same; with twice the bread, it's the meal changed.
        #expect(saved.hasSameAmounts(as: eaten(saved, at: at(monday, 13)).reversed()))
        var more = eaten(saved, at: at(monday, 13))
        more[0].nutrients.kcal *= 2
        #expect(!saved.hasSameAmounts(as: more))
        #expect(!saved.hasSameAmounts(as: Array(saved.foods.dropLast())))
        // Foods without a catalog id go by name and brand.
        let quick = [
            FoodEntry(date: at(monday, 9), name: "Toast", amountLabel: "1", nutrients: .zero, source: .description),
            FoodEntry(date: at(monday, 9), name: "Jam", brand: "Bonne Maman", amountLabel: "1", nutrients: .zero, source: .description),
        ]
        let toast = SavedMeal(name: "Toast", from: quick)
        #expect(SavedMeals.meal(for: eaten(toast, at: at(monday, 10)), in: [saved, toast])?.id == toast.id)
    }

    @Test("of two meals with the same foods, the one in the same amounts is the one eaten")
    func twoMealsOfTheSameFoods() {
        let full = SavedMeal(name: "Sandwich", from: sandwich(monday))
        var lighter = sandwich(monday)
        lighter[0].nutrients.kcal = 70
        lighter[0].grams = 15
        let light = SavedMeal(name: "Light sandwich", from: lighter)
        // Either order: the newer one isn't taken for the other.
        for meals in [[light, full], [full, light]] {
            #expect(SavedMeals.meal(for: eaten(full, at: at(monday, 13)), in: meals)?.id == full.id)
            #expect(SavedMeals.meal(for: eaten(light, at: at(monday, 13)), in: meals)?.id == light.id)
        }
        // Neither as saved: the first, to update.
        var other = eaten(full, at: at(monday, 13))
        other[1].nutrients.kcal = 120
        #expect(SavedMeals.meal(for: other, in: [light, full])?.id == light.id)
    }

    @Test("a different amount of something with no calories is still a change")
    func amountsWithoutCalories() {
        let water = [
            FoodEntry(date: at(monday, 8), name: "Water", foodID: "usda:water", amountLabel: "250 ml", grams: 250, nutrients: .zero, source: .search),
            FoodEntry(
                date: at(monday, 8), name: "Oats", foodID: "usda:oats", amountLabel: "40 g", grams: 40,
                nutrients: Nutrients(kcal: 150, protein: 5, carbs: 27, fat: 3), source: .search),
        ]
        let meal = SavedMeal(name: "Oats and water", from: water)
        var more = eaten(meal, at: at(monday, 9))
        more[0].grams = 500
        #expect(!meal.hasSameAmounts(as: more))
        #expect(meal.hasSameAmounts(as: eaten(meal, at: at(monday, 9))))
    }

    @Test("dinner eaten just before midnight isn't offered again just after")
    func aroundMidnight() {
        let dinner = SavedMeal(name: "Late dinner", from: [food("Pasta", at(monday, 23, 30)), food("Sauce", at(monday, 23, 31))])
        let week = (0..<4).flatMap { eaten(dinner, at: at(monday.adding(days: $0), 23, 30)) }
        // At 12:15 AM, the dinner of 45 minutes ago (yesterday by the calendar) has just been eaten.
        let after = SavedMeals.rank([dinner], entries: week, now: at(monday.adding(days: 4), 0, 15), calendar: calendar)
        #expect(after[0].score > 0 && !after[0].usualNow)
        // The next evening, it is.
        let evening = SavedMeals.rank([dinner], entries: week, now: at(monday.adding(days: 4), 23, 10), calendar: calendar)
        #expect(evening[0].usualNow)
    }

    @Test("a name to start from: the biggest three foods, as eaten, short")
    func names() {
        #expect(SavedMeals.suggestedName(sandwich(monday)) == "Bread, cheese and mayonnaise +2")
        #expect(SavedMeals.suggestedName([food("Oats, rolled", at(monday, 7)), food("Milk, 2%", at(monday, 7, 1))]) == "Oats and milk")
        #expect(
            SavedMeals.suggestedName([food("KIND bar", at(monday, 7), kcal: 200), food("Coca-Cola", at(monday, 7, 1))]) == "KIND bar and Coca-Cola")
        #expect(SavedMeals.suggestedName([food("Apple", at(monday, 7))]) == "Apple")
        #expect(SavedMeals.suggestedName([]) == "")
    }

    @Test("a saved meal survives a round trip through JSON")
    func coding() throws {
        let meal = SavedMeal(name: "Turkey sandwich", from: sandwich(monday))
        let decoded = try JSONDecoder().decode(SavedMeal.self, from: JSONEncoder().encode(meal))
        #expect(decoded == meal)
    }
}
