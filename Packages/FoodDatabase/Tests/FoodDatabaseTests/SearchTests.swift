import Foundation
import Synchronization
import Testing

@testable import FoodDatabase

/// Everyday searches and a pattern one of the first three results must match ("(?i)" ignores case).
let searchBasket: [(String, String)] = [
    ("egg", "^Egg, whole, "),
    ("eggs", "^Egg, whole, "),
    ("2 eggs", "^Egg, whole, "),
    ("rice", "^Rice, white, long-grain, .*cooked"),
    ("white rice", "^Rice, white, long-grain, .*cooked"),
    ("brown rice", "^Rice, brown, .*cooked"),
    ("chicken", "^Chicken, broilers or fryers, .*cooked, roasted"),
    ("chicken breast", "^Chicken, broilers or fryers, breast, .*cooked, roasted"),
    ("200g chicken breast", "^Chicken, broilers or fryers, breast, .*cooked"),
    ("apple", "^Apples, raw"),
    ("apples", "^Apples, raw"),
    ("banana", "^Bananas, raw"),
    ("blueberry", "^Blueberries, raw$"),
    ("strawberries", "^Strawberries, raw$"),
    ("cherry", "^Cherries, sweet, raw"),
    ("avocado", "^Avocados, raw"),
    ("broccoli", "^Broccoli, (raw|cooked)"),
    ("coffee", "^Beverages, coffee, brewed"),
    ("cup of coffee", "^Beverages, coffee, brewed"),
    ("potato", "^Potatoes, (baked|boiled)"),
    ("sweet potato", "^Sweet potato, cooked, (baked|boiled)"),
    ("salmon", "^Fish, salmon, .*cooked"),
    ("tuna", "^Fish, tuna, "),
    ("ground beef", "^Beef, ground, "),
    ("milk", "^Milk, whole, "),
    ("whole milk", "^Milk, whole, "),
    ("greek yogurt", "^Yogurt, Greek, plain"),
    ("cheese", "^Cheese, cheddar"),
    ("cream cheese", "^Cheese, cream$"),
    ("cottage cheese", "^Cheese, cottage, "),
    ("oatmeal", "^Cereals, oats, .*cooked"),
    ("pasta", "^Pasta, cooked"),
    ("peanut butter", "^Peanut butter, (smooth|chunk)"),
    ("almonds", "^Nuts, almonds"),
    ("black beans", "^Beans, black, mature seeds, cooked"),
    ("orange juice", "^Orange juice, raw"),
    ("slice of pizza", "^Pizza, cheese topping"),
    ("mcdonalds", "^McDONALD'S, "),
    ("big mac", "^McDONALD'S, BIG MAC$"),
    ("wendys", "^WENDY'S, "),
    // Fat levels and other numbers written into a name.
    ("2% milk", "^Milk, reduced fat, fluid, 2% milkfat"),
    ("1% milk", "^Milk, lowfat, fluid, 1% milkfat"),
    ("85% lean ground beef", "^Beef, ground, 85% lean"),
    ("93/7 ground beef", "^Beef, ground, 93% lean meat / ?7% fat"),
    ("80/20 ground beef", "^Beef, ground, 80% lean meat / ?20% fat"),
    ("0% greek yogurt", "\\b0%"),
    ("2% cottage cheese", "^Cheese, cottage, lowfat, 2% milkfat"),
    ("12 grain bread", "(?i)^12 grain bread"),
    ("7-up", "(?i)^7 up$"),
    // Count and unit words that name the food.
    ("cup noodles", "(?i)cup noodle"),
    ("glass noodles", "(?i)glass noodle"),
    ("k cup", "(?i)\\bk.?cups?\\b"),
    ("peanut butter cups", "(?i)peanut butter cup"),
    ("mini wheats", "(?i)mini.wheats"),
    ("strip steak", "(?i)strip steak"),
    ("potato wedges", "(?i)potato wedges"),
    ("fries", "(?i)fries"),
    ("pop tarts", "(?i)pop.?tart"),
    ("burger", "(?i)burger"),
    // USDA spells it doughnut.
    ("glazed donut", "^Doughnuts, .*glazed"),
]

