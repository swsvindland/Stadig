import Foundation
import SystemCore
import Testing
@testable import FoodDatabase

@Suite("Reading a typed search")
struct QueryTests {
    @Test("search expressions keep the food words as stemmed prefixes", arguments: [
        ("eggs", #""egg"*"#),
        ("cherry", #""cherr"*"#),
        ("blueberries", #""blueberr"*"#),
        ("mcdonalds", #""mcdonald"*"#),
        ("McDonald's", #""mcdonald"*"#),
        ("Wendy's", #""wend"*"#),
        ("cookies", #""cookie"*"#),
        ("cup of coffee", #""coffee"*"#),
        ("2 eggs", #""egg"*"#),
        ("200 g chicken breast", #""chicken"* AND "breast"*"#),
        ("200g chicken breast", #""chicken"* AND "breast"*"#),
        ("1.5 cups rice", #""rice"*"#),
        ("1/2 cup oats", #""oat"*"#),
        ("8 fl oz milk", #""milk"*"#),
        ("slice of pizza", #""pizza"*"#),
        ("large egg", #""egg"*"#),
        ("2 large eggs", #""egg"*"#),
        ("2 cups", #""cup"*"#),
        ("12", ""),
        // Numbers written into a name stay, and match only themselves.
        ("2% milk", #""2" AND "milk"*"#),
        ("3.25% milk", #""3" AND "25" AND "milk"*"#),
        ("93/7 ground beef", #""93" AND "7" AND "ground"* AND "beef"*"#),
        ("7-up", #""7" AND "up"*"#),
        ("7up", #""7up"*"#),
        // Count and unit words stay when they name the food.
        ("cup", #""cup"*"#),
        ("cup noodles", #""cup"* AND "noodle"*"#),
        // A letter on its own is a whole word: a search waits for a last word's second letter.
        ("k cup", #""k" AND "cup"*"#),
        ("peanut butter cups", #""peanut"* AND "butter"* AND "cup"*"#),
        ("mini wheats", #""mini"* AND "wheat"*"#),
        ("or", #""or"*"#),
        ("crème brûlée", #""creme"* AND "brulee"*"#),
        // The model's looser wordings don't take over a typed word.
        ("fries", #""fries"*"#),
        ("pop", #""pop"*"#),
        ("ketchup", #"("ketchup"* OR "catsup"*)"#),
        (#"" OR - NEAR ( *"#, #""near"*"#),
        ("", ""),
    ])
    func expression(query: String, expected: String) {
        #expect(searchExpression(query) == expected)
    }

    @Test("a number before a food is kept as an optional phrase")
    func counts() {
        #expect(readQuery("12 grain bread").counts.map { [$0.0, $0.1] } == [["12", "grain"]])
        #expect(readQuery("2 eggs").counts.map { [$0.0, $0.1] } == [["2", "eggs"]])
        #expect(readQuery("2 cups rice").counts.isEmpty)
        #expect(readQuery("2% milk").counts.isEmpty)
    }

    @Test("stems match singular and plural prefixes")
    func stems() {
        #expect(stem("tomatoes") == "tomato")
        #expect(stem("berries") == "berr")
        #expect(stem("strawberry") == "strawberr")
        #expect(stem("hummus") == "hummus")
        #expect(stem("cookies") == "cookie")
        #expect(stem("turkeys") == "turke" && stem("turkey") == "turke")
        #expect(stem("pie") == "pie")
    }

    @Test("typos count a swapped pair as one and read the start of a word")
    func typoDistance() {
        #expect(typos("protien", "protein", limit: 2) == 1)
        #expect(typos("chiken", "chicken", limit: 1) == 1)
        #expect(typos("abc", "xyz", limit: 1) == 2)
        #expect(misread("chikc", "chicken")?.edits == 1)
        #expect(misread("brocoli", "broccoli")?.meant == "broccoli")
        #expect(misread("coke", "cake")?.edits == 1)
        #expect(misread("cok", "cake") == nil, "short words get no typos")
    }

    @Test("typed searches match the person's own foods by word, not by substring")
    func ownFoods() {
        func named(_ name: String, _ brand: String? = nil) -> Food {
            Food(id: "custom:\(name)", name: name, brand: brand, basis: .g, nutrients: .zero, source: .custom)
        }
        #expect(matchesQuery("eggs", named("Egg, whole, cooked, hard-boiled")))
        #expect(matchesQuery("chicken breast", named("Chicken, broilers or fryers, breast")))
        #expect(matchesQuery("chic", named("Chicken thigh")), "a half-typed word counts")
        #expect(matchesQuery("or", named("Orange juice")), "a short word may be a prefix")
        #expect(matchesQuery("cup of coffee", named("Coffee, brewed")))
        #expect(matchesQuery("tyson", named("Chicken breast", "Tyson")))
        #expect(matchesQuery("oat", named("Oat breakfast")))
        #expect(!matchesQuery("oat", named("Goat cheese")))
        #expect(!matchesQuery("rice", named("Licorice")))
        #expect(!matchesQuery("chicken breast", named("Chicken thigh")))
        #expect(!matchesQuery("", named("Anything")))
        // A number in the search is the variety asked for.
        #expect(matchesQuery("2% milk", named("Milk, reduced fat, fluid, 2% milkfat")))
        #expect(!matchesQuery("2% milk", named("Milk, whole, 3.25% milkfat")))
        #expect(!matchesQuery("2% milk", named("Whole milk")))
        #expect(matchesQuery("93/7 beef", named("Ground beef 93/7")))
        #expect(!matchesQuery("93/7 beef", named("Ground beef 80/20")))
        // A corrected word finds them too.
        #expect(!matchesQuery("chiken", named("Chicken thigh")))
        #expect(matchesQuery("chiken", named("Chicken thigh"), fixes: ["chiken": ["chicken"]]))
        #expect(!matchesQuery("chiken", named("Beef thigh"), fixes: ["chiken": ["chicken"]]))
        // Every word the search looks for, not just one: a frequent food doesn't answer a search it
        // shares one word with.
        #expect(!matchesQuery("flat white", named("Rice, white, long-grain, regular, enriched, cooked")))
        #expect(!matchesQuery("chicken soup", named("Chicken breast")))
        #expect(!matchesQuery("rice cake", named("White rice")))
        #expect(matchesQuery("white ri", named("Rice, white, long-grain, regular, enriched, cooked")))
        // A last letter on its own waits for the next, as the catalog search does.
        #expect(matchesQuery("chicken b", named("Chicken thigh")))
        #expect(!matchesQuery("c", named("C")))
        #expect(!matchesQuery("12", named("12 grain bread")))
    }

    @Test("a profile tells a kind of food from others named with the same words")
    func profiles() throws {
        func food(_ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double, _ basis: FoodBasis = .g) -> Food {
            Food(id: "x", name: "x", basis: basis, nutrients: Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat), source: .custom)
        }
        // Mini-Wheats as their labels give them.
        let cereal = try #require(profile([food(360, 9, 82, 2), food(350, 8.3, 85, 2.2), food(370, 10, 80, 1.7), food(345, 9.1, 81.7, 2.5)]))
        #expect(likeness(food(377, 16.4, 78.7, 0), cereal) > 0.9, "shredded wheat")
        #expect(likeness(food(229, 11.4, 42.9, 4.3), cereal) < -0.9, "wheat bread")
        #expect(likeness(food(268, 10.7, 51.8, 0.9), cereal) < 0, "pita pockets")
        // A food counted per serving has no amounts to compare, and three foods are too few to say.
        #expect(likeness(food(110, 3, 23, 0.5, .serving), cereal) == 0)
        #expect(profile([food(360, 9, 82, 2), food(350, 8, 85, 2), food(370, 10, 80, 2)]) == nil)
    }

    @Test("restaurant and packaged foods are recognized as branded")
    func branded() {
        func usda(_ name: String) -> Food { Food(id: "usda:1", name: name, basis: .g, nutrients: .zero, source: .usda) }
        #expect(isBranded(usda("McDONALD'S, french fries")))
        #expect(isBranded(usda("T.G.I. FRIDAY'S, french fries")))
        #expect(isBranded(usda("DOMINO'S 14\" Pepperoni Pizza, Classic Hand-Tossed Crust")))
        #expect(isBranded(Food(id: "off:1", name: "Ketchup", basis: .g, nutrients: .zero, source: .off)))
        #expect(!isBranded(usda("Fast foods, potato, french fried in vegetable oil")))
        #expect(!isBranded(usda("Tomatoes, red, ripe, raw, year round average")))
        #expect(brandWords(name: "McDONALD'S, BIG MAC", brand: "") == ["mcdonald"])
    }
}
