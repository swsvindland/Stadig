import FoodDatabase
import Foundation
import SystemCore

/// Builds a week of meals from the library, sized to the targets, and swaps what the person
/// doesn't want. Deterministic: the same inputs give the same plan, and `variation` gives
/// another.
public struct MealPlanner: Sendable {
    let foods: [String: Food]

    /// Reads every building block's food from the catalog once.
    public init(catalog: FoodCatalog) {
        var foods: [String: Food] = [:]
        for ingredient in Library.ingredients {
            if let food = catalog.food(id: ingredient.foodID) { foods[ingredient.id] = food }
        }
        self.foods = foods
    }

    /// A bowl: protein, carb and a vegetable in a flavour.
    struct Bowl: Hashable {
        var profile: Profile
        var protein: Ingredient
        var carb: Ingredient
        var vegetable: Ingredient

        var id: String { "bowl:\(profile.id):\(protein.id):\(carb.id):\(vegetable.id)" }

        init(_ profile: Profile, _ protein: Ingredient, _ carb: Ingredient, _ vegetable: Ingredient) {
            self.profile = profile
            self.protein = protein
            self.carb = carb
            self.vegetable = vegetable
        }

        init?(id: String) {
            let parts = id.split(separator: ":").map(String.init)
            guard parts.count == 5, parts[0] == "bowl", let profile = Library.profile(parts[1]),
                let protein = Library.ingredient(parts[2]), let carb = Library.ingredient(parts[3]),
                let vegetable = Library.ingredient(parts[4])
            else { return nil }
            self.init(profile, protein, carb, vegetable)
        }

        var title: String { "\(profile.name) \(protein.short), \(carb.short) and \(vegetable.short)" }
    }

    /// What a week is made of, before it's sized.
    struct Choices {
        var bowls: [Bowl]
        var breakfast: Template?
        var snack: Template?
        /// The snack was picked (kept from a plan, or swapped to), rather than left to whichever
        /// fills the day best.
        var snackPinned = false
        /// Snacks not to fill with: the ones the week has had, when "other dishes" replaces them.
        var replacedSnacks: Set<String> = []
    }

    // MARK: Plans

    /// A week from `start`, prepped the day before. `recent` are recipe ids from last week, so
    /// the next week differs.
    public func plan(
        start: Day, targets: PlanTargets, preferences: PlanPreferences, recent: Set<String> = [], variation: Int = 0,
        now: Date = Date()
    ) -> MealPlan {
        let choices = choose(preferences: preferences, recent: recent, variation: variation)
        return build(choices, id: UUID(), start: start, targets: targets, preferences: preferences, now: now)
    }

    /// The same week with one recipe replaced by the next best that isn't already in it. Once the
    /// week has started, only the days from `now` on change.
    public func swap(_ recipeID: String, in plan: MealPlan, variation: Int = 1, now: Date = Date(), calendar: Calendar = .current) -> MealPlan {
        let today = Day(now, calendar: calendar)
        var choices = self.choices(of: plan, from: today)
        let used = Set(plan.recipes.map(\.id))
        if let index = choices.bowls.firstIndex(where: { $0.id == recipeID }) {
            let others = choices.bowls.enumerated().filter { $0.offset != index }.map(\.element)
            let ranked = rankedBowls(plan.preferences, recent: used, variation: variation)
            if let next = ranked.first(where: { candidate in candidate.id != recipeID && others.allSatisfy { differs(candidate, $0) } })
                ?? ranked.first(where: { $0.id != recipeID && !used.contains($0.id) })
            {
                choices.bowls[index] = next
            }
        } else if choices.breakfast.map({ "template:\($0.id)" }) == recipeID {
            choices.breakfast = nextTemplate(after: choices.breakfast, slot: .breakfast, preferences: plan.preferences)
        } else if choices.snack.map({ "template:\($0.id)" }) == recipeID {
            choices.snack = nextTemplate(after: choices.snack, slot: .snack, preferences: plan.preferences)
            choices.snackPinned = true
        }
        let next = build(choices, id: plan.id, start: plan.start, targets: plan.targets, preferences: plan.preferences, now: now)
        return keepingEaten(plan, in: next, today: today)
    }