/// Searches whose first result must match.
let firstResults: [(String, String)] = [
    ("eggs", "^Egg, whole, cooked"),
    ("rice", "^Rice, white, long-grain, .*cooked"),
    ("mcdonalds big mac", "^McDONALD'S, BIG MAC$"),
    // The top row is the one typed: its fat level, the named product, not a looser wording.
    ("2% milk", "^Milk, reduced fat, fluid, 2% milkfat"),
    ("milk 2%", "^Milk, reduced fat, fluid, 2% milkfat"),
    ("93% lean ground beef", "^Beef, ground, 93% lean"),
    ("90/10 ground beef", "^Beef, ground, 90% lean meat / ?10% fat"),
    ("cup noodles", "(?i)cup noodle"),
    ("peanut butter cups", "(?i)peanut butter cups"),
    ("fries", "(?i)fries"),
    ("pop tarts", "(?i)pop.?tarts"),
    ("burger", "(?i)burger"),
    ("pop", "^Snacks, popcorn"),
    // A food named by its leading parts, as USDA inverts them, before a blend or dish with the words.
    ("olive oil", "^Oil, olive, salad or cooking$"),
    ("peanut butter", "^Peanut butter, (smooth|chunk)"),
    ("white rice", "^Rice, white, long-grain, .*cooked"),
    ("brown rice", "^Rice, brown, .*cooked"),
    ("chicken breast", "^Chicken, broilers or fryers, breast, .*cooked, roasted"),
    ("whole milk", "^Milk, whole, "),
    ("cheddar cheese", "^Cheese, cheddar"),
    ("sour cream", "^Cream, sour"),
    // A count before a food only ranks a name that has it: "2 eggs" are still plain eggs.
    ("2 eggs", "^Egg, whole, cooked"),
    // A half-typed last word is searched once it has two letters; until then, the rest is.
    ("chicken b", "^Chicken, "),
    ("chicken br", "^Chicken, broilers or fryers, breast"),
    // Words the catalog doesn't know fall back to the last word, which names the food.
    ("zesty homestyle banana", "^Bananas, raw"),
    // Typos and joined words still find the food that was meant.
    ("chiken breast", "^Chicken, broilers or fryers, breast, "),
    ("chikc", "^Chicken, "),
    ("bananna", "^Bananas, raw"),
    // Worldwide, hundreds of labels spell these as typed, so those products answer them.
    ("brocoli", "(?i)^(Broccoli, raw|brocoli$)"),
    ("avacado", "^Avocados, raw"),
    ("straberries", "^Strawberries, raw"),
    ("yogrt", "^Yogurt, "),
    ("greek yougurt", "^Yogurt, Greek, plain"),
    ("mozerella", "(?i)^(Cheese, mozzarella|mozz?arella$)"),
    ("cheeze", "^Cheese, cheddar"),
    ("salmen", "^Fish, salmon, .*cooked"),
    ("quinao", "^Quinoa, cooked"),
    ("cofee", "^Beverages, coffee, brewed"),
    ("peanutbutter", "^Peanut butter, "),
    ("icecream", "^Ice creams, "),
    ("protien bar", "(?i)protein bar"),
    ("teff", "^Teff, "),
    ("beet", "^Beets, raw"),
    // A word typed as spelled on a label ranks before the correction of it.
    ("brest", "(?i)breast"),
    // Packaged foods people scan more come first among a brand's products.
    ("coca cola", "(?i)^coca.cola$"),
]

