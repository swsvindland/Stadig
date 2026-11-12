import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// "What fits tonight": the evening's usual foods, one or two at a time, that finish the day's
/// calories with as much of the protein left as they can.
@Suite("What fits tonight")
struct WhatFitsTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    let today = Day(year: 2026, month: 11, day: 11)

    func food(_ name: String, kcal: Double, protein: Double) -> FoodEntry {
        let date = today.at(hour: 20, minute: 0, calendar: Self.calendar)
        return FoodEntry(
            date: date, day: today, name: name, foodID: "usda:\(name.lowercased())", amountLabel: "1 serving",
            nutrients: Nutrients(kcal: kcal, protein: protein, carbs: kcal / 8, fat: kcal / 40), source: .search, updatedAt: date)
    }

    var usual: [FoodEntry] {
        [
            food("Shake", kcal: 120, protein: 24), food("Banana", kcal: 105, protein: 1.3), food("Yogurt", kcal: 146, protein: 20),
            food("Blueberries", kcal: 46, protein: 0.6), food("Chicken", kcal: 290, protein: 54), food("Rice", kcal: 275, protein: 6),
            food("Coffee", kcal: 2, protein: 0.3), food("Ice cream", kcal: 520, protein: 8),
        ]
    }

    @Test("the best option covers the protein left and lands on the calories")
    func best() throws {
        let options = WhatFits.options(usual, left: Nutrients(kcal: 412, protein: 46, carbs: 49, fat: 6))
        let first = try #require(options.first)
        // Shake and chicken would land on the calories too, with 32 g of protein more than's left.
        #expect(first.items.map(\.name) == ["Banana", "Chicken"])
        #expect(first.onTarget)
        #expect(first.leaves == 17)
        #expect(options.count == 3)
    }

    @Test("nothing goes far over, nothing is too small to be a meal, and no food is offered twice")
    func bounds() {
        let options = WhatFits.options(usual, left: Nutrients(kcal: 412, protein: 46, carbs: 49, fat: 6))
        #expect(options.allSatisfy { $0.leaves >= -WhatFits.onTarget })
        let names = options.flatMap { $0.items.map(\.name) }
        #expect(!names.contains("Ice cream"))
        #expect(!names.contains("Coffee"))
        #expect(Set(names).count == names.count)
    }

    @Test("too little left, or nothing to suggest, offers nothing")
    func nothing() {
        #expect(WhatFits.options(usual, left: Nutrients(kcal: 100, protein: 10, carbs: 0, fat: 0)).isEmpty)
        #expect(WhatFits.options([], left: Nutrients(kcal: 600, protein: 40, carbs: 0, fat: 0)).isEmpty)
    }

    @Test("two foods go together only if they've been eaten together")
    func together() {
        let day = today.adding(days: -2)
        func at(_ entry: FoodEntry, _ hour: Int) -> FoodEntry {
            var entry = entry
            entry.date = day.at(hour: hour, minute: 0, calendar: Self.calendar)
            entry.day = day
            return entry
        }
        let foods = usual
        // Shake and banana after training, yogurt and blueberries at breakfast, chicken and rice at dinner.
        let history = [at(foods[0], 15), at(foods[1], 15), at(foods[2], 8), at(foods[3], 8), at(foods[4], 19), at(foods[5], 19)]
        let options = WhatFits.options(foods, left: Nutrients(kcal: 412, protein: 46, carbs: 49, fat: 6), history: history)
        let pairs = options.filter { $0.items.count == 2 }.map { $0.items.map(\.name) }
        #expect(!pairs.isEmpty)
        #expect(pairs.allSatisfy { [["Shake", "Banana"], ["Yogurt", "Blueberries"], ["Chicken", "Rice"]].contains($0) })
        // Chicken alone covers the protein; with rice it would go over.
        #expect(options.first?.items.map(\.name) == ["Chicken"])
    }

    @Test("the evening starts at five")
    func evening() {
        #expect(!WhatFits.isEvening(today.at(hour: 16, minute: 59, calendar: Self.calendar), calendar: Self.calendar))
        #expect(WhatFits.isEvening(today.at(hour: 17, minute: 0, calendar: Self.calendar), calendar: Self.calendar))
    }
}
