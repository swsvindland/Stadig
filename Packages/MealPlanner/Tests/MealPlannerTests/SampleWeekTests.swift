import Foundation
import SystemCore
import Testing

@testable import MealPlanner

/// `PRINT_PLAN=1 swift test --filter SampleWeek` prints a week, its groceries and prep day, to read.
@Suite("Sample week", .enabled(if: ProcessInfo.processInfo.environment["PRINT_PLAN"] != nil))
struct SampleWeekTests {
    @Test func printWeek() {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: Set(MealSlot.allCases)))
        for recipe in plan.recipes {
            let n = recipe.nutrients
            print(
                "\n\(recipe.title) ×\(recipe.servings): \(Int(n.kcal)) kcal, \(Int(n.protein)) P, \(Int(n.carbs)) C, \(Int(n.fat)) F, fibre \(Int(n.fiber ?? 0))"
            )
            for item in recipe.items { print("   \(Int(item.grams)) g \(item.name)\(item.onTheDay ? " (on the day)" : "")") }
        }
        let day = plan.planned(on: monday)
        print("\nDay: \(Int(day.kcal)) kcal, \(Int(day.protein)) P, \(Int(day.carbs)) C, \(Int(day.fat)) F of \(cut)")
        print("\nGroceries")
        for item in Groceries.list(for: plan) {
            print(
                "   [\(item.aisle.label)] \(item.name): \(Int(item.grams)) g\(item.count.map { " (\($0) \(item.unit!))" } ?? "")\(item.pantry ? " · pantry" : "")"
            )
        }
        let guide = PrepGuide.make(for: plan)
        print("\nPrep: \(guide.minutes) min, \(guide.containers) containers")
        for step in guide.steps { print("   \(step.minute)' (\(step.minutes)m\(step.handsOn ? "" : ", waiting")) \(step.title): \(step.detail)") }
        for pack in guide.packing {
            print(
                "   PACK \(pack.title) ×\(pack.servings): \(pack.contents.map { "\(Int($0.grams)) g \($0.name)" }.joined(separator: ", ")) | on the day: \(pack.onTheDay.map(\.name))"
            )
        }
    }
}
