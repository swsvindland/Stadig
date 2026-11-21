import Foundation
import SystemCore
import Testing

@testable import FoodDatabase

/// A search's words read against each food's own name and brand, wherever they were typed. These
/// rank foods made here, so they run without either catalog.
@Suite("A food's own words")
struct OwnWordsTests {
    static func food(_ name: String, brand: String? = nil, _ nutrients: Nutrients = Nutrients(kcal: 100, protein: 5, carbs: 10, fat: 4)) -> Food {
        Food(
            id: "\(brand == nil ? "usda" : "off"):\(name)|\(brand ?? "")", name: name, brand: brand, basis: .g, nutrients: nutrients,
            source: brand == nil ? .usda : .off)
    }

    static let shelf = [
        food("Cheese, cottage, creamed, large or small curd"),
        food("Cowpeas, catjang, mature seeds, raw"),
        food("Cottage Cheese", brand: "Happy Farms"),
        food("Cottage Cheese", brand: "The Honest Cow"),
        food("Wasabi, root, raw"),
        food("Bread, wheat"),
        food("Whole Grain Crisp Bread", brand: "Wasa"),
        food("Crisp Bread", brand: "Wasa"),
        food("Nuts, chestnuts, european, roasted"),
        food("Gala Apples", brand: "Orchard Fresh"),
        food("Roasted Chestnuts", brand: "Galli"),
        food("Liquid Egg Whites", brand: "Egg-Land's Best"),
        food("Large Brown Eggs", brand: "Egg-Land's Best"),
    ]

    func first(_ query: String, doubted: Set<String> = []) -> String {
        rankSearch(query, Self.shelf, hints: RankHints(doubted: doubted)).first.map { "\($0.food.name) [\($0.food.brand ?? "")]" } ?? ""
    }

    @Test(
        "a brand is the food's brand wherever its words are typed",
        arguments: [
            "honest cow cottage cheese", "cottage cheese honest cow", "cottage honest cow cheese", "cheese cottage cow honest",
            "cottage cheese the honest cow", "cottage cheese honest cows",
        ])
    func anywhere(query: String) {
        // Not cowpeas for the last word "cow", nor USDA's cottage cheese for the two words it has.
        #expect(first(query) == "Cottage Cheese [The Honest Cow]")
    }

    @Test("the word naming the food is the last that isn't the brand's")
    func head() {
        // "wasa" starts wasabi, but it's the whole of a brand whose food has the other words.
        #expect(first("crisp bread wasa") == "Crisp Bread [Wasa]")
        #expect(first("wasa crisp bread") == "Crisp Bread [Wasa]")
        // Each of the brand's words takes one word typed, so "eggs" still names the food.
        #expect(first("egg land best brown eggs") == "Large Brown Eggs [Egg-Land's Best]")
        #expect(first("brown eggs egg lands best") == "Large Brown Eggs [Egg-Land's Best]")
    }

    @Test("after a food, the last word may be as far as the brand is typed")
    func halfTyped() {
        #expect(first("crisp bread was") == "Crisp Bread [Wasa]")
        #expect(first("roasted chestnuts gal") == "Roasted Chestnuts [Galli]")
        // Every word of the brand has to be typed or begun: "honest" alone isn't The Honest Cow.
        #expect(first("cottage cheese honest") == "Cheese, cottage, creamed, large or small curd []")
        // Alone, it's as much the start of a food: the brand's foods get nothing for it.
        let alone = rankSearch("was", Self.shelf)
        #expect(alone.first?.food.name == "Wasabi, root, raw", "\(alone.map(\.food.name))")
    }

    @Test("a word the catalogs barely know is a food's own word misspelt")
    func misspelt() {
        #expect(first("gali roasted chestnuts", doubted: ["gali"]) == "Roasted Chestnuts [Galli]")
        #expect(first("roasted chestnuts gali", doubted: ["gali"]) == "Roasted Chestnuts [Galli]")
        // A word they know is taken as typed, and one letter is the most a short word may be out by.
        #expect(first("gali roasted chestnuts") == "Nuts, chestnuts, european, roasted []")
        #expect(first("gxlo roasted chestnuts", doubted: ["gxlo"]) == "Nuts, chestnuts, european, roasted []")
    }

