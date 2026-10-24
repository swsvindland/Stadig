import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MealPlanner

/// The bundled USDA catalog, read once.
let planner = MealPlanner(catalog: FoodCatalog.standard(region: "us"))
/// A Monday, prepped the Sunday before.
let monday = Day(year: 2026, month: 10, day: 19)
/// The Sunday before, prep day: a swap or a change then rebuilds the whole week.
let prepMorning = monday.adding(days: -1).date().addingTimeInterval(10 * 3600)
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

        let noFishOrDairy = planner.plan(
            start: monday, targets: cut,
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
        #expect(
            planner.plan(start: monday, targets: cut, preferences: preferences).recipes.map(\.id) == week1.recipes.map(\.id),
            "the same inputs give the same plan")

        let first = try #require(week1.recipes.first { $0.kind == .bowl })
        let swapped = planner.swap(first.id, in: week1, now: prepMorning)
        #expect(swapped.recipe(first.id) == nil)
        #expect(swapped.recipes.filter { $0.kind == .bowl }.count == 2)
        let other = week1.recipes.filter { $0.kind == .bowl }[1]
        #expect(swapped.recipe(other.id) != nil, "the other bowl stays")
        #expect(swapped.id == week1.id && swapped.meals.count == week1.meals.count)

        let breakfast = try #require(week1.recipes.first { $0.slots == [.breakfast] })
        let newBreakfast = planner.swap(breakfast.id, in: week1, now: prepMorning)
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

    @Test("two bowls sharing a vegetable and a grain: both batches are prepped, and the grain cooks in one pot")
    func sharedIngredients() throws {
        let teriyaki = try #require(MealPlanner.Bowl(id: "bowl:teriyaki:chicken-breast:rice-white:broccoli"))
        let peanut = try #require(MealPlanner.Bowl(id: "bowl:peanut:pork:rice-white:broccoli"))
        let plan = planner.build(
            MealPlanner.Choices(bowls: [teriyaki, peanut]), id: UUID(), start: monday, targets: cut,
            preferences: PlanPreferences(), now: monday.date())
        let guide = PrepGuide.make(for: plan)
        let bowls = plan.recipes.filter { $0.kind == .bowl }
        let broccoli = try #require(Library.ingredient("broccoli"))
        let rice = try #require(Library.ingredient("rice-white"))
        // Each bowl's broccoli is prepped, with its own amount and seasoning.
        let preps = guide.steps.filter { $0.title == "Prep for the oven: broccoli" }
        #expect(preps.count == 2, "\(guide.steps.map(\.title))")
        for bowl in bowls {
            let item = try #require(bowl.item("broccoli"))
            let amount = PrepGuide.amount(item.grams * Double(bowl.servings) / broccoli.yield, broccoli)
            #expect(preps.contains { $0.detail.hasPrefix("Cut \(amount) broccoli") }, "\(amount): \(preps.map(\.detail))")
        }
        #expect(preps.contains { $0.detail.contains("chili flakes") } && preps.contains { !$0.detail.contains("chili flakes") })
        // Both bowls' rice goes in one pot.
        let pots = guide.steps.filter { $0.title == "Cook the white rice" }
        #expect(pots.count == 1, "\(guide.steps.map(\.title))")
        let raw = bowls.compactMap { b in b.item("rice-white").map { $0.grams * Double(b.servings) / rice.yield } }.reduce(0, +)
        #expect(pots.first?.detail.hasPrefix("Rinse \(PrepGuide.amount(raw, rice)) white rice") == true, "\(pots.first?.detail ?? "")")
        #expect(guide.steps.first?.detail.contains("a large pot") == true, "\(guide.steps.first?.detail ?? "")")
    }

    @Test(
        "requests read as changes",
        arguments: [
            ("no fish this week", ["fish"], [String]()),
            ("I'm sick of chicken, more salmon please", ["chicken-breast", "chicken-thigh"], ["salmon"]),
            ("something spicy", [], ["tex-mex", "curry"]),
            ("no fish or pork", ["fish", "pork"], []),
            ("replace the chicken with beef", ["chicken-breast", "chicken-thigh"], ["beef"]),
            ("dairy-free please", ["dairy"], []),
            ("can we do Asian flavours", [], ["teriyaki", "peanut"]),
            ("skip the egg muffins, I'd like overnight oats", ["egg-muffins"], ["overnight-oats"]),
            // A verb after a negation is still the negation, not a wish.
            ("I don't want fish this week", ["fish"], []),
            ("I don't like spicy", ["tex-mex", "curry"], []),
            ("no more chicken", ["chicken-breast", "chicken-thigh"], []),
            ("I don't really want to eat any more rice", ["rice-white", "rice-brown"], []),
            ("I don't want chicken, I want beef", ["chicken-breast", "chicken-thigh"], ["beef"]),
            // "and" carries a negation along a list, allergies included.
            ("no fish and pork", ["fish", "pork"], []),
            ("I'm allergic to shellfish and peanuts", ["shellfish", "peanuts"], []),
            ("no chicken and more curry", ["chicken-breast", "chicken-thigh"], ["curry"]),
            ("no rice and use quinoa", ["rice-white", "rice-brown"], ["quinoa"]),
            ("no fish and make it spicy", ["fish"], ["tex-mex", "curry"]),
            ("I can't eat fish and pork", ["fish", "pork"], []),
            // Other ways of saying no.
            ("my partner doesn't like fish", ["fish"], []),
            ("I cannot eat shrimp", ["shrimp"], []),
            ("we didn't like the cod", ["cod"], []),
            // A tag word that also names a flavour or a food is avoided as the tag too.
            ("allergic to fish and peanut", ["fish", "peanuts", "peanut"], []),
            ("allergic to soy", ["soy", "teriyaki"], []),
            ("no eggs", ["eggs"], []),
            ("more eggs", [], ["egg-muffins"]),
        ])
    func requests(text: String, avoid: [String], want: [String]) {
        let change = PlanRequests.read(text)
        #expect(change.avoid == Set(avoid), "\(text): \(change.avoid)")
        #expect(change.want == Set(want), "\(text): \(change.want)")
    }

    @Test("an allergy read from a request leaves its foods out of the plan")
    func allergiesReachThePlan() {
        // Last week asked for the peanut-lime bowl; the allergy wins.
        let before = PlanPreferences(slots: Set(MealSlot.allCases), want: ["peanut", "shrimp"])
        #expect(planner.plan(start: monday, targets: cut, preferences: before).recipes.contains { $0.profileID == "peanut" })
        let change = PlanRequests.read("I'm allergic to shellfish and peanuts")
        let plan = planner.plan(start: monday, targets: cut, preferences: change.applied(to: before))
        for recipe in plan.recipes {
            #expect(recipe.profileID != "peanut", "\(recipe.title)")
            for item in recipe.items {
                #expect(Library.ingredient(item.ingredientID)!.tags.isDisjoint(with: [.shellfish, .peanuts]), "\(recipe.title): \(item.name)")
            }
        }
    }

    @Test("the model's reading counts only for what the request names, and nothing avoided stays wanted")
    func assistantMerge() {
        func merged(_ request: String, avoid: [String], want: [String]) -> PlanChange {
            let (words, named) = PlanRequests.reading(request)
            return PlanAssistant.merge(PlanRequests.read(avoid: avoid, want: want), words: words, named: named)
        }
        // The word rules read "but chicken" as more chicken; the model's avoid wins.
        let butChicken = merged("I'd love anything but chicken", avoid: ["chicken"], want: [])
        #expect(butChicken.avoid == ["chicken-breast", "chicken-thigh"] && butChicken.want.isEmpty, "\(butChicken)")
        // A wish the model reads for something left out goes: more fish is cod, not salmon.
        let noSalmon = merged("more fish, but no salmon", avoid: ["salmon"], want: ["fish"])
        #expect(noSalmon.avoid == ["salmon"] && noSalmon.want == ["cod"], "\(noSalmon)")
        // The device model's own replies (macOS 27, 24 October 2026): the whole menu, or an allergy,
        // from words that name none of it. Only what the request names is kept.
        let curry = merged(
            "combine or same meal for lunch and dinner, just do a high protein Japanese curry",
            avoid: ["rice", "quinoa", "pasta", "potatoes", "sweet potatoes", "vegetables"],
            want: ["chicken", "turkey", "beef", "pork", "salmon", "cod", "shrimp", "tofu"])
        #expect(curry == PlanChange(want: ["japanese-curry"], oneDish: true), "\(curry)")
        #expect(curry.summary == "One dish all week · more Japanese curry")
        #expect(merged("high protein please", avoid: ["gluten"], want: ["salmon", "curry"]).isEmpty)
        #expect(merged("I'm really busy this week", avoid: ["gluten"], want: ["beef", "pasta"]) == PlanChange(quicker: true))
        // Nor the other flavour a dish's name is made of: "Japanese" alone is teriyaki.
        #expect(merged("a Japanese curry", avoid: [], want: ["Japanese", "curry"]).want == ["japanese-curry"])
        // A model reply with nothing in it leaves the word rules' reading.
        let words = PlanRequests.read("no chicken, something spicy")
        #expect(merged("no chicken, something spicy", avoid: [], want: []) == words)
    }

    @Test("one dish for every lunch and dinner, asked for in a request")
    func oneDishRequests() {
        for request in [
            "combine or same meal for lunch and dinner, just do a high protein Japanese curry",
            "Same meal for lunch and dinner. Just do a high protein Japanese curry",
            "Instead of two different meals just do Japanese curry for lunch and dinner",
            "Japanese curry for both lunch and dinner",
        ] {
            let change = PlanRequests.read(request)
            #expect(change.oneDish == true && change.want == ["japanese-curry"] && change.avoid.isEmpty, "\(request): \(change)")
        }
        #expect(PlanRequests.read("just one dish this week").oneDish == true)
        #expect(PlanRequests.read("more variety please").oneDish == false)
        #expect(PlanRequests.read("not the same meal for lunch and dinner").oneDish == false)
        #expect(PlanRequests.read("I don't need variety").oneDish == true)
        // The week, not the dish.
        #expect(PlanRequests.read("the same meals as last week but no pork").oneDish == nil)
        #expect(PlanRequests.read("no fish").oneDish == nil)
        // A wish for one week of curry doesn't stop at the flavour's first dish.
        #expect(PlanRequests.read("curry").want == ["curry"])
    }

    @Test("one dish is one batch for every lunch and dinner, through swaps, other dishes and a change back")
    func oneDish() throws {
        let preferences = PlanChange(want: ["japanese-curry"], oneDish: true).applied(to: PlanPreferences(slots: Set(MealSlot.allCases)))
        let plan = planner.plan(start: monday, targets: cut, preferences: preferences)
        let bowls = plan.recipes.filter { $0.kind == .bowl }
        let bowl = try #require(bowls.first)
        #expect(bowls.count == 1 && bowl.servings == 14, "\(plan.recipes.map(\.title))")
        #expect(bowl.profileID == "japanese-curry" && bowl.title.hasPrefix("Japanese curry "), "\(bowl.title)")
        #expect(plan.meals.filter { $0.slot == .lunch || $0.slot == .dinner }.allSatisfy { $0.recipeID == bowl.id })
        // Still sized to the day: one dish isn't a smaller or bigger one.
        for day in plan.days {
            let n = plan.planned(on: day)
            #expect(abs(n.kcal - cut.kcal) / cut.kcal < 0.08, "\(day): \(Int(n.kcal)) kcal")
            #expect(n.protein >= cut.protein * 0.9, "\(day): \(Int(n.protein)) g protein")
        }
        // Kept for days 1 to 3, then frozen, as any batch.
        #expect(plan.meals.filter { $0.recipeID == bowl.id && $0.storage == .freezer }.count == 8)

        let swapped = planner.swap(bowl.id, in: plan, now: prepMorning)
        let swappedBowls = swapped.recipes.filter { $0.kind == .bowl }
        #expect(swappedBowls.count == 1 && swappedBowls[0].id != bowl.id && swappedBowls[0].servings == 14)
        #expect(swappedBowls[0].profileID == "japanese-curry", "still what was asked for: \(swappedBowls[0].title)")
        let shuffled = planner.shuffle(plan, variation: 1, now: prepMorning)
        #expect(shuffled.recipes.filter { $0.kind == .bowl }.count == 1)

        let two = planner.replan(plan, preferences: PlanChange(oneDish: false).applied(to: plan.preferences), now: prepMorning)
        let twoBowls = two.recipes.filter { $0.kind == .bowl }
        #expect(twoBowls.count == 2 && twoBowls.allSatisfy { $0.servings == 7 }, "\(two.recipes.map(\.title))")
        #expect(twoBowls.contains { $0.profileID == "japanese-curry" })
    }

    @Test("a Japanese curry: carrot and potato in a thickened curry gravy over rice")
    func japaneseCurry() throws {
        let plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(want: ["japanese-curry"], oneDish: true))
        let bowl = try #require(plan.recipes.first)
        #expect(
            Set(bowl.items.map(\.ingredientID)).isSuperset(of: ["carrots", "potato", "onion", "flour", "soy-sauce"]), "\(bowl.items.map(\.name))")
        #expect(bowl.items.contains { $0.ingredientID.hasPrefix("rice") })
        let guide = PrepGuide.make(for: plan)
        let sauce = try #require(guide.steps.first { $0.title == "Make the Japanese curry sauce" }, "\(guide.steps.map(\.title))")
        #expect(sauce.detail.contains("flour") && sauce.detail.contains("roast potatoes") && sauce.minutes == 14)
        #expect(guide.steps.contains { $0.title == "Prep for the oven: potatoes" })
        #expect(guide.containers == 14)
        let groceries = Groceries.list(for: plan)
        #expect(groceries.contains { $0.id == "flour" && $0.pantry })
        #expect(groceries.contains { $0.id == "spice:Curry powder" })
        // Gluten-free leaves it out: the gravy is thickened with flour.
        #expect(
            !planner.plan(start: monday, targets: cut, preferences: PlanPreferences(avoid: ["gluten"], want: ["japanese-curry"]))
                .recipes.contains { $0.profileID == "japanese-curry" })
    }

    @Test("diet words and cost or time")
    func requestFlags() {
        #expect(PlanRequests.read("make it vegetarian").diet == .vegetarian)
        let vegan = PlanRequests.read("going vegan")
        #expect(vegan.diet == .vegetarian && vegan.avoid.isSuperset(of: ["dairy", "eggs"]))
        #expect(PlanRequests.read("cheaper this week, money's tight").cheaper == true)
        #expect(PlanRequests.read("I'm short on time").quicker == true)
        #expect(PlanRequests.read("busy week").quicker == true)
        // Allergies and intolerances, however they're put, by the setup's word for the group.
        #expect(PlanRequests.read("I'm lactose intolerant").avoid == ["dairy"])
        #expect(PlanRequests.read("I have a nut allergy").avoid == ["nuts"])
        #expect(PlanRequests.read("an allergy to shellfish, more salmon") == PlanChange(avoid: ["shellfish"], want: ["salmon"]))
        #expect(PlanRequests.read("I'm coeliac").avoid == ["gluten"])
        #expect(PlanRequests.read("peanut-free, please").avoid == ["peanuts"])
        // Words inside other words don't count: breakfast isn't fast.
        #expect(PlanRequests.read("the same breakfast every day").quicker == nil)
        // Tidied phrases from the model read the same way.
        let tidy = PlanRequests.read(avoid: ["seafood", "chicken"], want: ["Mexican"])
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
        let next = planner.replan(plan, preferences: change.applied(to: plan.preferences), now: prepMorning)
        #expect(next.recipes.contains { $0.profileID == "curry" })
        #expect(!next.recipes.contains { $0.items.contains { $0.ingredientID.hasPrefix("chicken") } })
        #expect(next.id == plan.id)
    }

    @Test("a swap or a change once the week has started leaves the days already eaten alone")
    func midWeek() throws {
        var plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(), now: prepMorning)
        let wednesday = monday.adding(days: 2)
        let mondayLunch = try #require(plan.meals.first { $0.day == monday && $0.slot == .lunch })
        let wednesdayLunch = try #require(plan.meals.first { $0.day == wednesday && $0.slot == .lunch })
        plan.logged = [mondayLunch.id: [UUID()], wednesdayLunch.id: [UUID()]]
        let first = try #require(plan.recipes.first { $0.kind == .bowl })
        #expect(wednesdayLunch.recipeID == first.id, "the bowls alternate: Wednesday's lunch is the first one")

        func check(_ next: MealPlan, from day: Day, replacing gone: (String) -> Bool) {
            #expect(next.meals.map(\.id) == plan.meals.map(\.id) && next.logged == plan.logged && next.id == plan.id)
            for meal in plan.meals {
                guard let after = next.meals.first(where: { $0.id == meal.id }) else { continue }
                if meal.day < day || plan.logged[meal.id] != nil {
                    #expect(after.recipeID == meal.recipeID, "\(meal.id) was eaten as planned")
                    #expect(next.recipe(after.recipeID) != nil)
                } else {
                    #expect(!gone(after.recipeID), "\(meal.id): \(after.recipeID)")
                }
            }
            // Servings match the meals, the kept dish's included.
            #expect(next.recipes.allSatisfy { r in r.servings == next.meals.filter { $0.recipeID == r.id }.count })
            // Still two bowls a day from here on.
            for d in next.days where d >= day {
                #expect(Set(next.meals(on: d).filter { $0.slot == .lunch || $0.slot == .dinner }.map(\.recipeID)).count == 2, "\(d)")
            }
        }

        // Swapped at Wednesday noon: Monday, Tuesday and Wednesday's logged lunch keep the first bowl.
        let noon = wednesday.date().addingTimeInterval(12 * 3600)
        let swapped = planner.swap(first.id, in: plan, now: noon)
        check(swapped, from: wednesday) { $0 == first.id }
        #expect(swapped.recipe(first.id)?.servings == 3, "Monday's lunch, Tuesday's dinner and Wednesday's lunch")
        // Swapping the new bowl the next day picks from what's still to come, not the kept dish.
        let thursday = wednesday.adding(days: 1)
        let added = try #require(swapped.recipes.first { $0.kind == .bowl && plan.recipe($0.id) == nil })
        let again = planner.swap(added.id, in: swapped, variation: 2, now: thursday.date().addingTimeInterval(12 * 3600))
        check(again, from: thursday) { $0 == added.id || $0 == first.id }

        // A change mid-week: no chicken from Wednesday on, and what was eaten stays.
        let change = PlanRequests.read("no chicken")
        let changed = planner.replan(plan, preferences: change.applied(to: plan.preferences), now: noon)
        check(changed, from: wednesday) { id in changed.recipe(id)?.items.contains { $0.ingredientID.hasPrefix("chicken") } == true }

        // Other dishes mid-week: every dish from Wednesday on is new, and what was eaten stays.
        let old = Set(plan.recipes.map(\.id))
        let shuffled = planner.shuffle(plan, variation: 1, now: noon)
        check(shuffled, from: wednesday) { old.contains($0) }
        #expect(shuffled.createdAt == plan.createdAt && shuffled.checked == plan.checked)
    }

    @Test("other dishes replace every dish in a week not yet started, none coming back in another slot")
    func shuffle() throws {
        let everything = PlanPreferences(slots: Set(MealSlot.allCases))
        let plan = planner.plan(start: monday, targets: cut, preferences: everything, now: prepMorning)
        for variation in 1...4 {
            let shuffled = planner.shuffle(plan, variation: variation, now: prepMorning)
            #expect(shuffled.id == plan.id && shuffled.meals.map(\.id) == plan.meals.map(\.id) && shuffled.preferences == plan.preferences)
            #expect(Set(shuffled.recipes.map(\.id)).isDisjoint(with: plan.recipes.map(\.id)), "variation \(variation)")
            #expect(shuffled.recipes.filter { $0.kind == .bowl }.count == 2)
            #expect(shuffled.recipes.contains { $0.slots == [.breakfast] } && shuffled.recipes.contains { $0.slots == [.snack] })
            #expect(shuffled.recipes.allSatisfy { r in r.servings == shuffled.meals.filter { $0.recipeID == r.id }.count })
            for day in shuffled.days {
                #expect(Set(shuffled.meals(on: day).filter { $0.slot == .lunch || $0.slot == .dinner }.map(\.recipeID)).count == 2, "\(day)")
                // The new snack is the one that fills the new week best, not just the next in line.
                let n = shuffled.planned(on: day)
                #expect(abs(n.kcal - cut.kcal) / cut.kcal < 0.08, "\(day): \(Int(n.kcal)) kcal")
                #expect(n.protein >= cut.protein * 0.85, "\(day): \(Int(n.protein)) g protein")
            }
            #expect(planner.shuffle(plan, variation: variation, now: prepMorning) == shuffled, "the same variation gives the same week")
        }
        // Swapping one bowl and then the other brings the first one's old dish back for these.
        for (preferences, variation) in [(PlanPreferences(diet: .vegetarian), 15), (PlanPreferences(diet: .pescatarian), 18)] {
            let week = planner.plan(start: monday, targets: cut, preferences: preferences, now: prepMorning)
            let shuffled = planner.shuffle(week, variation: variation, now: prepMorning)
            #expect(Set(shuffled.recipes.map(\.id)).isDisjoint(with: week.recipes.map(\.id)), "\(preferences.diet)")
        }
        // A week that's over has nothing left to change.
        let later = plan.end.adding(days: 1).date().addingTimeInterval(12 * 3600)
        #expect(planner.shuffle(plan, variation: 1, now: later) == plan)
    }

    @Test("other dishes twice in a week don't bring back a dish the week has had")
    func shuffleTwice() throws {
        let everything = PlanPreferences(slots: Set(MealSlot.allCases))
        let plan = planner.plan(start: monday, targets: cut, preferences: everything, now: prepMorning)
        let wednesday = monday.adding(days: 2)
        let friday = monday.adding(days: 4)
        for variation in 1...4 {
            let first = planner.shuffle(plan, variation: variation, now: wednesday.date().addingTimeInterval(12 * 3600))
            let second = planner.shuffle(first, variation: variation + 1, now: friday.date().addingTimeInterval(12 * 3600))
            // Monday and Tuesday keep the week's first snack, Wednesday and Thursday the next, and
            // neither comes back from Friday on: each shuffle used to rule out only the current one.
            let had = Set(first.meals.filter { $0.day < friday }.map(\.recipeID))
            for meal in second.meals where meal.day >= friday {
                #expect(!had.contains(meal.recipeID), "variation \(variation): \(meal.id) is \(meal.recipeID) again")
            }
            #expect(second.recipes.filter { $0.slots == [.snack] }.count == 3 && second.recipes.filter { $0.slots == [.breakfast] }.count == 3)
            for day in second.days where day >= friday {
                let n = second.planned(on: day)
                #expect(abs(n.kcal - cut.kcal) / cut.kcal < 0.08, "\(day): \(Int(n.kcal)) kcal")
                #expect(n.protein >= cut.protein * 0.85, "\(day): \(Int(n.protein)) g protein")
            }
        }
    }

    @Test("only dishes still to be eaten can be swapped")
    func swappable() throws {
        var plan = planner.plan(start: monday, targets: cut, preferences: PlanPreferences(), now: prepMorning)
        let ids = plan.recipes.map(\.id)
        #expect(planner.swappable(plan, today: monday.adding(days: -1)) == ids, "before the week, every dish, in the plan's order")
        #expect(planner.swappable(plan, today: plan.end) == ids)
        #expect(planner.swappable(plan, today: plan.end.adding(days: 1)).isEmpty)
        // On Sunday, only Sunday's two meals are left; logging one leaves the other's dish.
        let sunday = plan.meals(on: plan.end)
        #expect(sunday.count == 2)
        plan.logged[sunday[0].id] = [UUID()]
        #expect(planner.swappable(plan, today: plan.end) == [sunday[1].recipeID])
        plan.logged[sunday[1].id] = [UUID()]
        #expect(planner.swappable(plan, today: plan.end).isEmpty)
        #expect(planner.shuffle(plan, variation: 1, now: plan.end.date().addingTimeInterval(12 * 3600)) == plan)
        // A dish swapped out mid-week stays on the days it was eaten, but can't be swapped again.
        plan.logged = [:]
        let wednesday = monday.adding(days: 2)
        let swapped = planner.swap(ids[0], in: plan, now: wednesday.date().addingTimeInterval(12 * 3600))
        #expect(swapped.recipe(ids[0]) != nil)
        let left = planner.swappable(swapped, today: wednesday)
        #expect(!left.contains(ids[0]) && left.contains(ids[1]) && left.count == 2)
    }
}
