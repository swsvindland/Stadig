import Testing

@testable import FoodDatabase

@Suite("What follows the first result")
struct VarietyTests {
    let catalog = Catalogs.usda

    @Test func foodsThatDifferOnlyInANoteShareAKey() {
        let key = Variety.key
        // What was added, how it was graded and trimmed, and USDA's notes in brackets.
        #expect(
            key("Milk, whole, 3.25% milkfat, with added vitamin D") == key("Milk, whole, 3.25% milkfat, without added vitamin A and vitamin D"))
        #expect(key("Rice, white, long-grain, regular, enriched, cooked") == key("Rice, white, long-grain, regular, unenriched, cooked"))
        #expect(key("Beans, black, mature seeds, cooked, boiled, without salt") == key("Beans, black, mature seeds, cooked, boiled, with salt"))
        #expect(key("Bagels, plain, enriched, with calcium propionate (includes onion, poppy, sesame)") == key("Bagels, plain, unenriched"))
        #expect(
            key("Beef, top sirloin, steak, separable lean only, trimmed to 0\" fat, choice, cooked, broiled")
                == key("Beef, top sirloin, steak, separable lean only, trimmed to 1/8\" fat, select, cooked, broiled"))
        #expect(key("Wheat flour, white, all-purpose, enriched, bleached") == key("Wheat flour, white, all-purpose, unenriched"))
        #expect(key("Corn, sweet, yellow, canned, whole kernel, regular pack") == key("Corn, sweet, yellow, canned, whole kernel, no salt added"))
        // Not what the food is, how it's cooked or what's left on it.
        #expect(key("Butter, salted") != key("Butter, without salt") && key("Milk, whole") != key("Milk, lowfat"))
        #expect(key("Rice, white, cooked") != key("Rice, white, raw") && key("Rice, white, cooked") != key("Rice, brown, cooked"))
        #expect(key("Beef, top sirloin, separable lean only, cooked") != key("Beef, top sirloin, separable lean and fat, cooked"))
        #expect(key("Chicken breast, cooked, with skin") != key("Chicken breast, cooked, without skin"))
    }

    @Test func aWordsKindsAreTheEverydayFoodsNamedWithIt() {
        let milk = Variety.kinds(of: "milk")
        #expect(milk.prefix(2) == ["whole milk", "almond milk"] && milk.contains("skim milk") && milk.contains("2% milk"))
        #expect(Variety.kinds(of: "oil").prefix(3) == ["olive oil", "canola oil", "coconut oil"])
        // The plural asks for the same ones.
        #expect(Variety.kinds(of: "eggs") == Variety.kinds(of: "egg") && Variety.kinds(of: "egg").contains("fried egg"))
        // A food that only ends on the word isn't a kind of it, nor is a dish named with "and".
        #expect(!Variety.kinds(of: "butter").contains("peanut butter") && !Variety.kinds(of: "cream").contains("ice cream"))
        #expect(!Variety.kinds(of: "water").contains("coconut water") && !Variety.kinds(of: "beer").contains("root beer"))
        #expect(!Variety.kinds(of: "beans").contains("rice and beans") && !Variety.kinds(of: "cheese").contains("mac and cheese"))
        // A word still being typed has none, nor has one nothing is named with, nor "green",
        // which stems to the greens it isn't.
        #expect(Variety.kinds(of: "mil").isEmpty && Variety.kinds(of: "quinoa").isEmpty && Variety.kinds(of: "green").isEmpty)
    }

    @Test func aOneWordSearchGoesOnToItsKinds() {
        let starts = { (query: String, firsts: [String]) -> Bool in
            let found = catalog.top(query, firsts.count)
            return found.count == firsts.count && zip(found, firsts).allSatisfy { $0.hasPrefix($1) }
        }
        #expect(
            starts("milk", ["Milk, whole", "Almond milk", "Oat milk", "Milk, nonfat"]), "\(catalog.top("milk", 4))")
        #expect(starts("oil", ["Oil, olive", "Oil, canola", "Oil, coconut", "Oil, vegetable"]), "\(catalog.top("oil", 4))")
        #expect(starts("beans", ["Beans, black", "Beans, snap, green", "Beans, pinto", "Beans, kidney"]), "\(catalog.top("beans", 4))")
        #expect(starts("chicken", ["Chicken, cooked", "Chicken, grilled", "Chicken, rotisserie", "Chicken, fried"]), "\(catalog.top("chicken", 4))")
        #expect(starts("rice", ["Rice, white", "Rice, brown", "Rice, fried"]), "\(catalog.top("rice", 3))")
        #expect(starts("juice", ["Orange juice", "Apple juice", "Cranberry juice", "Grapefruit juice"]), "\(catalog.top("juice", 4))")
        #expect(starts("cheese", ["Cheese, cheddar", "Cheese, cottage", "Cheese, cream", "Cheese, swiss"]), "\(catalog.top("cheese", 4))")
        // Each is the food its own search leads with.
        for kind in ["almond milk", "skim milk", "canola oil", "pinto beans", "grilled chicken", "brown rice", "apple juice"] {
            let first = catalog.top(kind, 1)
            let word = String(kind.split(separator: " ").last ?? "")
            #expect(first.count == 1 && catalog.top(word, 4).contains(first[0]), "\(kind)")
        }
        // The first result is the search's own, and the scores still fall down the list.
        for query in ["milk", "oil", "beans", "chicken", "egg", "bread", "water"] {
            let found = catalog.search(query)
            #expect(found.first?.food.id == catalog.searchCatalog(query, known: [:]).ranked.first?.food.id, "\(query)")
            #expect(zip(found, found.dropFirst()).allSatisfy { $0.score >= $1.score }, "\(query)")
            #expect(Set(found.map(\.food.id)).count == found.count, "\(query)")
        }
        // A food that isn't a kind of the word, or is only named with the kind's words in
        // passing, isn't brought up: no ice cream after cream, no oatmeal made with oat milk.
        #expect(!catalog.top("cream", 4).contains { $0.hasPrefix("Ice cream") } && !catalog.top("milk", 5).contains { $0.hasPrefix("Oatmeal") })
        #expect(!catalog.top("butter", 4).contains { $0.lowercased().contains("peanut") })
    }

    @Test func aWordForAKindOfFoodGoesOnToTheFoodsItStandsFor() {
        let starts = { (query: String, firsts: [String]) -> Bool in
            let found = catalog.top(query, firsts.count)
            return found.count == firsts.count && zip(found, firsts).allSatisfy { $0.hasPrefix($1) }
        }
        // After the catalogs' own food of no one kind, the ones people mean by the word.
        #expect(starts("nuts", ["Nuts, mixed nuts", "Nuts, almonds", "Peanuts, all types", "Nuts, cashew nuts"]), "\(catalog.top("nuts", 4))")
        #expect(starts("berries", ["Berries", "Strawberries, raw", "Blueberries, raw", "Raspberries, raw"]), "\(catalog.top("berries", 4))")
        #expect(starts("fruit", ["Fruit", "Apples, raw", "Bananas, raw", "Oranges, raw"]), "\(catalog.top("fruit", 4))")
        #expect(starts("vegetables", ["Vegetables, mixed", "Broccoli, raw", "Carrots, raw", "Spinach, raw"]), "\(catalog.top("vegetables", 4))")
        #expect(starts("fish", ["Fish, cooked", "Fish, salmon", "Fish, tuna", "Fish, cod"]), "\(catalog.top("fish", 4))")
        #expect(starts("cereal", ["Cereal, ready-to-eat", "Cereal, corn flakes", "Cereal, granola", "Oatmeal"]), "\(catalog.top("cereal", 4))")
        // Before it, where the catalogs' first is no food anyone means by the word: a
        // lotus's seeds, green tea, a non-dairy milk, mechanically deboned poultry.
        #expect(
            starts("seeds", ["Seeds, sunflower", "Seeds, chia", "Seeds, flaxseed", "Seeds, pumpkin", "Seeds, lotus"]), "\(catalog.top("seeds", 5))")
        #expect(starts("greens", ["Lettuce, green leaf", "Spinach, raw", "Kale, raw", "Collards, raw"]), "\(catalog.top("greens", 4))")
        #expect(
            starts("dairy", ["Milk, whole", "Cheese, cheddar", "Yogurt, plain", "Butter, salted", "Non-dairy milk"]), "\(catalog.top("dairy", 5))")
        #expect(starts("poultry", ["Chicken, cooked", "Turkey, cooked", "Duck, cooked", "Poultry, mechanically"]), "\(catalog.top("poultry", 4))")
        #expect(starts("seafood", ["Shrimp, cooked", "Fish, salmon", "Crab, cooked", "Fish, tuna"]), "\(catalog.top("seafood", 4))")
        // And where they name nothing by it.
        #expect(starts("legumes", ["Beans, black", "Lentils", "Chickpeas"]), "\(catalog.top("legumes", 3))")
        #expect(starts("spirits", ["Vodka", "Whiskey", "Rum", "Tequila"]), "\(catalog.top("spirits", 4))")
        // The word whole: "green" is on its way to green beans, and a seed isn't seeds.
        #expect(catalog.top("green", 2).allSatisfy { $0.hasPrefix("Beans, snap, green") }, "\(catalog.top("green", 2))")
        #expect(catalog.top("seed", 1) == catalog.searchCatalog("seed", known: [:]).ranked.prefix(1).map(\.food.name))
        #expect(Variety.groups["green"] == nil && Variety.groups["seed"] == nil && Variety.groups["veggies"]?.leads == false)
        // Each is the food its own search leads with, the scores still fall and no food is listed twice.
        #expect(catalog.top("almonds", 1) == [catalog.top("nuts", 2)[1]] && catalog.top("sunflower seeds", 1) == catalog.top("seeds", 1))
        for query in ["nuts", "seeds", "dairy", "greens", "legumes", "cereal"] {
            let found = catalog.search(query)
            #expect(zip(found, found.dropFirst()).allSatisfy { $0.score >= $1.score }, "\(query)")
            #expect(Set(found.map(\.food.id)).count == found.count, "\(query)")
        }
    }

    @Test func foodsThatDifferComeBeforeTheSameFoodAgain() {
        // Whole milk is one food, bagels differ by their grain, and white rice by its grain's
        // length and whether it's cooked.
        #expect(catalog.top("whole milk", 2).last?.hasPrefix("Milk, whole, 3.25%") == false, "\(catalog.top("whole milk", 2))")
        #expect(catalog.top("bagel", 3).dropFirst() == ["Bagels, wheat", "Bagels, multigrain"], "\(catalog.top("bagel", 3))")
        for query in ["white rice", "bagel", "black beans", "flour", "sirloin steak", "canned corn"] {
            let plain = catalog.search(query).prefix(6).map(\.food).filter { $0.source == .usda && ($0.brand ?? "").isEmpty }
            #expect(Set(plain.map { Variety.key($0.name) }).count == plain.count, "\(query): \(plain.map(\.name))")
        }
        // The same foods are found, in another order.
        for query in ["white rice", "whole milk", "milk", "bagel"] {
            let found = catalog.search(query, limit: 200).map(\.food.id)
            let ranked = catalog.searchCatalog(query, known: [:]).ranked.map(\.food.id)
            #expect(Set(ranked).isSubset(of: Set(found)) || found.count == 200, "\(query)")
        }
    }

    @Test func aSearchOfMoreWordsOrABrandKeepsItsOrder() {
        // Kinds follow one word only: "almond milk" doesn't go on to skim milk, nor "2 eggs"
        // or "eggs on toast" to the ways eggs are cooked.
        #expect(!catalog.top("almond milk", 4).contains { $0.hasPrefix("Milk, nonfat") })
        let ranked = { (query: String) in catalog.searchCatalog(query, known: [:]).ranked.prefix(3).map(\.food.name) }
        #expect(catalog.top("2 eggs", 3) == ranked("2 eggs") && catalog.top("eggs on toast", 3) == ranked("eggs on toast"))
        // The kinds' own searches aren't kept as the person's. On a catalog of its own:
        // the shared one is searched by other tests meanwhile.
        let own = FoodCatalog(usda: Catalogs.usdaURL, off: nil, region: "us")
        _ = own.search("yogurt")
        #expect(own.recent.withLock { $0.map(\.asked.typed) } == ["yogurt"])
        #expect(own.kindFoods.withLock { $0["greek yogurt"] } != nil)
        // A food and what it comes with stay as they were found.
        let plate = catalog.searchCatalog("chicken and rice", known: [:]).ranked.prefix(2).map(\.food.name)
        #expect(Array(catalog.top("chicken and rice", 2)) == plate)
        // A brand's foods are in the order they were found.
        let brand = catalog.searchCatalog("mcdonalds fries", known: [:])
        #expect(!brand.brand.isEmpty && catalog.search("mcdonalds fries").prefix(10).map(\.food.id) == brand.ranked.prefix(10).map(\.food.id))
    }
}