    @Test("a typo is compared with a food's words, a stem isn't a brand, and joined words may be a word apart")
    func words() throws {
        let typed = try #require(Misspelling("gali"))
        #expect(typed.reads(["roast", "chestnut", "galli"]))
        #expect(!typed.reads(["gal", "ga"]), "too short to be what was meant")
        #expect(!typed.reads(["garlic"]), "two letters out")
        #expect(try #require(Misspelling("kerrygnld")).reads(["kerrygold"]))
        #expect(Misspelling("egg") == nil && Misspelling("7up") == nil)
        // Possessives and plurals name the same brand; a shared stem doesn't.
        #expect(bare("joes") == bare("joe") && bare("kelloggs") == "kellogg")
        #expect(stem("wheats") == stem("wheaty") && bare("wheats") != bare("wheaty"))
        // "Member's Mark" has an "s" between its words in the index.
        #expect(searchTerm("membermark", ["membermark": ["member mark"]]) == #"("membermark"* OR NEAR("member" "mark"*, 1))"#)
        #expect(searchTerm("chiken", ["chiken": ["chicken"]]) == #"("chiken"* OR "chicken"*)"#)
    }

    @Test("a name written as one word or as two matches as well either way")
    func oneWordOrTwo() {
        let drinks = [Self.food("Red Bull Energy Drink", brand: "Red Bull"), Self.food("Redbull Energy Drink", brand: "Redbull")]
        let apart: Fixes = ["red": ["redbull"], "bull": ["redbull"]]
        let both = rankSearch("red bull energy drink", drinks, hints: RankHints(fixes: apart, respelt: ["redbull"]))
        #expect(both.count == 2 && both.allSatisfy { $0.name == 1 })
        #expect(abs(both[0].score - both[1].score) < 0.01, "\(both.map(\.score))")
        // Read as a correction instead, the one word is a guess and ranks below the words typed.
        let guessed = rankSearch("red bull energy drink", drinks, hints: RankHints(fixes: apart))
        #expect(guessed.first?.food.brand == "Red Bull" && guessed[0].score - guessed[1].score > 0.3, "\(guessed.map(\.score))")
        let corn = [Self.food("Pop Corn", brand: "Jolly Time"), Self.food("Popcorn", brand: "Jolly Time")]
        let joined = rankSearch("popcorn", corn, hints: RankHints(fixes: ["popcorn": ["pop corn"]], respelt: ["pop corn"]))
        #expect(joined.count == 2 && abs(joined[0].score - joined[1].score) < 0.01, "\(joined.map(\.score))")
        // A word that stands for two names a brand only when both are the brand's: "blackberries",
        // also written "black berries", doesn't name Berry Fresh by its "berries".
        let berries = [Self.food("Blackberries", brand: "Berry Fresh"), Self.food("Fresh Blackberries", brand: "Driscoll's")]
        let fresh = rankSearch(
            "fresh blackberries", berries, hints: RankHints(fixes: ["blackberries": ["black berr"]], respelt: ["black berr"]))
        #expect(fresh.first?.food.brand == "Driscoll's", "\(fresh.map { $0.food.brand ?? "" })")
        // The other way is searched in place of the word, not beside it.
        #expect(searchTerm("popcorn", ["popcorn": ["pop corn"]], only: true) == #"NEAR("pop" "corn"*, 1)"#)
        #expect(searchTerm("bull", ["bull": ["redbull"]], only: true) == #""redbull"*"#)
        // Kinds of food are told apart by their usual energy and macros.
        let drink = Profile(center: [log(55), 0, 11, 0], spread: [0.15, 3, 6, 3])
        let sweet = Profile(center: [log(510), 9, 55, 30], spread: [0.15, 3, 6, 3])
        #expect(drink.distance(to: drink) == 0 && drink.distance(to: sweet) > 2.25)
        #expect(drink.distance(to: Profile(center: [log(50), 0, 12, 0], spread: [0.15, 3, 6, 3])) < 2.25)
    }

