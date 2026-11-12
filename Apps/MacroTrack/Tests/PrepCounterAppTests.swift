import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// Counter mode on prep day: the run that carries on when it's closed and opened again, its timers
/// and the containers filling, and the scale's readings reaching what's logged from the plan.
@MainActor
struct PrepCounterAppTests {
    func plan(_ model: AppModel) -> MealPlan {
        SampleData.seedIfEmpty(model)
        // Being eaten from since yesterday: today's meals can be logged.
        return model.makeMealPlan(preferences: PlanPreferences(slots: Set(MealSlot.allCases)), start: model.today.adding(days: -1))
    }

    @Test func closedAndOpenedAgainItCarriesOn() throws {
        let model = TestEnvironment().model()
        let plan = plan(model)
        model.startPrep(plan)
        let run = try #require(model.prepRun)
        #expect(model.showPrepCounter && run.planID == plan.id && run.index == 0)
        run.advance(at: Date())
        model.showPrepCounter = false
        model.startPrep(plan)
        #expect(model.prepRun === run && run.index == 1, "the same run, where it was")

        // Another week's plan is another run.
        let next = model.makeMealPlan(preferences: PlanPreferences(slots: [.dinner]), start: plan.end.adding(days: 1))
        model.startPrep(next)
        #expect(model.prepRun !== run && model.prepRun?.planID == next.id)
        model.finishPrep()
        #expect(model.prepRun == nil && !model.showPrepCounter)
    }

    @Test func aPotsTimerRunsFromItsNextAndBackTakesItOff() throws {
        let model = TestEnvironment().model()
        model.startPrep(plan(model))
        let run = try #require(model.prepRun)
        let pot = try #require(run.guide.steps.firstIndex { $0.timer != nil && $0.weigh != nil })
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        while run.index < pot { run.advance(at: start) }
        let step = run.step
        #expect(run.timers.allSatisfy { $0.id != step.id }, "not on until it's done")
        run.advance(at: start)
        let timer = try #require(run.timers.first { $0.id == step.id })
        #expect(timer.ends == start.addingTimeInterval(TimeInterval(step.minutes * 60)) && timer.name == step.timer?.name)
        #expect(run.nextAlarm?.id == run.timers.first?.id)
        // Its dishes have a part in.
        for dish in step.dishes { #expect(run.parts(of: dish).done >= 1) }

        run.back()
        #expect(run.step == step && run.timers.allSatisfy { $0.id != step.id }, "back a step: the pot's off again")
        run.advance(at: start)
        run.ring(step.id)
        run.clear(step.id)
        #expect(run.timers.allSatisfy { $0.id != step.id } && run.nextAlarm?.id != step.id)
    }

    @Test func theScalesReadingsReachTheContainersLoggedFromThePlan() throws {
        let model = TestEnvironment().model()
        let plan = plan(model)
        model.startPrep(plan)
        let run = try #require(model.prepRun)
        let step = try #require(run.guide.steps.first { $0.weigh != nil })
        let weigh = try #require(step.weigh)
        let dish = try #require(weigh.dishes.first)
        let planned = try #require(plan.recipe(dish))
        #expect(run.reading(for: step) == weigh.grams.rounded(), "the recipe's amount until it's set")

        // A slip of the finger isn't a reading.
        run.read(weigh.grams * 10, for: step)
        #expect(run.weighed == run.planned)

        run.read(weigh.grams * 1.1, for: step)
        let change = try #require(run.changes(for: step).first { $0.recipeID == dish })
        #expect(change.kcal > 0)
        model.saveReadings(run)
        let saved = try #require(model.mealPlans.first { $0.id == plan.id }?.recipe(dish))
        let item = try #require(saved.item(weigh.ingredientID))
        let factor = (weigh.grams * 1.1).rounded() / weigh.grams
        #expect(abs(item.grams - (planned.item(weigh.ingredientID)?.grams ?? 0) * factor) < 0.01)
        #expect(abs(saved.nutrients.kcal - planned.nutrients.kcal - change.kcal) < 0.01)

        // A container logged from the plan is what was cooked.
        model.finishPrep()
        let meal = try #require(plan.meals.first { $0.recipeID == dish && $0.day == model.today })
        let current = try #require(model.mealPlans.first { $0.id == plan.id })
        model.logPlanned(meal, in: current)
        #expect(abs((model.allEntries(on: meal.day).last?.nutrients.kcal ?? 0) - saved.nutrients.kcal) < 0.01)
    }

    @Test func aReadingSetBackToTheRecipeLeavesThePlanAsItWas() throws {
        let model = TestEnvironment().model()
        let plan = plan(model)
        model.startPrep(plan)
        let run = try #require(model.prepRun)
        let step = try #require(run.guide.steps.first { $0.weigh != nil })
        let weigh = try #require(step.weigh)
        run.read(weigh.grams * 0.9, for: step)
        model.saveReadings(run)
        #expect(model.mealPlans.first { $0.id == plan.id }?.recipes != plan.recipes)
        run.read(weigh.grams, for: step)
        model.saveReadings(run)
        #expect(model.mealPlans.first { $0.id == plan.id }?.recipes == plan.recipes)
    }

    @Test func aDishReplannedDuringPrepKeepsItsNewAmounts() throws {
        let model = TestEnvironment().model()
        let plan = plan(model)
        model.startPrep(plan)
        let run = try #require(model.prepRun)
        let step = try #require(run.guide.steps.first { $0.weigh != nil })
        let weigh = try #require(step.weigh)
        let dish = try #require(weigh.dishes.first)
        // The plan changes under the run: the same dish, other amounts.
        var changed = try #require(model.mealPlans.first { $0.id == plan.id })
        let index = try #require(changed.recipes.firstIndex { $0.id == dish })
        changed.recipes[index].servings += 1
        model.store.save(changed)
        model.reloadMealPlans()
        run.read(weigh.grams * 1.1, for: step)
        model.saveReadings(run)
        #expect(model.mealPlans.first { $0.id == plan.id }?.recipe(dish) == changed.recipes[index], "not overwritten from the run's copy")
    }
}
