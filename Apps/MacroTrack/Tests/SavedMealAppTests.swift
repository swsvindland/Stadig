import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// Saved meals in the app model: the meal the logger is adding to, saving it, logging it again
/// whole or in part with Undo, updating it when an amount changes, renaming and deleting (with
/// Undo), and keeping it over a relaunch.
@MainActor
struct SavedMealAppTests {
    /// A banana and a coffee logged a second apart, at `date`.
    func breakfast(_ model: AppModel, at date: Date) throws -> [FoodEntry] {
        let foods = [
            try model.entry(foodID: Foods.bananaID, grams: 120, date: date),
            try model.entry(foodID: Foods.coffeeID, grams: 237, date: date.addingTimeInterval(1)),
        ]
        model.log(foods)
        return foods
    }

    /// "new", "saved Breakfast", "changed Breakfast": by name, since each save stamps the meal anew.
    func state(_ model: AppModel, _ entries: [FoodEntry]) -> String {
        switch model.saveState(of: entries) {
        case .new: "new"
        case .saved(let meal): "saved \(meal.name)"
        case .changed(let meal): "changed \(meal.name)"
        }
    }

    @Test func theLoggerShowsTheMealItIsAddingTo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        #expect(model.mealBeingLogged() == nil)

        let noon = model.today.at(hour: 12, minute: 0)
        let foods = try breakfast(model, at: noon)
        // Logging ten minutes on joins them; two hours on, or another day, starts a meal of its own.
        model.loggerTime = noon.addingTimeInterval(10 * 60)
        #expect(model.mealBeingLogged()?.entries.map(\.id) == foods.map(\.id))
        model.loggerTime = noon.addingTimeInterval(2 * 3600)
        #expect(model.mealBeingLogged() == nil)
        model.loggerTime = nil
        model.selectedDay = model.today.adding(days: -1)
        #expect(model.mealBeingLogged() == nil)
        #expect(model.mealBeingLogged(at: noon.addingTimeInterval(5 * 60)) != nil, "an asked-for time, as the Foods inspector passes, wins")
    }

    @Test func aSavedMealLogsAgainWholeOrInPartWithUndo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        // Yesterday at this time, so it's the meal Today offers now.
        let yesterday = model.today.adding(days: -1).at(sameTimeAs: Date())
        let foods = try breakfast(model, at: yesterday)
        #expect(state(model, foods) == "new")

        let meal = model.saveMeal(named: "  Banana and coffee ", from: foods)
        #expect(meal.name == "Banana and coffee")
        #expect(model.savedMeals.map(\.id) == [meal.id])
        #expect(state(model, foods) == "saved Banana and coffee")
        #expect(model.toast?.message == "Saved Banana and coffee · 2 foods")
        #expect(model.usualMeals.map(\.id) == [meal.id])

        let before = model.entries.count
        model.log(meal)
        let logged = model.entries.filter { $0.source == .recipe }
        #expect(model.entries.count == before + 2)
        #expect(logged.map(\.name) == foods.map(\.name))
        #expect(logged.map(\.nutrients) == foods.map(\.nutrients))
        #expect(logged.allSatisfy { $0.day == model.today })
        #expect(model.toast?.message.hasPrefix("Logged Banana and coffee · ") == true)
        // Eaten now, Today stops offering it.
        #expect(model.usualMeals.isEmpty)

        let toast = try #require(model.toast)
        model.undo(toast)
        #expect(model.entries.count == before)
        #expect(model.usualMeals.map(\.id) == [meal.id])

        // No coffee this time.
        model.log(meal, skipping: [meal.foods[1].id])
        #expect(model.entries.filter { $0.source == .recipe }.map(\.name) == [foods[0].name])
        #expect(model.toast?.message.hasPrefix("Logged Banana and coffee, 1 of 2") == true)
    }

    @Test func aBlankNameTakesTheSuggestedOne() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let foods = try breakfast(model, at: Date())
        let meal = model.saveMeal(named: " ", from: foods)
        #expect(meal.name == SavedMeals.suggestedName(foods))
        #expect(!meal.name.isEmpty)
    }

    @Test func aChangedAmountOffersAnUpdateOfTheMeal() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let foods = try breakfast(model, at: Date())
        let meal = model.saveMeal(named: "Breakfast", from: foods)

        var bigger = foods[0]
        bigger.nutrients = bigger.nutrients.scaled(2)
        model.update(bigger)
        let now = try #require(model.mealBeingLogged())
        #expect(state(model, now.entries) == "changed Breakfast")

        model.update(meal, from: now.entries)
        let updated = try #require(model.savedMeal(meal.id))
        #expect(updated.name == "Breakfast")
        #expect(updated.nutrients.kcal == now.nutrients.kcal)
        #expect(state(model, now.entries) == "saved Breakfast")
        #expect(model.savedMeals.count == 1)
    }

    @Test func renamingChangingAndDeletingAMeal() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let meal = model.saveMeal(named: "Breakfast", from: try breakfast(model, at: Date()))

        model.rename(meal, to: "Banana and coffee")
        model.rename(try #require(model.savedMeal(meal.id)), to: "   ")
        #expect(model.savedMeal(meal.id)?.name == "Banana and coffee")

        // Half the banana, for good.
        var half = try #require(model.savedMeal(meal.id)?.foods.first)
        half.nutrients = half.nutrients.scaled(0.5)
        model.replace(food: half.id, in: try #require(model.savedMeal(meal.id)), with: half)
        #expect(model.savedMeal(meal.id)?.foods.first?.nutrients == half.nutrients)

        // Deleted, then back with Undo; the foods logged from it stay.
        let logged = model.entries.count
        model.delete(meal: try #require(model.savedMeal(meal.id)))
        #expect(model.savedMeals.isEmpty)
        #expect(model.entries.count == logged)
        model.undo(try #require(model.toast))
        #expect(model.savedMeal(meal.id)?.name == "Banana and coffee")

        // Taking out the last food deletes it, and Undo brings it back whole, not empty.
        let whole = try #require(model.savedMeal(meal.id))
        model.replace(food: whole.foods[1].id, in: whole, with: nil)
        model.replace(food: whole.foods[0].id, in: try #require(model.savedMeal(meal.id)), with: nil)
        #expect(model.savedMeals.isEmpty)
        model.undo(try #require(model.toast))
        #expect(model.savedMeal(meal.id)?.foods.map(\.id) == [whole.foods[0].id])

        // A food that's no longer in the meal (removed on another device) changes nothing.
        let before = try #require(model.savedMeal(meal.id))
        model.replace(food: whole.foods[1].id, in: before, with: half)
        #expect(model.savedMeal(meal.id)?.foods == before.foods)
    }

    @Test func savedMealsSurviveARelaunch() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let meal = model.saveMeal(named: "Breakfast", from: try breakfast(model, at: Date()))

        let relaunched = environment.model()
        #expect(relaunched.savedMeals == [try #require(model.savedMeal(meal.id))])
        #expect(relaunched.mealSuggestions.map(\.meal.id) == [meal.id])
    }
}