    @Test("a brand people scan is read while it's still being typed")
    func brandsBegun() {
        let scanned = { (name: String, brand: String, popularity: Double) -> Food in
            var food = Self.food(name, brand: brand)
            food.popularity = popularity
            return food
        }
        let first = { (query: String, foods: [Food]) in rankSearch(query, foods, hints: RankHints(popularity: true)).first?.food.title ?? "" }
        // One of the most scanned brands, before a plain food that starts the same.
        let juice = scanned("Orange Juice No Pulp", "Tropicana", 2)
        #expect(first("trop", [Self.food("Beverages, Tropical Punch, ready-to-drink"), juice]) == juice.title)
        // Any other brand comes after a plain food that leads with the letters, and before one
        // that only has them somewhere.
        let ham = scanned("Le Bon Paris", "Herta", 2)
        #expect(first("her", [ham, Self.food("Fish, herring, Atlantic, raw")]) == "Fish, herring, Atlantic, raw")
        let sauce = scanned("Original Hot Sauce", "Cholula", 3)
        #expect(first("chol", [Self.food("Mayonnaise, reduced-calorie or diet, cholesterol-free"), sauce]) == sauce.title)
        // A brand of several words is begun by its first typed whole, and a letter typed after
        // it that starts the next says so whatever plain food has the word.
        let pint = scanned("Vanilla Bean", "Halo Top", 2)
        #expect(first("halo", [Self.food("Halot", brand: "Wegmans"), pint]) == pint.title)
        let soda = scanned("Baja Blast", "Mountain Dew", 2)
        let yam = Self.food("Mountain yam, hawaii, raw")
        #expect(first("mountain d", [yam, soda]) == soda.title)
        #expect(first("mountain y", [soda, yam]) == yam.name)
        // An everyday food's own word isn't a brand begun until a letter of its next is typed.
        let pocket = scanned("Pepperoni Pizza Sandwich", "Hot Pockets", 2)
        let chile = Self.food("Sauce, hot chile, sriracha")
        #expect(first("hot", [pocket, chile]) == chile.name)
        #expect(first("hot p", [chile, pocket]) == pocket.title)
        // A brand no one scans, typed whole, is as likely one of the most scanned begun.
        let spread = scanned("Hazelnut Spread", "Nutella", 6)
        let smoothie = Self.food("Superfood Smoothie", brand: "Nutes")
        #expect(first("nute", [smoothie, spread]) == spread.title)
        #expect(first("nutes", [spread, smoothie]) == smoothie.title)
    }

    @Test("the asked brand's food named by exactly the words typed comes before its foods more like the usual")
    func exactlyNamed() {
        // Most chocolate bars are milk chocolate; this brand's "Chocolate Bar" is darker than its others.
        let usual = Nutrients(kcal: 540, protein: 6, carbs: 58, fat: 31)
        let bars = [
            Self.food("Chocolate Date Bar", brand: "Trader Joe's", usual),
            Self.food("Milk Chocolate Bar", brand: "Trader Joe's", usual),
            Self.food("Chocolate Bar", brand: "Trader Joe's", Nutrients(kcal: 613, protein: 10, carbs: 32, fat: 48)),
            Self.food("Chocolate Bar", brand: "Hershey's", usual),
        ]
        let kind = Profile(center: [log(550), 6, 58, 31], spread: [0.15, 3, 6, 3])
        let ranked = rankSearch("trader joes chocolate bar", bars, hints: RankHints(brand: ["trader", "joes"], profile: kind))
        #expect(ranked.first.map { "\($0.food.name) [\($0.food.brand ?? "")]" } == "Chocolate Bar [Trader Joe's]")
        #expect(ranked.count == 4)
    }
}

