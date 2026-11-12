import Foundation
import SystemCore
import Testing

@testable import MealPlanner

/// Prep day run step by step at the counter: what each step weighs and finishes, and what the
/// scale's readings do to the containers.
@Suite("Prep readings")
struct PrepReadingsTests {
    /// Two bowls sharing a pot of white rice, and breakfasts: a week with a shared batch.
    func sharedWeek() throws -> MealPlan {
        let teriyaki = try #require(MealPlanner.Bowl(id: "bowl:teriyaki:chicken-breast:rice-white:broccoli"))
        let peanut = try #require(MealPlanner.Bowl(id: "bowl:peanut:pork:rice-white:broccoli"))
        return planner.build(
            MealPlanner.Choices(bowls: [teriyaki, peanut]), id: UUID(), start: monday, targets: cut,
            preferences: PlanPreferences(), now: monday.date())
    }

    @Test("every step has a short label; what cooks by itself has a timer; batches say what to weigh and which dishes they finish")
    func steps() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: Set(MealSlot.allCases)))
        let guide = PrepGuide.make(for: plan)
        #expect(guide.steps.first?.label == "Oven on" && guide.steps.last?.label == "Store")
        #expect(guide.steps.contains { $0.label == "Box it up" })
        for step in guide.steps {
            #expect(!step.label.isEmpty && step.label.count <= 32, "\(step.label)")
            // A step that waits on the oven or a pot runs on a timer; the cook's own work doesn't.
            #expect((step.timer != nil) == !step.handsOn, "\(step.title)")
        }
        let pot = try #require(guide.steps.first { $0.title == "Cook the white rice" })
        #expect(pot.label == "Rice on" && pot.timer == PrepTimer(name: "White rice", place: "Hob, lid on"))
        let oven = try #require(guide.steps.first { $0.title.hasPrefix("Into the oven") })
        #expect(oven.timer?.place == "Oven, 220°C (425°F)" && oven.label.hasSuffix(" in"), "\(oven.label)")
        // Every dish made ahead is finished by some step, and what's made on the day by none.
        for recipe in plan.recipes {
            let finishing = guide.steps.filter { $0.dishes.contains(recipe.id) }
            #expect(finishing.isEmpty == recipe.madeOnTheDay, "\(recipe.title): \(finishing.map(\.title))")
        }
        // Weighing comes before the oven: a tray's raw weight on its prep step, not on the round.
        #expect(guide.steps.filter { $0.title.hasPrefix("Prep for the oven") }.allSatisfy { $0.weigh?.form == "raw" })
        #expect(guide.steps.filter { $0.title.hasPrefix("Into the oven") }.allSatisfy { $0.weigh == nil && !$0.dishes.isEmpty })
    }

    @Test("a shared pot weighs the dry grain for every dish it goes in, with water to match the reading")
    func sharedPot() throws {
        let plan = try sharedWeek()
        let guide = PrepGuide.make(for: plan)
        let rice = try #require(Library.ingredient("rice-white"))
        let pot = try #require(guide.steps.first { $0.title == "Cook the white rice" })
        let weigh = try #require(pot.weigh)
        let bowls = plan.recipes.filter { $0.kind == .bowl }
        let raw = bowls.compactMap { b in b.item("rice-white").map { $0.grams * Double(b.servings) / rice.yield } }.reduce(0, +)
        #expect(weigh.form == "dry" && abs(weigh.grams - raw) < 0.001)
        #expect(Set(weigh.dishes) == Set(bowls.map(\.id)) && Set(pot.dishes) == Set(bowls.map(\.id)))
        // The step's water is the reading's at the plan's amount, and follows the scale.
        #expect(pot.detail.contains("with \(weigh.water(for: weigh.grams) ?? 0) ml water"), "\(pot.detail)")
        #expect(weigh.water(for: 400) == 750 && weigh.water(for: 412) == 800)
        // A reading the batch couldn't be is a slip, not a reading.
        #expect(weigh.accepts(weigh.grams * 1.03) && weigh.accepts(weigh.grams / 4) && weigh.accepts(weigh.grams * 4))
        #expect(!weigh.accepts(weigh.grams * 10) && !weigh.accepts(weigh.grams / 5) && !weigh.accepts(0) && !weigh.accepts(.nan))
        // Counted things (cans) aren't weighed.
        #expect(guide.steps.allSatisfy { $0.weigh?.ingredientID != "canned-tomatoes" })
    }

    @Test("a reading over the plan spreads over every container the batch fills, and nothing else moves")
    func reportion() throws {
        let plan = try sharedWeek()
        let guide = PrepGuide.make(for: plan)
        let pot = try #require(guide.steps.first { $0.title == "Cook the white rice" })
        let planned = try #require(pot.weigh?.grams)
        let factor = 1.03
        let readings = PrepReadings(grams: [pot.id: planned * factor])
        let weighed = readings.apply(to: plan.recipes, guide: guide)
        #expect(weighed.map(\.id) == plan.recipes.map(\.id))
        for (before, after) in zip(plan.recipes, weighed) {
            guard let rice = before.item("rice-white") else {
                #expect(before == after, "\(before.title) has no rice")
                continue
            }
            let riced = try #require(after.item("rice-white"))
            #expect(abs(riced.grams - rice.grams * factor) < 0.001)
            #expect(abs(after.nutrients.kcal - (before.nutrients.kcal + rice.nutrients.kcal * 0.03)) < 0.001)
            #expect(abs(after.nutrients.protein - (before.nutrients.protein + rice.nutrients.protein * 0.03)) < 0.001)
            for (key, value) in rice.micros { #expect(abs((riced.micros[key] ?? 0) - value * factor) < 0.0001, "\(key)") }
            // The other parts are as planned.
            #expect(zip(before.items, after.items).filter { $0.0.ingredientID != "rice-white" }.allSatisfy { $0.0 == $0.1 })
        }
        // What the counter says for the reading: each dish's change a container, matching what's applied.
        let changes = readings.changes(for: pot, in: plan.recipes, guide: guide)
        #expect(changes.count == 2)
        for change in changes {
            let before = try #require(plan.recipe(change.recipeID))
            let after = try #require(weighed.first { $0.id == change.recipeID })
            #expect(change.servings == before.servings && change.kcal > 0)
            #expect(abs(change.kcal - (after.nutrients.kcal - before.nutrients.kcal)) < 0.001)
        }
    }

    @Test("readings come from the plan each time: at the plan's amount, cleared or changed twice")
    func idempotent() throws {
        let plan = try sharedWeek()
        let guide = PrepGuide.make(for: plan)
        let pot = try #require(guide.steps.first { $0.title == "Cook the white rice" })
        let prep = try #require(guide.steps.first { $0.title.hasPrefix("Prep for the oven") && $0.weigh != nil })
        let planned = try #require(pot.weigh?.grams)
        #expect(PrepReadings(grams: [pot.id: planned]).apply(to: plan.recipes, guide: guide) == plan.recipes)
        #expect(PrepReadings().apply(to: plan.recipes, guide: guide) == plan.recipes)
        #expect(PrepReadings(grams: [pot.id: 0]).apply(to: plan.recipes, guide: guide) == plan.recipes)
        #expect(PrepReadings(grams: [pot.id: 0]).changes(for: pot, in: plan.recipes, guide: guide).isEmpty)
        // Read, then corrected: the same as reading the correction once.
        var readings = PrepReadings(grams: [pot.id: planned + 40])
        _ = readings.apply(to: plan.recipes, guide: guide)
        readings.grams[pot.id] = planned - 20
        let corrected = readings.apply(to: plan.recipes, guide: guide)
        #expect(corrected == PrepReadings(grams: [pot.id: planned - 20]).apply(to: plan.recipes, guide: guide))
        // Two readings, two parts: under on one tray and over on the pot.
        let both = PrepReadings(grams: [pot.id: planned * 1.1, prep.id: (prep.weigh?.grams ?? 0) * 0.9])
            .apply(to: plan.recipes, guide: guide)
        let dish = try #require(prep.weigh?.dishes.first)
        let before = try #require(plan.recipe(dish))
        let after = try #require(both.first { $0.id == dish })
        let part = try #require(prep.weigh?.ingredientID)
        #expect(abs((after.item(part)?.grams ?? 0) - (before.item(part)?.grams ?? 0) * 0.9) < 0.001)
        #expect(abs((after.item("rice-white")?.grams ?? 0) - (before.item("rice-white")?.grams ?? 0) * 1.1) < 0.001)
    }
}