    /// The dishes that can still be swapped, in the plan's order: those served at a meal from
    /// `today` on that isn't logged. The others stay on the days they were eaten.
    public func swappable(_ plan: MealPlan, today: Day) -> [String] {
        let upcoming = Set(plan.meals.filter { $0.day >= today && plan.logged[$0.id] == nil }.map(\.recipeID))
        return plan.recipes.map(\.id).filter(upcoming.contains)
    }

    /// The same preferences, other dishes: every dish still to come is replaced, and the plan keeps
    /// its id, and the days already eaten and the meals logged keep theirs, as with a swap. The plan
    /// as it is when nothing is left to change.
    public func shuffle(_ plan: MealPlan, variation: Int, now: Date = Date(), calendar: Calendar = .current) -> MealPlan {
        let today = Day(now, calendar: calendar)
        guard !swappable(plan, today: today).isEmpty else { return plan }
        var choices = self.choices(of: plan, from: today)
        // Not one of the week's dishes, nor one just picked, so a dish doesn't come back in the
        // other slot: swapping one bowl at a time would hand the second the first's old dish.
        var used = Set(plan.recipes.map(\.id))
        let ranked = rankedBowls(plan.preferences, recent: used, variation: variation)
        var picked: [Bowl] = []
        for index in choices.bowls.indices {
            if let next = ranked.first(where: { candidate in !used.contains(candidate.id) && picked.allSatisfy { differs(candidate, $0) } })
                ?? ranked.first(where: { !used.contains($0.id) })
            {
                choices.bowls[index] = next
                used.insert(next.id)
            }
            picked.append(choices.bowls[index])
        }
        // Nor, while there's another, a breakfast or snack the week has had: one kept only for the
        // days already eaten would otherwise come back on a second shuffle.
        let templates = Set(plan.recipes.compactMap(\.templateID))
        if let breakfast = choices.breakfast {
            choices.breakfast = nextTemplate(after: breakfast, slot: .breakfast, preferences: plan.preferences, avoiding: templates)
        }
        if let snack = choices.snack {
            // Whichever other snack fills the new week best, as in a new plan: the next one in line
            // can leave the day well short of its protein.
            let next = nextTemplate(after: snack, slot: .snack, preferences: plan.preferences, avoiding: templates)
            let fresh = next.map { !templates.contains($0.id) } ?? false
            choices.snack = next
            choices.snackPinned = false
            choices.replacedSnacks = fresh ? templates : [snack.id]
        }
        let next = build(choices, id: plan.id, start: plan.start, targets: plan.targets, preferences: plan.preferences, now: now)
        return keepingEaten(plan, in: next, today: today)
    }

    /// The week again with new preferences: what still fits stays, the rest is chosen afresh.
    /// Once the week has started, only the days from `now` on change.
    public func replan(
        _ plan: MealPlan, preferences: PlanPreferences, targets: PlanTargets? = nil, variation: Int = 0,
        now: Date = Date(), calendar: Calendar = .current
    ) -> MealPlan {
        let today = Day(now, calendar: calendar)
        let kept = choices(of: plan, from: today)
        var choices = choose(preferences: preferences, recent: [], variation: variation)
        // Keep a bowl that still fits and isn't now outranked by something asked for.
        if preferences.want.isEmpty {
            for (i, bowl) in kept.bowls.enumerated() where i < choices.bowls.count && allows(bowl, preferences) {
                if choices.bowls.enumerated().allSatisfy({ $0.offset == i || differs(bowl, $0.element) }) { choices.bowls[i] = bowl }
            }
        }
        let next = build(choices, id: plan.id, start: plan.start, targets: targets ?? plan.targets, preferences: preferences, now: now)
        return keepingEaten(plan, in: next, today: today)
    }