/// The same readings over the catalogs, where a brand has thousands of foods and a word a dozen meanings.
@Suite("Brands in a search", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"))
struct BrandReadingTests {
    let catalog = Catalogs.both

    @Test(
        "a brand typed first, last or between a food's words finds the brand's food",
        arguments: [
            ("honest cow cottage cheese", #"^Cottage Cheese \[The Honest Cow\]"#),
            ("cottage cheese honest cow", #"^Cottage Cheese \[The Honest Cow\]"#),
            ("crisp bread wasa", #"(?i)^crisp bread \[wasa\]"#),
            ("sourdough crispbread wasa", #"(?i)^sourdough crispbread \[wasa\]"#),
            ("apple cinnamon oats mush", #"(?i)^apple cinnamon oats \[mush\]"#),
            ("minute jasmine rice", #"^Jasmine Rice \[Minute"#),
            ("jasmine rice minute", #"^Jasmine Rice \[Minute"#),
            ("jasmine minute rice", #"^Jasmine Rice \[Minute"#),
            ("frosted kelloggs flakes", #"(?i)frosted flakes.*\[Kellogg"#),
            ("wheat thins original nabisco", #"(?i)^wheat thins original \[Nabisco\]"#),
            ("strawberry kiwi chobani", #"^Strawberry Kiwi \[Chobani\]"#),
            ("chobani strawberry kiwi", #"^Strawberry Kiwi \[Chobani\]"#),
            ("trader joes chocolate bar", #"^Chocolate Bar \[Trader Joe's\]"#),
            ("chocolate bar trader joes", #"^Chocolate Bar \[Trader Joe's\]"#),
        ])
    func anywhere(query: String, pattern: String) {
        let names = catalog.names(query, 3)
        #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
    }

    @Test(
        "a brand half typed after the food finds the brand's food",
        arguments: [
            ("organic peanut butter smuc", #"(?i)^organic peanut butter \[Smucker"#),
            ("berry fruitful kas", #"(?i)^berry fruitful \[Kashi\]"#),
            ("roasted chestnuts gall", #"^Roasted Chestnuts \[Galli\]"#),
        ])
    func halfTyped(query: String, pattern: String) {
        let names = catalog.names(query, 3)
        #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
    }

    @Test(
        "a misspelt brand finds the brand's food, however few foods it has",
        arguments: [
            ("sracy pita chips sea salt", #"^Pita Chips Sea Salt \[Stacy's\]"#),
            ("pita chips sea salt sracy", #"^Pita Chips Sea Salt \[Stacy's\]"#),
            ("gali roasted chestnuts", #"^Roasted Chestnuts \[Galli\]"#),
            ("perue chicken tenders", #"^Chicken Tenders \[Perdue\]"#),
            ("triscuiits rosemary olive oil", #"(?i)^rosemary & olive oil \[triscuit"#),
            ("cobani strawberry kiwi", #"^Strawberry Kiwi \[Chobani\]"#),
            ("membermark creamy almond butter", #"(?i)^creamy almond butter \[Member's Mark\]"#),
            ("organicvalley reduced fat milk", #"(?i)reduced fat milk \[Organic Valley\]"#),
        ])
    func misspelt(query: String, pattern: String) {
        let names = catalog.names(query, 3)
        #expect(names.first.map { matches(pattern, $0) } == true, "\(query): \(names.joined(separator: " | "))")
    }

    @Test("a word with others after it is corrected to whole words, and two typos lose to a missing space")
    func spelling() {
        // Not the start of "perfect" or "pere": nothing is half typed before "chicken tenders".
        #expect(catalog.searchCatalog("perue chicken tenders", known: [:]).fixes["perue"]?.contains("perdue") == true)
        // One letter from "Triscuits", which few labels say, and so Triscuit.
        #expect(catalog.searchCatalog("triscuiits rosemary", known: [:]).fixes["triscuiits"] == ["triscuit"])
        // Not "organically", two letters away: labels write the two words, so they're searched as
        // typed apart. Last in a search it may be half typed, and is a missing space to correct.
        #expect(catalog.searchCatalog("organicvalley milk", known: [:]).text == "organic valley milk")
        #expect(catalog.searchCatalog("milk organicvalley", known: [:]).fixes["organicvalley"] == ["organic valle"])
        // The last word may still be half typed: the start of chicken.
        #expect(catalog.searchCatalog("grilled chikc", known: [:]).fixes["chikc"] == ["chic"])
    }

    @Test("words that aren't a brand's stay a food's")
    func notBrands() {
        // A whole word isn't the start of a chain's name: "apple" isn't Applebee's.
        for query in ["apple cinnamon oats", "cinnamon oats apple", "apple pie"] {
            #expect(catalog.searchCatalog(query, known: [:]).brand.isEmpty, "\(query)")
        }
        // A chain half typed at the end still is one.
        #expect(catalog.searchCatalog("big mac mcdon", known: [:]).brand == ["mcdon"])
        #expect(catalog.top("big mac mcdon", 1) == ["McDONALD'S, BIG MAC"])
        // Plain foods stay ahead of a packaged food that happens to be listed under one of the words.
        for query in ["chicken breast", "whole milk", "brown rice", "olive oil"] {
            #expect(catalog.search(query).first?.food.source == .usda, "\(query)")
        }
    }
}

/// Names labels write as one word and as two: Red Bull and Redbull, popcorn and pop corn.
@Suite("One word or two", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"))
struct CompoundTests {
    let catalog = Catalogs.both

    @Test(
        "a name typed as one word and typed as two is one search",
        arguments: [
            ("redbull", "red bull"), ("kitkat", "kit kat"), ("kit-kat", "kitkat"), ("hotdog", "hot dog"), ("hotdogs", "hot dogs"),
            ("popcorn", "pop corn"), ("icecream", "ice cream"), ("peanutbutter", "peanut butter"), ("oatmilk", "oat milk"),
            ("crispbread", "crisp bread"), ("lowfat cottage cheese", "low fat cottage cheese"),
            ("redbull sugarfree", "red bull sugar free"), ("vanilla milkshake", "vanilla milk shake"),
        ])
    func oneSearch(joined: String, apart: String) {
        let one = catalog.search(joined)
        let two = catalog.search(apart)
        #expect(
            one.count > 5 && one.map(\.food.id) == two.map(\.food.id),
            "\(joined): \(one.prefix(3).map(\.food.title)) | \(two.prefix(3).map(\.food.title))")
    }

    @Test(
        "it's read the way most labels write it, and finds the foods written the other way too",
        arguments: [
            ("redbull", "red bull", "(?i)red bull", "(?i)redbull"),
            ("red bull energy", "red bull energy", "(?i)red bull", "(?i)redbull"),
            ("kit kat", "kitkat", "(?i)kitkat", "(?i)kit.kat"),
            ("pop corn", "popcorn", "(?i)popcorn", "(?i)pop corn"),
            ("hotdog buns", "hot dog buns", "(?i)hot dog", "(?i)hotdog"),
            ("oatmilk", "oat milk", "(?i)oat.milk", "(?i)oatmilk"),
        ])
    func bothWays(typed: String, read: String, usual: String, other: String) {
        #expect(catalog.searchCatalog(typed, known: [:]).text == read)
        let titles = catalog.search(typed).map(\.food.title)
        #expect(titles.contains { matches(usual, $0) }, "\(typed): none written the usual way in \(titles.prefix(5))")
        #expect(titles.contains { matches(other, $0) }, "\(typed): none written the other way in \(titles.prefix(5))")
    }

    @Test("a word that is a food or a brand of its own stays one word")
    func ownNames() {
        // Butterball is turkey; "butter balls" are sweets. Buttercup, on 19 labels, is left alone.
        for query in ["butterball", "buttercup squash", "strawberry", "chicken", "sandwich", "goldfish"] {
            let found = catalog.searchCatalog(query, known: [:])
            #expect(found.text == query && found.also.isEmpty, "\(query): \(found.text) \(found.also)")
        }
        for match in catalog.search("butterball").prefix(5) { #expect(matches("(?i)butterball", match.food.title), "\(match.food.title)") }
        // Typed apart, the one word is still searched: it can only add the foods that have it.
        #expect(catalog.searchCatalog("butter ball turkey", known: [:]).also["ball"] == ["butterball"])
        #expect(catalog.search("butter ball turkey").first.map { matches("(?i)butterball", $0.food.title) } == true)
        #expect(catalog.search("butter finger").prefix(3).contains { matches("(?i)butterfinger", $0.food.title) })
    }

    @Test("a brand of one word typed alone lists its foods, the most scanned first")
    func alone() {
        for brand in ["chobani", "fage", "kind"] {
            let found = catalog.search(brand, limit: 6)
            #expect(found.count == 6 && found.allSatisfy { matches("(?i)\(brand)", $0.food.brand ?? $0.food.name) }, "\(brand)")
            let scanned = found.map(\.food.popularity)
            #expect(scanned == scanned.sorted(by: >) && (scanned.first ?? 0) >= 1.5, "\(brand): \(scanned)")
        }
        // Half typed too, where no plain food starts as typed, and typed as one word.
        #expect(catalog.search("chob").first?.food.brand?.lowercased() == "chobani")
        #expect(catalog.search("redb").first.map { matches("(?i)red ?bull", $0.food.brand ?? "") } == true)
        // A chain's items as USDA analysed them come before what shops sell under its name.
        #expect(catalog.top("wendys", 1).first.map { matches("^WENDY'S, ", $0) } == true)
        // A plain food by the word comes first, whatever is listed under it as a brand, and a
        // word corrected into one isn't a brand typed.
        #expect(catalog.top("cod", 1).first.map { matches("^Fish, cod", $0) } == true)
        #expect(catalog.top("yogrt", 1).first.map { matches("^Yogurt, ", $0) } == true)
        // Half typed, one of the most scanned brands comes before a plain food that starts the
        // same, unless the letters are on their way to an everyday food.
        #expect(catalog.search("her").first?.food.brand == "Hershey's")
        #expect(catalog.search("trop").first?.food.brand == "Tropicana")
        #expect(catalog.top("cel", 1).first.map { matches("^Celery", $0) } == true)
        // A brand of several words is begun by its first, and by a letter of its next.
        #expect(catalog.search("halo").first?.food.brand?.lowercased() == "halo top")
        #expect(catalog.search("mountain d").first?.food.brand?.lowercased() == "mountain dew")
        // A name the catalogs know isn't corrected, typed whole or as far as it's typed; a
        // typo still is, though a brand sold elsewhere starts the same.
        for name in ["skittles", "triscuit", "cholula", "halo", "skip"] { #expect(catalog.searchCatalog(name, known: [:]).fixes.isEmpty, "\(name)") }
        #expect(catalog.searchCatalog("bred", known: [:]).fixes["bred"] != nil)
        #expect(catalog.searchCatalog("protien bar", known: [:]).fixes["protien"] == ["protein"])
        #expect(catalog.search("cholu").first?.food.brand == "Cholula")
        // The brands that go on from a word with the letter typed after it are found among the
        // word's own foods, and offered; a small word typed last is such a letter.
        let begun = catalog.search("swiss m", limit: 60)
        #expect(begun.prefix(3).contains { $0.food.brand?.lowercased().hasPrefix("swiss miss") == true })
        #expect(FoodCompletions.suggest("swiss m", from: begun).first == "swiss miss")
        #expect(readQuery("chips a").letter == ["chips", "a"] && readQuery("2 a").letter.isEmpty)
        #expect(FoodCompletions.suggest("chips a", from: catalog.search("chips a", limit: 60)).first == "chips ahoy")
    }

    @Test("words still being typed, short halves and everyday pairs are searched as typed")
    func asTyped() {
        // "pea che" is on its way to pea cheese as much as to peaches, and "peache" is no word yet.
        for query in ["pea ch", "pea che", "chicken breast", "greek yogurt", "olive oil", "2% milk"] {
            let found = catalog.searchCatalog(query, known: [:])
            #expect(found.text == plain(query) && found.also.isEmpty, "\(query): \(found.text) \(found.also)")
        }
        // A last word on its way to an everyday food or a brand people scan is read as that one's
        // names too: "pop cor" already finds popcorn, "red bul" Redbull.
        #expect(catalog.searchCatalog("pop cor", known: [:]).also["cor"]?.contains("popcorn") == true)
        #expect(catalog.searchCatalog("red bul", known: [:]).also["bul"]?.contains("redbull") == true)
        // A brand half typed after the food isn't divided: "popcor" is on its way to PopCorners.
        #expect(catalog.searchCatalog("sea salt popcor", known: [:]).text == "sea salt popcor")
        // A word no label has is the two words labels write, unless it's last and may be half typed.
        #expect(catalog.searchCatalog("wellsleyfarms purified water", known: [:]).text == "wellsley farms purified water")
        #expect(catalog.searchCatalog("purified water wellsleyfarms", known: [:]).text == "purified water wellsleyfarms")
        // Amounts and sizes around a name are kept as typed.
        #expect(catalog.searchCatalog("2 hotdogs", known: [:]).text == "2 hot dogs")
        #expect(catalog.searchCatalog("14\" pop corn", known: [:]).text == "14\" popcorn")
    }

    @Test("the person's own food is found written either way")
    func personal() {
        let own = Food(id: "custom:shake", name: "Morning Milk Shake", basis: .ml, nutrients: .zero, source: .custom)
        let found = catalog.search("morning milkshake", personal: [PersonalFood(food: own, score: 1)])
        #expect(found.first?.food.id == own.id && found.first?.personal == true)
    }
}
