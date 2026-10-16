import Foundation
import Testing
import FoodDatabase
import NutritionEngine
import SystemCore
@testable import MealPlanner

/// The bundled USDA catalog, read once.
let planner = MealPlanner(catalog: FoodCatalog.standard(region: "us"))
/// A Monday, prepped the Sunday before.
let monday = Day(year: 2026, month: 10, day: 19)
/// A lifter cutting at 2,300 kcal.
let cut = PlanTargets(kcal: 2300, protein: 180, carbs: 230, fat: 70)

@Suite("Meal planner")
struct MealPlannerTests {
    @Test("every building block is a catalog food of the kind it says")
    func library() throws {
        let catalog = FoodCatalog.standard(region: "us")
        for ingredient in Library.ingredients {
            let food = try #require(catalog.food(id: ingredient.foodID), "\(ingredient.id)")
            #expect(food.processing != .ultraProcessed, "\(ingredient.id): \(food.name)")
            if ingredient.role == .protein, ingredient.id != "eggs", ingredient.id != "boiled-eggs" {
                #expect(food.nutrients.protein >= 8, "\(ingredient.id) is a protein")
            }
        }
        for profile in Library.profiles {
            for id in profile.proteins.union(profile.carbs).union(profile.vegetables).union(profile.sauce.map(\.id)) {
                #expect(Library.ingredient(id) != nil, "\(profile.id): \(id)")
            }
        }
        for template in Library.templates { for part in template.parts { #expect(Library.ingredient(part.id) != nil, "\(template.id): \(part.id)") } }
    }

    @Test("a full week hits the day's calories and protein")
    func fullWeek() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: Set(MealSlot.allCases)))
        #expect(plan.prepDay == monday.adding(days: -1) && plan.days.count == 7)
        #expect(plan.meals.count == 28)
        for day in plan.days {
            let n = plan.planned(on: day)
            #expect(abs(n.kcal - cut.kcal) / cut.kcal < 0.08, "\(day): \(Int(n.kcal)) kcal")
            #expect(n.protein >= cut.protein * 0.9, "\(day): \(Int(n.protein)) g protein")
            #expect(plan.unplanned(on: day).isEmpty)
        }
        // Two bowls for variety: another protein and another flavour, seven of each.
        let bowls = plan.recipes.filter { $0.kind == .bowl }
        #expect(bowls.count == 2 && bowls.allSatisfy { $0.servings == 7 })
        #expect(Set(bowls.compactMap(\.profileID)).count == 2)
        #expect(bowls[0].items.first?.ingredientID != bowls[1].items.first?.ingredientID)
        // Never the same bowl twice in a day.
        for day in plan.days {
            let ids = plan.meals(on: day).filter { $0.slot == .lunch || $0.slot == .dinner }.map(\.recipeID)
            #expect(Set(ids).count == 2)
        }
    }

    @Test("only the meals asked for are prepped; the rest keep room in the targets")
    func someMeals() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: [.lunch]))
        #expect(plan.meals.count == 7 && plan.meals.allSatisfy { $0.slot == .lunch })
        // Two lunches alternate: four of one, three of the other.
        #expect(plan.recipes.map(\.servings).sorted() == [3, 4])
        let open = plan.unplanned(on: monday)
        #expect(open.map(\.slot) == [.breakfast, .snack, .dinner])
        let room = open.map(\.room.kcal).reduce(0, +) + plan.planned(on: monday).kcal
        #expect(abs(room - cut.kcal) < 1, "what's planned and what's left add up to the day")
        let lunch = plan.planned(on: monday)
        #expect(abs(lunch.kcal - cut.kcal * 0.3) / (cut.kcal * 0.3) < 0.1, "\(Int(lunch.kcal)) kcal")
    }

    @Test("cooked food spends three days in the fridge, then the freezer")
    func storage() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: [.breakfast, .lunch, .dinner]))
        let lunches = plan.meals.filter { $0.slot == .lunch }
        let byRecipe = Dictionary(grouping: plan.meals.filter { $0.slot != .breakfast }, by: \.recipeID)
        for (_, meals) in byRecipe {
            let sorted = meals.sorted { $0.day < $1.day }
            #expect(sorted.prefix(3).allSatisfy { $0.storage == .fridge })
            #expect(sorted.dropFirst(3).allSatisfy { $0.storage == .freezer })
        }
        #expect(lunches.first?.storage == .fridge && lunches.last?.storage == .freezer)
        // Lunches only: what's kept counts from prep day, not from how many came before.
        let lunches2 = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: [.lunch])).meals
        #expect(lunches2.allSatisfy { ($0.storage == .fridge) == ($0.day < monday.adding(days: 3)) })
        // Overnight oats keep four days, and freeze.
        let breakfasts = plan.meals.filter { $0.slot == .breakfast }
        #expect(breakfasts.prefix(4).allSatisfy { $0.storage == .fridge } && breakfasts.last?.storage == .freezer)
    }

    @Test("diets and dislikes leave foods out")
    func diets() throws {
        let vegetarian = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: Set(MealSlot.allCases), diet: .vegetarian))
        let meat: FoodTags = [.meat, .poultry, .pork, .fish, .shellfish]
        for recipe in vegetarian.recipes {
            for item in recipe.items { #expect(Library.ingredient(item.ingredientID)!.tags.isDisjoint(with: meat), "\(item.name)") }
        }
        #expect(vegetarian.recipes.filter { $0.kind == .bowl }.count == 2)

        let noFishOrDairy = planner.plan(start: monday, targets: cut,
                                         preferences: PlanPreferences(slots: Set(MealSlot.allCases), avoid: ["fish", "dairy", "chicken-breast"]))
        for recipe in noFishOrDairy.recipes {
            for item in recipe.items {
                let ingredient = Library.ingredient(item.ingredientID)!
                #expect(ingredient.tags.isDisjoint(with: [.fish, .dairy]) && ingredient.id != "chicken-breast", "\(recipe.title): \(item.name)")
            }
        }
        // Breakfast without dairy is egg muffins, without their feta.
        #expect(noFishOrDairy.recipes.first { $0.slots == [.breakfast] }?.templateID == "egg-muffins")
    }

    @Test("asking for something puts it in the plan")
    func wants() throws {
        let salmon = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(want: ["salmon"]))
        #expect(salmon.recipes.contains { $0.id.contains(":salmon:") })
        let curry = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(want: ["curry"]))
        #expect(curry.recipes.contains { $0.profileID == "curry" })
        let cheap = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(cheaper: true))
        for recipe in cheap.recipes { #expect(recipe.items.compactMap { Library.ingredient($0.ingredientID) }.allSatisfy { $0.cost <= 2 }) }
    }

    @Test("next week differs from this one, and a swap changes only that dish")
    func variety() throws {
        let preferences = PlanPreferences(slots: [.breakfast, .lunch, .dinner, .snack])
        let week1 = planner.plan(start: monday, targets: cut, preferences: preferences)
        let week2 = planner.plan(start: monday.adding(days: 7), targets: cut, preferences: preferences, recent: Set(week1.recipes.map(\.id)))
        let bowls1 = Set(week1.recipes.filter { $0.kind == .bowl }.map(\.id))
        let bowls2 = Set(week2.recipes.filter { $0.kind == .bowl }.map(\.id))
        #expect(bowls1.isDisjoint(with: bowls2))
        #expect(planner.plan(start: monday, targets: cut, preferences: preferences).recipes.map(\.id) == week1.recipes.map(\.id),
                "the same inputs give the same plan")

        let first = try #require(week1.recipes.first { $0.kind == .bowl })
        let swapped = planner.swap(first.id, in: week1)
        #expect(swapped.recipe(first.id) == nil)
        #expect(swapped.recipes.filter { $0.kind == .bowl }.count == 2)
        let other = week1.recipes.filter { $0.kind == .bowl }[1]
        #expect(swapped.recipe(other.id) != nil, "the other bowl stays")
        #expect(swapped.id == week1.id && swapped.meals.count == week1.meals.count)

        let breakfast = try #require(week1.recipes.first { $0.slots == [.breakfast] })
        let newBreakfast = planner.swap(breakfast.id, in: week1)
        #expect(newBreakfast.recipe(breakfast.id) == nil && newBreakfast.recipes.contains { $0.slots == [.breakfast] })
    }

    @Test("the week's food is whole, with fibre and something fermented")
    func quality() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: Set(MealSlot.allCases)))
        let items = plan.recipes.flatMap { recipe in recipe.items.map { ($0, Double(recipe.servings)) } }
        let kcal = items.map { $0.0.nutrients.kcal * $0.1 }.reduce(0, +)
        let ultra = items.filter { $0.0.processing == .ultraProcessed }.map { $0.0.nutrients.kcal * $0.1 }.reduce(0, +)
        #expect(ultra / kcal < 0.05)
        let fiber = plan.planned(on: monday).fiber ?? 0
        #expect(fiber >= 25, "\(Int(fiber)) g fibre")
        #expect(plan.meals(on: monday).contains { meal in plan.recipe(meal.recipeID)!.items.contains { $0.fermented == true } })
    }

    @Test("the grocery list buys raw and dry amounts, in the units things are sold in")
    func groceries() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: Set(MealSlot.allCases)))
        let list = Groceries.list(for: plan)
        for recipe in plan.recipes where recipe.kind == .bowl {
            let protein = try #require(recipe.items.first { Library.ingredient($0.ingredientID)?.role == .protein })
            let ingredient = Library.ingredient(protein.ingredientID)!
            let line = try #require(list.first { $0.name == ingredient.name })
            let raw = protein.grams * 7 / ingredient.yield
            #expect(line.grams >= raw && line.grams < raw + 60, "\(line.name): \(line.grams) g for \(raw) g")
        }
        #expect(list.contains { $0.pantry && $0.name == "Olive oil" })
        #expect(list.last?.name == "Salt and pepper")
        // Pantry staples and spices come after what has to be bought.
        let firstPantry = try #require(list.firstIndex { $0.pantry })
        #expect(list[firstPantry...].allSatisfy { $0.pantry })
        // Things sold whole are counted.
        if let yogurt = list.first(where: { $0.name == "Plain Greek yogurt" }) {
            #expect(yogurt.unit?.contains("tub") == true && (yogurt.count ?? 0) >= 1)
        }
    }

    @Test("prep day fits in an afternoon, oven and pots overlapping")
    func prep() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: Set(MealSlot.allCases)))
        let guide = PrepGuide.make(for: plan)
        #expect(guide.containers == 14)
        #expect(guide.minutes <= 150, "\(guide.minutes) minutes")
        #expect(guide.steps.first?.title == "Set up" && guide.steps.last?.title == "Store")
        #expect(guide.steps.contains { $0.title.hasPrefix("Into the oven") })
        #expect(guide.steps.last!.detail.contains("Lunches and dinners: fridge Mon–Wed, freezer Thu–Sun"), "\(guide.steps.last!.detail)")
        // Steps are in time order, and something cooks while the cook is busy.
        #expect(zip(guide.steps, guide.steps.dropFirst()).allSatisfy { $0.minute <= $1.minute })
        let waits = guide.steps.filter { !$0.handsOn && $0.minutes >= 15 }
        #expect(waits.contains { wait in guide.steps.contains { $0.handsOn && $0.minute > wait.minute && $0.minute < wait.minute + wait.minutes } })
        #expect(guide.packing.count == plan.recipes.count)

        let lunchesOnly = PrepGuide.make(for: planner.plan(start: monday, targets: cut, preferences: PlanPreferences(slots: [.lunch])))
        #expect(lunchesOnly.containers == 7 && lunchesOnly.minutes < guide.minutes)
    }

    @Test("requests read as changes", arguments: [
        ("no fish this week", ["fish"], [String]()),
        ("I'm sick of chicken, more salmon please", ["chicken-breast", "chicken-thigh"], ["salmon"]),
        ("something spicy", [], ["tex-mex", "curry"]),
        ("no fish or pork", ["fish", "pork"], []),
        ("replace the chicken with beef", ["chicken-breast", "chicken-thigh"], ["beef"]),
        ("dairy-free please", ["dairy"], []),
        ("can we do Asian flavours", [], ["teriyaki", "peanut"]),
        ("skip the egg muffins, I'd like overnight oats", ["egg-muffins"], ["overnight-oats"]),
    ])
    func requests(text: String, avoid: [String], want: [String]) {
        let change = PlanRequests.read(text)
        #expect(change.avoid == Set(avoid), "\(text): \(change.avoid)")
        #expect(change.want == Set(want), "\(text): \(change.want)")
    }

    @Test("diet words and cost or time")
    func requestFlags() {
        #expect(PlanRequests.read("make it vegetarian").diet == .vegetarian)
        let vegan = PlanRequests.read("going vegan")
        #expect(vegan.diet == .vegetarian && vegan.avoid.isSuperset(of: ["dairy", "eggs"]))
        #expect(PlanRequests.read("cheaper this week, money's tight").cheaper == true)
        #expect(PlanRequests.read("I'm short on time").quicker == true)
        // Tidied phrases from the model read the same way.
        let tidy = PlanRequests.read(avoid: ["seafood", "chicken"], want: ["Mexican"], diet: "", cheaper: false, quicker: false)
        #expect(tidy.avoid == ["seafood", "chicken-breast", "chicken-thigh"] && tidy.want == ["tex-mex"])
        // Applied, an avoided thing stops being wanted, and a new wish replaces the last.
        var preferences = PlanPreferences(want: ["salmon"])
        preferences = PlanChange(avoid: ["salmon"], want: ["curry"]).applied(to: preferences)
        #expect(preferences.want == ["curry"] && preferences.avoid == ["salmon"])
        #expect(PlanChange(avoid: ["fish"], want: ["tex-mex"], cheaper: true).summary == "No fish · more Tex-Mex · cheaper")
    }

    @Test("a request changes next week's plan the way it says")
    func replan() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences())
        let change = PlanRequests.read("no chicken, more curry")
        let next = planner.replan(plan, preferences: change.applied(to: plan.preferences))
        #expect(next.recipes.contains { $0.profileID == "curry" })
        #expect(!next.recipes.contains { $0.items.contains { $0.ingredientID.hasPrefix("chicken") } })
        #expect(next.id == plan.id)
    }
}