    /// The rebuilt week with what's already happened left alone: meals on days before `today`, and
    /// meals already logged, keep the dish they were (and its recipe), so a change mid-week doesn't
    /// rewrite what was eaten or tick a dish that wasn't.
    func keepingEaten(_ old: MealPlan, in rebuilt: MealPlan, today: Day) -> MealPlan {
        var next = rebuilt
        next.logged = old.logged
        next.checked = old.checked
        next.createdAt = old.createdAt
        let kept = old.meals.filter { $0.day < today || old.logged[$0.id] != nil }
        guard !kept.isEmpty else { return next }
        let keptIDs = Set(kept.map(\.id))
        next.meals = (kept + rebuilt.meals.filter { !keptIDs.contains($0.id) })
            .sorted { $0.day != $1.day ? $0.day < $1.day : $0.slot < $1.slot }
        // The rebuilt dishes first, so the week's current choices read first; then the old ones
        // still eaten on the kept days.
        var recipes = rebuilt.recipes + old.recipes.filter { rebuilt.recipe($0.id) == nil }
        for i in recipes.indices { recipes[i].servings = next.meals.filter { $0.recipeID == recipes[i].id }.count }
        next.recipes = recipes.filter { $0.servings > 0 }
        return next
    }

    // MARK: Choosing

    func choose(preferences: PlanPreferences, recent: Set<String>, variation: Int) -> Choices {
        let bowlSlots = preferences.slots.intersection([.lunch, .dinner]).count
        var bowls: [Bowl] = []
        if bowlSlots > 0 {
            let ranked = rankedBowls(preferences, recent: recent, variation: variation)
            if let first = ranked.first {
                bowls.append(first)
                // A second for variety, unless one dish was asked for: another protein and another
                // flavour, else at least another protein.
                if !preferences.oneDish,
                    let second = ranked.first(where: { differs($0, first) }) ?? ranked.first(where: { $0.protein.id != first.protein.id })
                {
                    bowls.append(second)
                }
            }
        }
        let breakfast =
            preferences.slots.contains(.breakfast)
            ? rankedTemplates(.breakfast, preferences, variation: variation).first : nil
        let snack = preferences.slots.contains(.snack) ? rankedTemplates(.snack, preferences, variation: variation).first : nil
        return Choices(bowls: bowls, breakfast: breakfast, snack: snack)
    }

    /// Two bowls that don't feel like the same meal: another protein and another flavour.
    func differs(_ a: Bowl, _ b: Bowl) -> Bool { a.protein.id != b.protein.id && a.profile.id != b.profile.id }

    func allows(_ bowl: Bowl, _ preferences: PlanPreferences) -> Bool {
        [bowl.protein, bowl.carb, bowl.vegetable].allSatisfy(preferences.allows)
            // Cheese on top can be left off; the sauce itself can't.
            && bowl.profile.sauce.allSatisfy { part in
                Library.ingredient(part.id).map { preferences.allows($0) || $0.role == .dairy } ?? false
            }
            && foods[bowl.protein.id] != nil && foods[bowl.carb.id] != nil && foods[bowl.vegetable.id] != nil
            && !preferences.avoid.contains(bowl.profile.id)
    }

