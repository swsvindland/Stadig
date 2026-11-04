import FoodDatabase
import Foundation
import HealthBridge
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore

extension AppModel {
    /// The plan being eaten from, or the next one when it's waiting for its prep day.
    var mealPlan: MealPlan? {
        mealPlans.last { $0.end >= today }
    }

    /// The plan with meals on a day.
    func mealPlan(covering day: Day) -> MealPlan? {
        mealPlans.last { $0.covers(day) }
    }

    /// Today's targets for planning; while the assessment runs (no calorie target yet), maintenance.
    var planTargets: PlanTargets {
        let analysis = analysis
        let kcal = analysis?.targets.kcal ?? analysis?.maintenance.kcal ?? 2200
        let macros = Targets.macros(kcal: kcal, referenceKg: analysis?.referenceKg ?? 75, phase: analysis?.phase?.kind)
        return PlanTargets(
            kcal: kcal, protein: analysis?.targets.protein ?? macros.protein, carbs: analysis?.targets.carbs ?? macros.carbs,
            fat: analysis?.targets.fat ?? macros.fat)
    }

    /// The Monday after today, prepped on Sunday; or tomorrow, prepped today.
    func planStart(tomorrow: Bool) -> Day {
        if tomorrow { return today.adding(days: 1) }
        return today.startOfWeek.adding(days: 7)
    }

    /// What the last plan asked for, to start the next one from.
    var lastPlanPreferences: PlanPreferences { mealPlans.last?.preferences ?? PlanPreferences() }

    /// A new week. It replaces a plan that hasn't started; one being eaten from ends where this begins.
    /// A week replaced from the same day keeps its id, so a screen showing it shows the new one.
    @discardableResult
    func makeMealPlan(preferences: PlanPreferences, start: Day) -> MealPlan {
        let recent = Set(mealPlans.last?.recipes.map(\.id) ?? [])
        planVariation = 0
        var plan = planner.plan(start: start, targets: planTargets, preferences: preferences, recent: recent)
        if let replaced = mealPlans.first(where: { $0.start == start && $0.start > today }) {
            plan.id = replaced.id
            plan.createdAt = replaced.createdAt
        }
        for old in mealPlans where old.id != plan.id && (old.start >= start || (old.covers(start) && old.start > today)) {
            store.delete(MealPlan.self, id: old.id)
        }
        save(plan)
        return plan
    }

    /// Dishes still to come, in the plan's order: only these can be swapped; the others stay on the
    /// days they were eaten.
    func swappableRecipes(in plan: MealPlan) -> [String] { planner.swappable(plan, today: today) }

    /// The same preferences, another set of dishes for every one still to come; the days already
    /// eaten and the meals logged keep theirs, as a single swap does.
    func shuffleMealPlan(_ plan: MealPlan) {
        guard !swappableRecipes(in: plan).isEmpty else { return }
        planVariation += 1
        save(planner.shuffle(plan, variation: planVariation))
    }

    func swap(_ recipeID: String, in plan: MealPlan) {
        planVariation += 1
        save(planner.swap(recipeID, in: plan, variation: planVariation))
    }

    /// Reads a request ("no fish, more spicy") and replans the week with it. Returns what changed,
    /// in words, or nil when nothing in it applied.
    func applyRequest(_ text: String, to plan: MealPlan) async -> String? {
        let change = await PlanAssistant().read(text, allowCloud: settings.allowCloudAI)
        // A plan deleted while the model was reading stays deleted.
        guard !change.isEmpty, let current = mealPlans.first(where: { $0.id == plan.id }) else { return nil }
        save(planner.replan(current, preferences: change.applied(to: current.preferences), targets: planTargets))
        return change.summary
    }

    func deleteMealPlan(_ plan: MealPlan) {
        store.delete(MealPlan.self, id: plan.id)
        reloadMealPlans()
    }

    func toggleGrocery(_ id: String, in plan: MealPlan) {
        guard var plan = mealPlans.first(where: { $0.id == plan.id }) else { return }
        if plan.checked.contains(id) { plan.checked.remove(id) } else { plan.checked.insert(id) }
        save(plan)
    }

    private func save(_ plan: MealPlan) {
        var plan = plan
        plan.updatedAt = Date()
        store.save(plan)
        reloadMealPlans()
    }

    // MARK: Eating from the plan

    /// Logged, as long as what was logged is still there (Undo or a delete un-logs it). Looked for
    /// from the newest entry back, where a meal logged from the plan is: years of history aren't
    /// walked for each meal on screen.
    func isLogged(_ meal: PlannedMeal, in plan: MealPlan) -> Bool {
        guard let ids = plan.logged[meal.id] else { return false }
        return foodLog.all.reversed().contains { ids.contains($0.id) }
    }

    /// The plan's meals logged and still in the log, by meal id: `isLogged` for a whole week at once,
    /// looking only at the plan's own days, where a meal from it is logged.
    func loggedMeals(in plan: MealPlan) -> Set<String> {
        guard !plan.logged.isEmpty else { return [] }
        let present = Set(plan.days.flatMap { allEntries(on: $0) }.map(\.id))
        return Set(plan.logged.filter { !present.isDisjoint(with: $0.value) }.keys)
    }

    /// One tap: the container (and what goes with it) as one entry, at the time it's logged.
    func logPlanned(_ meal: PlannedMeal, in plan: MealPlan) {
        guard let recipe = plan.recipe(meal.recipeID) else { return }
        // Today, when it's logged; a day being caught up, at the meal's usual time.
        let date = meal.day == today ? logDate() : meal.day.at(minutes: Int((meal.slot.hour * 60).rounded()))
        let entry = Self.entry(for: recipe, date: date)
        log([entry], message: "Logged \(recipe.title)")
        guard var plan = mealPlans.first(where: { $0.id == plan.id }) else { return }
        plan.logged[meal.id] = [entry.id]
        save(plan)
    }

    /// A planned dish as one entry: its numbers summed, its processing the group most of its
    /// calories come from, fermented if anything in it is.
    static func entry(for recipe: PlannedRecipe, date: Date) -> FoodEntry {
        let n = recipe.nutrients
        var micros: [String: Double] = [:]
        for item in recipe.items { for (key, value) in item.micros { micros[key, default: 0] += value } }
        var byGroup: [Processing: Double] = [:]
        for item in recipe.items { if let p = item.processing { byGroup[p, default: 0] += item.nutrients.kcal } }
        let processing = byGroup.max { $0.value < $1.value }?.key
        let fermented = recipe.items.contains { $0.fermented == true }
        let label = recipe.kind == .bowl ? "1 container" : "1 serving"
        return FoodEntry(
            date: date, name: recipe.title, amountLabel: label,
            grams: recipe.items.map(\.grams).reduce(0, +), nutrients: n, micros: micros, processing: processing,
            fermented: fermented, source: .plan)
    }
}
