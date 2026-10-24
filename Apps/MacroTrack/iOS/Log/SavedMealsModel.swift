import Foundation
import NutritionEngine
import SystemCore
import SystemStore

/// What foods eaten together are to the saved meals: none of them, one of them as it was saved, or
/// one of them with an amount changed.
enum MealSaveState: Equatable {
    case new
    case saved(SavedMeal)
    case changed(SavedMeal)
}

extension AppModel {
    func savedMeal(_ id: UUID) -> SavedMeal? { savedMeals.first { $0.id == id } }

    /// The foods a food logged at `date` (else at the open logger's time) would join: the meal the
    /// logger is adding to, so what's gone in so far stays in sight.
    func mealBeingLogged(at date: Date? = nil) -> Moment? {
        let date = date ?? logDate()
        return Timeline.moment(joining: date, in: entries(on: Day(date)))
    }

    /// Saved meals worth a chip on Today: eaten around this time of day in the last month.
    var usualMeals: [SavedMeal] { mealSuggestions.filter(\.usualNow).prefix(3).map(\.meal) }

    func saveState(of entries: [FoodEntry]) -> MealSaveState {
        guard let meal = SavedMeals.meal(for: entries, in: savedMeals) else { return .new }
        return meal.hasSameAmounts(as: entries) ? .saved(meal) : .changed(meal)
    }

    /// Saves foods eaten together as a meal; a blank name takes the suggested one. Returns it as
    /// stored (stamped, its times to the millisecond).
    @discardableResult
    func saveMeal(named name: String, from entries: [FoodEntry]) -> SavedMeal {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let meal = SavedMeal(name: trimmed.isEmpty ? SavedMeals.suggestedName(entries) : trimmed, from: entries)
        save(meal, message: "Saved \(meal.name) · \(meal.foods.count) foods")
        return savedMeal(meal.id) ?? meal
    }

    /// The meal's foods as they were just eaten, under the same name.
    func update(_ meal: SavedMeal, from entries: [FoodEntry]) {
        var meal = meal
        meal.foods = SavedMeal(name: meal.name, from: entries).foods
        save(meal, message: "Updated \(meal.name)")
    }

    func rename(_ meal: SavedMeal, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != meal.name else { return }
        var meal = meal
        meal.name = trimmed
        save(meal)
    }

    /// One food of a meal changed (its amount), or taken out for good. It's found by its id, so a
    /// meal changed meanwhile (synced in, or in another window) doesn't get the wrong food. The last
    /// food out deletes the meal, and its Undo brings the meal back as it was.
    func replace(food id: UUID, in meal: SavedMeal, with food: FoodEntry?) {
        guard let index = meal.foods.firstIndex(where: { $0.id == id }) else { return }
        var changed = meal
        if let food { changed.foods[index] = food } else { changed.foods.remove(at: index) }
        if changed.foods.isEmpty { delete(meal: meal) } else { save(changed) }
    }

    /// Saves a meal, stamped later than the copy it edits (see `save(settings:)`).
    func save(_ meal: SavedMeal, message: String? = nil) {
        var meal = meal
        meal.updatedAt = max(Date(), meal.updatedAt.addingTimeInterval(0.001))
        store.save(meal)
        reload()
        if let message { toast = Toast(message: message) }
    }

    func delete(meal: SavedMeal) {
        store.delete(SavedMeal.self, id: meal.id)
        reload()
        toast = Toast(message: "Deleted \(meal.name)", deletedMeal: meal)
    }

    /// A saved meal eaten at the logger's time (or `date`), leaving out the foods in `skipping`.
    func log(_ meal: SavedMeal, skipping: Set<UUID> = [], at date: Date? = nil) {
        let entries = meal.entries(at: date ?? logDate(), skipping: skipping)
        log(entries, message: skipping.isEmpty ? "Logged \(meal.name)" : "Logged \(meal.name), \(entries.count) of \(meal.foods.count)")
    }
}
