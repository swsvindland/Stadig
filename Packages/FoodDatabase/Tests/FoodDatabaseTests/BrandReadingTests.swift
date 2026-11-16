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
        // Not "organically", two letters away.
        #expect(catalog.searchCatalog("organicvalley milk", known: [:]).fixes["organicvalley"] == ["organic valle"])
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