/// Generic foods USDA names in inverted form, searched without the packaged-food catalog.
@Suite("Search without packaged foods")
struct GenericSearchTests {
    @Test(
        "a food named by its leading parts comes first",
        arguments: [
            ("olive oil", "^Oil, olive, salad or cooking$"),
            ("canola oil", "^Oil, canola$"),
            ("peanut butter", "^Peanut butter, (smooth|chunk)"),
            ("white rice", "^Rice, white, long-grain, .*cooked"),
            ("brown rice", "^Rice, brown, .*cooked"),
            ("chicken breast", "^Chicken, broilers or fryers, breast, .*cooked, roasted"),
            ("whole milk", "^Milk, whole, "),
            ("cheddar cheese", "^Cheese, cheddar"),
            ("eggs", "^Egg, whole, cooked"),
            ("apples", "^Apples, raw"),
            ("coffee", "^Beverages, coffee, brewed"),
            ("chicken br", "^Chicken, broilers or fryers, breast"),
        ])
    func first(query: String, pattern: String) {
        let names = Catalogs.usda.top(query)
        #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
    }

    @Test(
        "a chain's menu item is found by the chain and the item, with or without its size",
        arguments: [
            ("papa johns 14 inch pepperoni", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("papa johns pepperoni", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("little caesars pepperoni", "^LITTLE CAESARS .*Pepperoni"),
            ("dominos 14 inch pepperoni pizza", #"^DOMINO'S 14" Pepperoni Pizza"#),
            ("pizza hut 12 inch pepperoni", #"^PIZZA HUT 12" Pepperoni Pizza"#),
        ])
    func chains(query: String, pattern: String) {
        // Without packaged foods the chains USDA writes in capitals are still known as brands.
        let names = Catalogs.usda.top(query)
        #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
    }

    @Test(
        "a restaurant food is found by what it is and where it's from, and a chain's burger by its name",
        arguments: [
            ("chicken nuggets", "^Chicken nuggets, from (restaurant|fast food)$"),
            ("chicken nuggets fast food", "^Chicken nuggets, from fast food$"),
            ("fast food fries", "^Potato, french fries, fast food$"),
            ("pepperoni pizza restaurant", "^Pizza with pepperoni, from restaurant or fast food"),
            ("black beans restaurant", "^Black beans, from fast food / restaurant$"),
            ("pancakes restaurant", "^Pancakes, plain, fast food / restaurant$"),
            ("big mac", #"^Big Mac \(McDonalds\)$"#),
            ("whopper", #"^Whopper \(Burger King\)$"#),
            ("mcdouble", #"^McDouble \(McDonalds\)$"#),
        ])
    func restaurantFoods(query: String, pattern: String) {
        // FNDDS's fast-food and restaurant foods, beside SR Legacy's older chain items.
        for catalog in [Catalogs.usda, Catalogs.both] {
            let names = catalog.top(query)
            #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
        }
    }

    @Test("the person's own foods appear only for searches they have every word of")
    func personal() throws {
        let catalog = Catalogs.usda
        let rice = try #require(catalog.search("white rice").first { $0.food.name == "Rice, white, long-grain, regular, enriched, cooked" }?.food)
        let breast = try #require(catalog.search("chicken breast").first?.food)
        let mine = [PersonalFood(food: rice, score: 20), PersonalFood(food: breast, score: 20)]
        // Without packaged foods, a search nothing matches in full falls back to foods with its last
        // word; the person's own are among them but don't move up.
        for query in ["flat white", "rice cake", "chicken soup", "white bread", "breast milk"] {
            let found = catalog.search(query, personal: mine)
            let plain = catalog.search(query)
            #expect(found.map(\.food.id) == plain.map(\.food.id), "\(query): \(found.prefix(3).map(\.food.name))")
            #expect(found.first?.personal != true, "\(query)")
        }
        // They lead the searches they do answer, as typed so far.
        for query in ["rice", "white rice", "whi", "chicken", "chicken b", "chicken br", "brest"] {
            #expect(catalog.search(query, personal: mine).first?.personal == true, "\(query)")
        }
    }
}

/// The app searches from detached tasks, task groups and `concurrentPerform` at once.
@Suite("Search from many threads")
struct ConcurrentSearchTests {
    @Test("searches run at once give the answers they give one at a time, and after memory is released")
    func parallel() {
        let queries = ["chicken breast", "chiken", "white rice", "apples", "olive oil", "peanutbutter", "milk", "eggs", "coca cola", "greek yog"]
        let serial = FoodCatalog(usda: Catalogs.usdaURL, off: Catalogs.offURL, region: "us")
        let expected = queries.map { serial.search($0).map(\.food.id) }
        // A fresh catalog, so the caches fill from every thread at once.
        let catalog = FoodCatalog(usda: Catalogs.usdaURL, off: Catalogs.offURL, region: "us")
        let runs = queries.count * 4
        let found = Mutex<[[String]]>(Array(repeating: [], count: runs))
        DispatchQueue.concurrentPerform(iterations: runs) { i in
            let ids =
                i % 2 == 0
                ? catalog.search(queries[i % queries.count]).map(\.food.id)
                : catalog.candidates(name: queries[i % queries.count], brand: nil).map(\.food.id)
            found.withLock { $0[i] = ids }
        }
        let candidates = queries.map { serial.candidates(name: $0, brand: nil).map(\.food.id) }
        for (i, ids) in found.withLock({ $0 }).enumerated() {
            #expect(ids == (i % 2 == 0 ? expected : candidates)[i % queries.count], "\(queries[i % queries.count])")
        }
        catalog.releaseMemory()
        #expect(queries.map { catalog.search($0).map(\.food.id) } == expected)
        #expect(catalog.failures == 0 && serial.failures == 0)
    }
}

@Suite("Search", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"))
struct SearchTests {
    let catalog = Catalogs.both

    @Test("everyday searches put a plain staple in the top three", arguments: searchBasket)
    func staple(query: String, pattern: String) {
        let names = catalog.top(query)
        #expect(names.contains { matches(pattern, $0) }, "\(query): \(names.joined(separator: " | "))")
    }

    @Test("the first result is the one typed", arguments: firstResults)
    func first(query: String, pattern: String) {
        let names = catalog.top(query)
        #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
    }

    @Test("branded foods stay reachable, and a named brand is not marked down")
    func branded() throws {
        let oreo = try #require(catalog.search("oreo").first?.food)
        #expect(oreo.source == .off)
        #expect(matches("(?i)oreo", oreo.brand ?? ""))
        let cola = try #require(catalog.search("coca cola").first?.food)
        #expect(matches("(?i)coca.cola", "\(cola.name) \(cola.brand ?? "")"))
        // A brand only resembling the search ("Pizzah") does not outrank plain pizza.
        #expect(catalog.search("pizza").first?.food.source == .usda)
        // Plain searches keep generic foods ahead of packaged ones.
        for query in ["chicken breast", "greek yogurt", "peanut butter"] {
            #expect(catalog.search(query).first?.food.source == .usda, "\(query)")
        }
        #expect(catalog.top("kind bar", 3).contains { matches("(?i)^kind bar$", $0) })
    }

    @Test(
        "a search naming a brand finds that brand's version first, then the name brand",
        arguments: ["trader joes mini wheats", "mini wheats trader joes"])
    func namedBrand(query: String) {
        // Trader Joe's sells Mini-Wheats as "Shredded Bite Size Wheats", in either word order; its
        // pita pockets have every word but bread's macros, and come after Kellogg's own.
        let found = catalog.names(query, 12)
        let listed = found.joined(separator: " | ")
        #expect(found.first.map { matches(#"^Shredded Bite Size Wheats \[Trader Joe"#, $0) } == true, "\(listed)")
        let kelloggs = found.firstIndex { matches(#"(?i)mini.?wheats.*\[Kellog"#, $0) } ?? -1
        let bread = found.firstIndex { matches("(?i)pita|bread|wraps|tortilla", $0) } ?? -1
        #expect(kelloggs > 0 && kelloggs < 5, "\(listed)")
        #expect(bread < 0 || bread > kelloggs, "\(listed)")
        #expect(catalog.searchCatalog(query, known: [:]).brand == ["trader", "joes"])
    }

    @Test("brands that don't make the food, or sell it by that name, and words that aren't brands")
    func brands() {
        // A brand that doesn't make the food leaves the name brand first, not the word's raw grain.
        let kirkland = catalog.names("kirkland mini wheats")
        #expect(kirkland.first.map { matches(#"(?i)mini.?wheats.*\[Kellogg"#, $0) } == true, "\(kirkland)")
        // A brand selling the food by that name keeps all of those ahead of its other cereal flakes.
        for name in catalog.names("great value frosted flakes", 3) {
            #expect(matches(#"(?i)frosted.*flakes.*\[Great Value\]"#, name), "\(name)")
        }
        // The brand's spread, not the cups and cookies named after it.
        for name in catalog.names("trader joes peanut butter", 4) {
            #expect(matches(#"(?i)peanut butter\b(?! (cups?|brittle|filled))"#, name), "\(name)")
        }
        // Brands that name their products, lone letters and a search for a brand alone stay names.
        for query in ["oreo cookies", "k cup", "pop", "kirkland", "chicken breast"] {
            #expect(catalog.searchCatalog(query, known: [:]).brand.isEmpty, "\(query)")
        }
        // A word found only in a brand counts half: "wheats" is not the brand Wheaty.
        #expect(!catalog.names("mini wheats", 8).contains { matches("(?i)wheaty", $0) })
    }

    @Test(
        "a chain's menu item comes first, however the chain and its size are typed",
        arguments: [
            ("papa johns 14 inch pepperoni", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("papa johns 14” pepperoni", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("papa john's pepperoni pizza", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("pepperoni pizza papa johns", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("papa johns large pepperoni", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("papajohns pepperoni", #"^PAPA JOHN'S 14" Pepperoni Pizza"#),
            ("dominos pepperoni", #"^DOMINO'S 14" Pepperoni Pizza"#),
            ("little caesars pepperoni", "^LITTLE CAESARS .*Pepperoni"),
            ("pizza hut pepperoni", "^PIZZA HUT .*Pepperoni"),
            ("wendys frosty", "^WENDY'S, Frosty"),
            ("kfc original recipe", "^KFC, .*ORIGINAL RECIPE"),
            ("14 inch pepperoni pizza", #"14" (pizza, )?pepperoni"#),
        ])
    func chainItems(query: String, pattern: String) {
        let names = catalog.top(query)
        #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
    }

    @Test("a brand that makes nothing like what the other words usually name means its own food by them")
    func brandsOwnKind() {
        // Pepperoni is usually the sausage, but Papa John's sells it on a pizza; cheddar is often a
        // cracker, but Tillamook's is cheese; and labels say "milk chocolate" far more than chocolate milk.
        let papa = catalog.names("papa johns pepperoni", 3)
        #expect(papa.first.map { matches("^PAPA JOHN'S", $0) } == true, "\(papa)")
        #expect(!papa.contains { matches(#"^Pepperoni \["#, $0) }, "\(papa)")
        for name in catalog.names("tillamook cheddar", 3) { #expect(matches(#"(?i)cheddar.*\[Tillamook\]"#, name), "\(name)") }
        let fairlife = catalog.names("fairlife chocolate milk", 3)
        #expect(fairlife.first.map { matches(#"(?i)^chocolate milk \[fairlife\]"#, $0) } == true, "\(fairlife)")
        // The brand as typed comes before a longer one that starts with it: Papa John's, then Papa
        // John's Salads & Produce.
        #expect(catalog.names("papa johns 14 inch pepperoni", 2).last.map { matches(#"\[Papa John's Salads? & Produce\]"#, $0) } == true)
        // A chain USDA names is a brand of its own words, not a shorter brand inside them.
        #expect(catalog.searchCatalog("little caesars pepperoni", known: [:]).brand == ["little", "caesars"])
        #expect(catalog.searchCatalog("dominos pepperoni", known: [:]).brand == ["dominos"])
    }

    @Test("the person's own foods lead a search, more so the more often they are eaten")
    func personal() throws {
        let pool = catalog.search("eggs").map(\.food)
        let boiled = try #require(pool.first { $0.name == "Egg, whole, cooked, hard-boiled" })
        let scrambled = try #require(pool.first { $0.name == "Egg, whole, cooked, scrambled" })
        #expect(pool.first?.id != boiled.id)
        let mine = catalog.search("eggs", personal: [PersonalFood(food: boiled, score: 0)])
        #expect(mine.first?.food.id == boiled.id && mine.first?.personal == true)
        #expect(mine.filter { $0.food.id == boiled.id }.count == 1, "listed once")
        let often = catalog.search("eggs", personal: [PersonalFood(food: boiled, score: 1), PersonalFood(food: scrambled, score: 20)])
        #expect(often.prefix(2).map(\.food.id) == [scrambled.id, boiled.id])
        // A known food still has to match the search.
        #expect(!catalog.search("banana", personal: [PersonalFood(food: boiled, score: 5)]).contains { $0.food.id == boiled.id })
        // A custom food leads the catalog when it matches, including through a corrected typo.
        let custom = Food(id: "custom:thigh", name: "Chicken thigh", basis: .g, nutrients: .zero, source: .custom)
        #expect(catalog.search("chiken", personal: [PersonalFood(food: custom, score: 1)]).first?.food.id == custom.id)
        #expect(catalog.search("chicken", personal: [PersonalFood(food: custom, score: 1)], limit: 5).count == 5)
    }

    @Test("a frequent food doesn't lead a search it shares only one word with")
    func unrelatedPersonal() throws {
        let rice = try #require(catalog.search("white rice").first { $0.food.name == "Rice, white, long-grain, regular, enriched, cooked" }?.food)
        let flat = catalog.search("flat white", personal: [PersonalFood(food: rice, score: 20)])
        #expect(
            flat.first.map { matches("(?i)flat white", "\($0.food.name) \($0.food.brand ?? "")") } == true,
            "\(flat.prefix(3).map(\.food.name))")
        #expect(!flat.contains { $0.food.id == rice.id })
        let breast = try #require(catalog.search("chicken breast").first?.food)
        #expect(!catalog.search("chicken soup", personal: [PersonalFood(food: breast, score: 20)]).contains { $0.food.id == breast.id })
        let ownRice = Food(id: "custom:rice", name: "White rice", basis: .g, nutrients: .zero, source: .custom)
        let cakes = catalog.search("rice cake", personal: [PersonalFood(food: ownRice, score: 20), PersonalFood(food: rice, score: 20)])
        #expect(!cakes.contains { $0.personal }, "\(cakes.prefix(3).map(\.food.name))")
        #expect(cakes.first.map { matches("(?i)rice cake", $0.food.name) } == true, "\(cakes.prefix(3).map(\.food.name))")
        // AI matching keeps its own foods in reach but doesn't boost a partial match over a real one.
        let seen = catalog.candidates(name: "flat white", brand: nil, personal: [PersonalFood(food: rice, score: 20)])
        #expect(seen.first?.food.id != rice.id)
    }

    @Test("search waits for a second letter, and a number alone isn't a search")
    func gate() {
        for query in ["c", "a", "   ", "", "12", "2 g", "qqqzzz"] { #expect(catalog.search(query).isEmpty, "\(query)") }
    }

    @Test("typos are corrected only when the catalogs barely know the word")
    func fixes() {
        let found = catalog.searchCatalog("chiken brest", known: [:])
        #expect(found.fixes["chiken"] == ["chicken"])
        #expect(found.fixes["brest"]?.first == "breast")
        // Real words stay as typed, including rare ones a typo from a common one.
        for query in ["beet", "kale", "chicken", "oreo", "hummus", "lasagne"] {
            #expect(catalog.searchCatalog(query, known: [:]).fixes.isEmpty, "\(query)")
        }
    }

    @Test("a barcode finds its packaged food in every form")
    func barcodes() throws {
        let nutella = try #require(catalog.food(barcode: "80176800"))
        #expect(nutella.name == "Nutella")
        #expect(catalog.food(barcode: "0080176800") == nil, "not a barcode length")
        #expect(catalog.food(barcode: "80176801") == nil, "bad check digit")
        #expect(catalog.food(barcode: "00000080176800")?.id == nutella.id)
    }
}

@Suite("AI matching candidates", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"))
struct CandidateTests {
    let catalog = Catalogs.both

    @Test("catalog queries run from specific to broad")
    func queries() {
        let queries = catalog.catalogQueries(Named(name: "Hamburger bun", brand: "Wendy's"))
        // Stems prefix-match every form: "wend"* finds "WENDY'S".
        #expect(queries.first?.hasPrefix(#""wend"* AND "#) == true)
        #expect(queries.contains { $0.contains(#"("bun"* OR "roll"*)"#) })
        // Count words are not searched as foods.
        #expect(catalog.catalogQueries(Named(name: "tomato slice", brand: "")).first == #""tomato"*"#)
        #expect(
            catalog.catalogQueries(Named(name: "cheddar cheese slice", brand: "")) == [#""cheddar"* AND "cheese"*"#, #""cheese"*"#, #""cheddar"*"#])
    }

    @Test(
        "seen foods match the everyday catalog food, not a variation",
        arguments: [
            ("lettuce", "^Lettuce, .*raw", ""),
            ("tomato slice", "^Tomatoes, red, ripe", ""),
            ("hamburger bun", "^Rolls, hamburger", ""),
            ("bacon", "(?i)bacon", "(?i)meatless|turkey|bits|sticks"),
            ("french fries", "(?i)french fr", ""),
            ("black coffee", "^Beverages, coffee, brewed", ""),
            ("egg", "^Egg, whole", ""),
            ("chicken", "^Chicken", "(?i)feet|giblets|liver|skin"),
            ("white rice", "long-grain", ""),
            ("cheese", "(?i)cheddar|american", ""),
        ])
    func everyday(name: String, pattern: String, not: String) throws {
        let found = catalog.candidates(name: name, brand: nil)
        let first = try #require(found.first)
        #expect(matches(pattern, first.food.name), "\(name): \(found.prefix(4).map(\.food.name))")
        if !not.isEmpty { #expect(!matches(not, first.food.name), "\(name): \(first.food.name)") }
        #expect(!isBranded(first.food), "\(name): \(first.food.name)")
        #expect(first.score >= 1.5, "a sure match")
        #expect(found.count > 1, "alternatives to swap to")
    }

    @Test(
        "a plain seen food is the form it's usually eaten in",
        arguments: [
            ("salmon", "^Fish, salmon, .*cooked", "(?i)smoked|lox|raw"),
            ("oatmeal", "^Cereals, oats, .*cooked with water", "(?i)dry|cookie|bread|bran"),
            ("beans", "^Beans, (black|pinto), mature seeds, cooked", "(?i)snap|baked|raw"),
            ("lentils", "^Lentils, .*cooked", "(?i)raw"),
            ("chicken", "^Chicken, .*cooked", "(?i)raw|feet|frankfurter"),
            ("rice", "^Rice, white, long-grain, .*cooked", "(?i)raw"),
            ("green beans", "^Beans, snap, green", "(?i)raw|black|pinto"),
            ("toast", "^Bread, (white|wheat), .*toasted", "(?i)rye|egg|oatmeal|muffin"),
            ("rye toast", "^Bread, rye, toasted", "(?i)wheat|white"),
            ("raw salmon", "^Fish, salmon, .*raw", "(?i)cooked|smoked"),
        ])
    func cookedForm(name: String, pattern: String, not: String) throws {
        let found = catalog.candidates(name: name, brand: nil)
        let first = try #require(found.first)
        #expect(matches(pattern, first.food.name), "\(name): \(found.prefix(4).map(\.food.name))")
        #expect(!matches(not, first.food.name), "\(name): \(first.food.name)")
        #expect(first.score >= 1.5, "a sure match")
    }

    @Test("a dish the catalog files under another name is found by it")
    func dishNames() throws {
        #expect(catalogDish("Spaghetti bolognese") == "spaghetti meat sauce")
        #expect(catalogDish("spag bol") == "spaghetti meat sauce")
        #expect(catalogDish("Penne with bolognese sauce") == "penne meat sauce")
        #expect(catalogDish("Chicken soup") == "Chicken soup")
        let found = catalog.candidates(name: "spaghetti bolognese", brand: nil)
        let first = try #require(found.first)
        #expect(matches("(?i)^(Restaurant, Italian, )?spaghetti with meat sauce", first.food.name), "\(found.prefix(4).map(\.food.name))")
        #expect(!isBranded(first.food))
        // A brand's own bolognese keeps its name.
        let branded = catalog.candidates(name: "spaghetti bolognese", brand: "Nutriquick")
        #expect(branded.first.map { matches("(?i)bolognese", $0.food.name) } == true, "\(branded.prefix(3).map(\.food.name))")
    }

    @Test("a named brand's food is found under the brand's own name for it")
    func brands() throws {
        func first(_ name: String, _ brand: String) -> String {
            catalog.candidates(name: name, brand: brand).first.map { "\($0.food.name) [\($0.food.brand ?? "")]" } ?? ""
        }
        // Trader Joe's calls them "Shredded Bite Size Wheats"; its wheat bread is another food.
        #expect(matches(#"^Shredded Bite Size Wheats \[Trader Joe"#, first("Mini Wheats", "Trader Joe's")))
        // Kirkland makes none, so Kellogg's, not a Kirkland bagel or raw wheat.
        #expect(matches("(?i)mini.?wheats", first("Mini Wheats", "Kirkland")))
        #expect(matches(#"(?i)^(Crunchy |Creamy )?Peanut Butter \[Trader Joe"#, first("peanut butter", "Trader Joe's")))
        // A chain's item, with a plain food kept within reach.
        let pizza = catalog.candidates(name: "Pepperoni pizza", brand: "Domino's")
        #expect(pizza.first.map { matches("^DOMINO'S .*Pepperoni", $0.food.name) } == true, "\(pizza.prefix(3).map(\.food.name))")
        #expect(pizza.prefix(8).contains { !isBranded($0.food) && matches("(?i)pizza", $0.food.name) })
    }

    @Test("a weak best match is offered but not chosen")
    func weak() {
        let found = catalog.candidates(name: "uni sashimi", brand: nil)
        #expect((found.first?.score ?? 0) < 1.5, "the catalog has no uni")
        #expect(found.prefix(8).contains { matches("(?i)sashimi", $0.food.name) })
    }

    @Test("the person's own foods are preferred when they match")
    func personal() throws {
        let own = Food(id: "custom:latte", name: "Oat milk latte", basis: .ml, nutrients: .zero, source: .custom)
        let found = catalog.candidates(name: "oat milk latte", brand: nil, personal: [PersonalFood(food: own, score: 3)])
        #expect(found.first?.food.id == own.id && found.first?.personal == true)
        #expect(catalog.candidates(name: "banana", brand: nil, personal: [PersonalFood(food: own, score: 3)]).allSatisfy { !$0.personal })
        #expect(catalog.candidates(name: "chicken", brand: nil, limit: 5).count == 5)
    }
}