    /// Every bowl the preferences allow, best first.
    func rankedBowls(_ preferences: PlanPreferences, recent: Set<String>, variation: Int) -> [Bowl] {
        var bowls: [(Bowl, Double)] = []
        for profile in Library.profiles {
            for protein in profile.proteins.compactMap(Library.ingredient) {
                for carb in profile.carbs.compactMap(Library.ingredient) {
                    for vegetable in profile.vegetables.compactMap(Library.ingredient) {
                        let bowl = Bowl(profile, protein, carb, vegetable)
                        guard allows(bowl, preferences) else { continue }
                        bowls.append((bowl, score(bowl, preferences, recent: recent, variation: variation)))
                    }
                }
            }
        }
        return bowls.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }.map(\.0)
    }

    func score(_ bowl: Bowl, _ preferences: PlanPreferences, recent: Set<String>, variation: Int) -> Double {
        let parts = [bowl.protein, bowl.carb, bowl.vegetable]
        var score = bowl.protein.everyday * 2 + bowl.carb.everyday + bowl.vegetable.everyday
        // Asked for by name: the protein or flavour most of all.
        for part in parts where preferences.want.contains(part.id) { score += part.role == .protein ? 4 : 2.5 }
        if preferences.want.contains(bowl.profile.id) { score += 3 }
        // Food quality: whole grains and beans for fibre, and a fermented topping.
        if ["rice-brown", "quinoa", "pasta", "sweet-potato", "black-beans"].contains(bowl.carb.id) { score += 0.35 }
        if let topping = bowl.profile.topping, Library.ingredient(topping.id).flatMap({ foods[$0.id]?.fermented }) == true { score += 0.3 }
        if preferences.cheaper { score += Double(3 - parts.map(\.cost).max()!) * 0.9 }
        if preferences.quicker { score -= Double(parts.map(minutes).max()!) / 15 }
        if recent.contains(bowl.id) { score -= 3 }
        if recent.contains(where: { $0.hasPrefix("bowl:\(bowl.profile.id):\(bowl.protein.id):") }) { score -= 1 }
        if variation > 0 { score += 2.5 * jitter(bowl.id, variation) }
        return score
    }

    func minutes(_ ingredient: Ingredient) -> Int {
        switch ingredient.cooking {
        case .roast(let m), .simmer(let m, _), .boil(let m), .pan(let m), .bake(let m): m
        case .none: 0
        }
    }

    /// The breakfasts or snacks the preferences allow, best first. Ones made ahead come first for
    /// breakfast; for snacks, the protein-rich ones.
    func rankedTemplates(_ slot: MealSlot, _ preferences: PlanPreferences, variation: Int) -> [Template] {
        let order: [String] =
            slot == .breakfast
            ? ["overnight-oats", "egg-muffins", "yogurt-bowl"]
            : ["kefir-banana", "yogurt-berries", "eggs-orange", "cottage-pineapple", "apple-almonds"]
        let allowed = Library.templates.filter { $0.slot == slot && usable($0, preferences) }
        return allowed.sorted { a, b in
            func rank(_ t: Template) -> Double {
                var r = Double(order.firstIndex(of: t.id) ?? order.count)
                if preferences.want.contains(t.id) || t.parts.contains(where: { preferences.want.contains($0.id) }) { r -= 10 }
                if variation > 0 { r -= 3 * jitter(t.id, variation) }
                return r
            }
            return rank(a) != rank(b) ? rank(a) < rank(b) : a.id < b.id
        }
    }

    /// A template whose required parts all fit (an optional part, with a range from zero, is dropped).
    func usable(_ template: Template, _ preferences: PlanPreferences) -> Bool {
        template.parts.allSatisfy { part in
            guard let ingredient = Library.ingredient(part.id), foods[part.id] != nil else { return part.grams.lowerBound == 0 }
            return preferences.allows(ingredient) || part.grams.lowerBound == 0
        } && !preferences.avoid.contains(template.id)
    }

    func nextTemplate(after current: Template?, slot: MealSlot, preferences: PlanPreferences) -> Template? {
        let ranked = rankedTemplates(slot, preferences, variation: 0)
        guard let current, let index = ranked.firstIndex(of: current) else { return ranked.first }
        return ranked[(index + 1) % ranked.count]
    }

    /// The next in line after `current` that isn't one of `avoiding`, else just the next in line.
    func nextTemplate(after current: Template, slot: MealSlot, preferences: PlanPreferences, avoiding: Set<String>) -> Template? {
        let ranked = rankedTemplates(slot, preferences, variation: 0)
        let start = ranked.firstIndex(of: current).map { $0 + 1 } ?? 0
        let inLine = ranked.indices.map { ranked[(start + $0) % ranked.count] }
        return inLine.first { !avoiding.contains($0.id) } ?? nextTemplate(after: current, slot: slot, preferences: preferences)
    }

    /// A stable 0–1 number for a key and a variation, so "another plan" is repeatable.
    func jitter(_ key: String, _ variation: Int) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(key)#\(variation)".utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return Double(hash % 10_000) / 10_000
    }

    /// What the plan is made of from `today` on: the dishes still to come, not ones kept only for
    /// days already eaten. A week that's over, or not started, is all of its dishes.
    func choices(of plan: MealPlan, from today: Day) -> Choices {
        let upcoming = Set(plan.meals.filter { $0.day >= today && plan.logged[$0.id] == nil }.map(\.recipeID))
        let recipes = plan.recipes.filter { upcoming.isEmpty || upcoming.contains($0.id) }
        return Choices(
            bowls: recipes.filter { $0.kind == .bowl }.compactMap { Bowl(id: $0.id) },
            breakfast: recipes.first { $0.slots.contains(.breakfast) }?.templateID.flatMap(Library.template),
            snack: recipes.first { $0.slots.contains(.snack) }?.templateID.flatMap(Library.template), snackPinned: true)
    }

    // MARK: Sizing

    func build(_ choices: Choices, id: UUID, start: Day, targets: PlanTargets, preferences: PlanPreferences, now: Date) -> MealPlan {
        let days = (0..<MealPlan.length).map { start.adding(days: $0) }
        var recipes: [PlannedRecipe] = []
        var meals: [PlannedMeal] = []

        // Lunch and dinner: the bowls, alternating so the same dish isn't eaten twice a day, unless
        // there's one.
        let bowlSlots = [MealSlot.lunch, .dinner].filter(preferences.slots.contains)
        var bowlRecipes = choices.bowls.map { bowl(for: $0, target: targets.scaled(MealSlot.lunch.share), preferences: preferences) }
        if !bowlRecipes.isEmpty {
            var servings = Array(repeating: 0, count: bowlRecipes.count)
            for (d, day) in days.enumerated() {
                for (s, slot) in bowlSlots.enumerated() {
                    let r = (d + s) % bowlRecipes.count
                    // How long it keeps counts from prep day, whichever serving it is.
                    meals.append(
                        PlannedMeal(
                            day: day, slot: slot, recipeID: bowlRecipes[r].id,
                            storage: storage(day: d, keeps: bowlRecipes[r].keeps, freezes: true)))
                    servings[r] += 1
                }
            }
            for i in bowlRecipes.indices {
                bowlRecipes[i].servings = servings[i]
                bowlRecipes[i].slots = bowlSlots
            }
            recipes += bowlRecipes.filter { $0.servings > 0 }
        }

        if let template = choices.breakfast {
            let recipe = make(template, target: targets.scaled(MealSlot.breakfast.share), preferences: preferences, servings: days.count)
            recipes.append(recipe)
            for (d, day) in days.enumerated() {
                meals.append(
                    PlannedMeal(
                        day: day, slot: .breakfast, recipeID: recipe.id,
                        storage: storage(day: d, keeps: recipe.keeps, freezes: recipe.freezes)))
            }
        }

        // The snack fills what the other meals leave, keeping room for the meals left to the person.
        if let template = choices.snack {
            let planned = recipes.map { r in r.nutrients.scaled(Double(meals.filter { $0.recipeID == r.id }.count) / Double(days.count)) }
                .reduce(.zero, +)
            let open = MealSlot.allCases.filter { !preferences.slots.contains($0) }.map(\.share).reduce(0, +)
            let room = targets - planned - targets.scaled(open).nutrients
            let target = PlanTargets(
                kcal: max(room.kcal, targets.kcal * 0.07), protein: max(room.protein, 5), carbs: room.carbs,
                fat: room.fat)
            // Whichever snack fills the gap best, protein first, unless one was picked; something
            // fermented when the day has nothing else that is.
            let fermented = recipes.contains { $0.items.contains { $0.fermented == true } }
            var candidates = [template]
            if !choices.snackPinned {
                candidates += rankedTemplates(.snack, preferences, variation: 0).filter { $0 != template && !choices.replacedSnacks.contains($0.id) }
            }
            let sized = candidates.enumerated().map { i, t -> (PlannedRecipe, Double) in
                let r = make(t, target: target, preferences: preferences, servings: days.count)
                let n = r.nutrients
                func miss(_ got: Double, _ want: Double, _ floor: Double) -> Double { pow((got - want) / max(want, floor), 2) }
                var score =
                    4 * miss(n.kcal, target.kcal, 50) + 4 * miss(n.protein, target.protein, 5) + miss(n.carbs, target.carbs, 5)
                    + miss(n.fat, target.fat, 5) + 0.03 * Double(i)
                if !fermented, r.items.contains(where: { $0.fermented == true }) { score -= 0.05 }
                return (r, score)
            }
            let recipe = sized.min { $0.1 < $1.1 }!.0
            recipes.append(recipe)
            for (d, day) in days.enumerated() {
                meals.append(
                    PlannedMeal(
                        day: day, slot: .snack, recipeID: recipe.id,
                        storage: storage(day: d, keeps: recipe.keeps, freezes: recipe.freezes)))
            }
        }

        return MealPlan(
            id: id, start: start, preferences: preferences, targets: targets, recipes: recipes,
            meals: meals.sorted { $0.day != $1.day ? $0.day < $1.day : $0.slot < $1.slot }, checked: [], logged: [:],
            createdAt: now, updatedAt: now)
    }

    /// Where a serving waits: the fridge for the first days, then the freezer, or made on the day.
    func storage(day: Int, keeps: Int, freezes: Bool) -> PlannedMeal.Storage {
        if keeps == 0 { return .onTheDay }
        if day < keeps { return .fridge }
        return freezes ? .freezer : .onTheDay
    }

    /// A bowl sized to its share: protein, carb, vegetable and oil solved; sauce and topping fixed.
    func bowl(for bowl: Bowl, target: PlanTargets, preferences: PlanPreferences) -> PlannedRecipe {
        // A topping or cheese the diet rules out is left off.
        let fixedParts = (bowl.profile.sauce.map { ($0.id, $0.grams, false) } + (bowl.profile.topping.map { [($0.id, $0.grams, true)] } ?? []))
            .filter { id, _, _ in Library.ingredient(id).map(preferences.allows) ?? false }
        let fixed = fixedParts.compactMap { id, grams, _ in foods[id].map { $0.nutrients(for: grams) } }.reduce(.zero, +)
        let scaled = [bowl.protein, bowl.carb, bowl.vegetable, Library.ingredient("olive-oil")!]
        let grams = solve(scaled.map { ($0, $0.range, $0.typical) }, target: target, fixed: fixed)
        var items = zip(scaled, grams).compactMap { item($0, grams: $1, onTheDay: false) }
        items += fixedParts.compactMap { id, grams, onTheDay in Library.ingredient(id).flatMap { item($0, grams: grams, onTheDay: onTheDay) } }
        return PlannedRecipe(
            id: bowl.id, kind: .bowl, title: bowl.title, slots: [.lunch, .dinner], items: items, servings: 0,
            keeps: 3, freezes: true, profileID: bowl.profile.id, templateID: nil)
    }

    /// A breakfast or snack sized to its target, leaving out optional parts the diet rules out.
    func make(_ template: Template, target: PlanTargets, preferences: PlanPreferences, servings: Int) -> PlannedRecipe {
        let parts = template.parts.compactMap { part -> (Ingredient, ClosedRange<Double>, Double)? in
            guard let ingredient = Library.ingredient(part.id), foods[part.id] != nil, preferences.allows(ingredient) else { return nil }
            return (ingredient, part.grams, part.typical)
        }
        let grams = solve(parts, target: target, fixed: .zero)
        // Fruit with a breakfast made ahead is eaten fresh.
        let items = zip(parts, grams).compactMap { part, g in
            item(part.0, grams: g, onTheDay: template.keeps > 0 && part.0.role == .fruit && template.id == "egg-muffins")
        }
        return PlannedRecipe(
            id: "template:\(template.id)", kind: .template, title: template.name, slots: [template.slot],
            items: items, servings: servings, keeps: template.keeps, freezes: template.freezes, profileID: nil,
            templateID: template.id)
    }

    func solve(_ parts: [(Ingredient, ClosedRange<Double>, Double)], target: PlanTargets, fixed: Nutrients) -> [Double] {
        let solverParts = parts.map { ingredient, range, typical in
            let n = foods[ingredient.id]?.nutrients(for: 1) ?? .zero
            return PortionSolver.Part(perGram: [n.kcal, n.protein, n.carbs, n.fat], range: range, typical: typical)
        }
        return PortionSolver.solve(solverParts, target: target, fixed: [fixed.kcal, fixed.protein, fixed.carbs, fixed.fat])
            .map(PortionSolver.round)
    }

    func item(_ ingredient: Ingredient, grams: Double, onTheDay: Bool) -> PlannedItem? {
        guard grams > 0, let food = foods[ingredient.id] else { return nil }
        return PlannedItem(
            ingredientID: ingredient.id, foodID: food.id, name: ingredient.name, grams: grams,
            nutrients: food.nutrients(for: grams), micros: food.extras(for: grams), processing: food.processing,
            fermented: food.fermented, onTheDay: onTheDay)
    }
}

extension PlanTargets {
    var nutrients: Nutrients { Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}
