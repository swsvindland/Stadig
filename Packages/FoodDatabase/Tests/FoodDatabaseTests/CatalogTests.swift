import Foundation
import Synchronization
import SystemCore
import Testing

@testable import FoodDatabase

@Suite("Catalog rows and files")
struct CatalogTests {
    static let order = [
        "calories", "protein", "carbs", "fat", "fiber", "sodium", "sugar", "saturatedFat", "cholesterol", "calcium",
        "iron", "transFat", "potassium", "addedSugar", "vitaminD", "vitaminC", "vitaminA",
    ]

    @Test("version 3 rows keep values in the catalog's nutrient order, null where unknown")
    func packedRow() throws {
        let data = #"["g",[97,8,9.4,3,0,0,9.4,0,null,250,null,null,null,10],[["80g",80],["1 pot (125 g)",125]]]"#
        let row = try #require(RowData(data: data, order: Self.order))
        #expect(row.basis == .g)
        #expect(row.nutrients == Nutrients(kcal: 97, protein: 8, carbs: 9.4, fat: 3, fiber: 0, sugar: 9.4, saturatedFat: 0, sodium: 0))
        #expect(row.extras == ["calcium": 250, "addedSugar": 10])
        #expect(row.portions == [Portion(label: "80g", amount: 80), Portion(label: "1 pot (125 g)", amount: 125)])
        // Fiber and sodium unknown, trailing values left off, no portions.
        let drink = try #require(RowData(data: #"["ml",[0,0,0,0,null,52,0,0]]"#, order: Self.order))
        #expect(drink.basis == .ml)
        #expect(drink.nutrients.fiber == nil && drink.nutrients.sodium == 52 && drink.nutrients.sugar == 0)
        #expect(drink.portions.isEmpty && drink.extras.isEmpty)
    }

    @Test("version 2 rows keep an object, with escapes and unicode in labels")
    func objectRow() throws {
        let data =
            #"{"basis":"g","nutrients":{"calories":32.0,"protein":0.67,"carbs":7.68,"fat":0.3,"fiber":2.0,"sodium":1.0,"#
            + #""sugar":4.89,"vitaminC":58.8,"caffeine":0.0,"iron":null},"portions":[{"label":"1 large (1-3/8\" dia)","amount":18.0},"#
            + #"{"label":"1 tasse à café 🍓","amount":1e2}]}"#
        let row = try #require(RowData(data: data, order: nil))
        #expect(row.nutrients == Nutrients(kcal: 32, protein: 0.67, carbs: 7.68, fat: 0.3, fiber: 2, sugar: 4.89, sodium: 1))
        #expect(row.extras == ["vitaminC": 58.8, "caffeine": 0])
        #expect(row.portions == [Portion(label: "1 large (1-3/8\" dia)", amount: 18), Portion(label: "1 tasse à café 🍓", amount: 100)])
        #expect(RowData(data: "{\"basis\":\"g\"}", order: nil) == nil)
        #expect(RowData(data: "[\"g\",[1,2", order: Self.order) == nil)
        #expect(RowData(data: "[\"cups\",[1,2,3,4]]", order: Self.order) == nil, "an unknown basis isn't guessed")
    }

    @Test("numbers parse exactly as JSON writes them")
    func numbers() {
        #expect(
            JSONValue.parse("[80.6, -0.5, 1e3, 0.0001, 12345678901234567890, 3.14159265358979]")
                == .array([.number(80.6), .number(-0.5), .number(1000), .number(0.0001), .number(1.2345678901234567e19), .number(3.14159265358979)]))
        #expect(JSONValue.parse("[true,false,null,\"a\\nb\"]") == .array([.bool(true), .bool(false), .null, .string("a\nb")]))
        #expect(JSONValue.parse("[1,]") == nil)
        #expect(JSONValue.parse("-") == nil)
    }

    @Test("broken escapes and cut-off rows are refused or replaced, never a crash")
    func malformed() {
        func row(_ bytes: [UInt8], _ order: [String]?) -> RowData? { bytes.withUnsafeBufferPointer { RowData(data: $0, order: order) } }
        func parse(_ bytes: [UInt8], _ order: [String]?) -> JSONValue? {
            _ = row(bytes, order)
            return bytes.withUnsafeBufferPointer { JSONValue.parse($0) }
        }
        // A high surrogate whose next escape isn't its low half stands alone, as does a lone low one.
        #expect(JSONValue.parse(#"["\uD800\u0041"]"#) == .array([.string("\u{FFFD}A")]))
        #expect(JSONValue.parse(#"["\uD800\uD800x"]"#) == .array([.string("\u{FFFD}\u{FFFD}x")]))
        #expect(JSONValue.parse(#"["\uDC00x", "\uD800"]"#) == .array([.string("\u{FFFD}x"), .string("\u{FFFD}")]))
        #expect(JSONValue.parse(#"["\uD83C\uDF53"]"#) == .array([.string("🍓")]))
        #expect(JSONValue.parse(#"["\uD800\u12"]"#) == nil)
        // Every cut, and every byte swapped for a piece of JSON syntax, in rows of both shapes, each
        // read as its catalog reads it (an object row has no nutrient order).
        let rows: [(json: String, order: [String]?)] = [
            (#"["g",[97,8,9.4,3,null,250],[["1 pot (125 g)",125]]]"#, Self.order),
            (#"{"basis":"g","nutrients":{"calories":32.0,"iron":null},"portions":[{"label":"1 \"x\" \uD83C\uDF53","amount":1e2}]}"#, nil),
        ]
        let syntax = Array(#""\u[]{},:-.eD8"#.utf8)
        for (json, order) in rows {
            let bytes = Array(json.utf8)
            #expect(parse(bytes, order) != nil)
            #expect(row(bytes, order)?.portions.count == 1)
            for end in 0..<bytes.count { #expect(parse(Array(bytes[..<end]), order) == nil) }
            for i in bytes.indices {
                for byte in syntax {
                    var changed = bytes
                    changed[i] = byte
                    _ = parse(changed, order)
                }
            }
        }
    }

    @Test("every expression a search can build is valid full-text syntax")
    func validExpressions() {
        let catalog = FoodCatalog(usda: Catalogs.usdaURL, off: nil, region: "us")
        for query in ["chicken breast", #"" OR - NEAR ( *"#, "crème", "rice", "x", "🍕", "Domino's 14\" pizza", "chiken", "1/2 cup", "a-b c*d"] {
            _ = catalog.search(query)
            _ = catalog.candidates(name: query, brand: "Mc'Test")
        }
        // And every keystroke of the ways a search is read while it's typed: a letter after a food,
        // a name as one word, a chain's item, marks and other scripts' letters.
        let typed = [
            "McDONALD'S, Egg McMUFFIN", "trader joe’s organic ketchup", "hotdog bun 2 oz", "peanutbutter & jelly", "chicken b", "2% milk 1 cup",
            "ｍｉｌｋ ١٢ ß ǅ ﬁ", "a b c d", "s ' ’s & - ( ) % : {brand} NEAR OR AND", "e\u{0301}clair\t\n", "   ",
        ]
        for query in typed {
            let letters = Array(query)
            for count in 0...letters.count {
                let text = String(letters[..<count])
                let found = catalog.search(text, limit: 60)
                _ = FoodCompletions.suggest(text, from: found)
                _ = catalog.candidates(name: text, brand: nil)
            }
        }
        #expect(catalog.failures == 0)
        // A bad one shows up as a failure, not just as nothing found.
        #expect(catalog.catalogs[0].match(#""unclosed"#, limit: 1).isEmpty)
        #expect(catalog.failures == 1)
    }

    @Test("generic foods are found by id as a search found them")
    func byID() throws {
        let catalog = FoodCatalog(usda: Catalogs.usdaURL, off: nil, region: "us")
        let found = catalog.search("chicken", limit: 50).map(\.food)
        #expect(found.count == 50)
        for food in found { #expect(catalog.food(id: food.id) == food, "\(food.id)") }
        #expect(catalog.food(id: "usda:0") == nil && catalog.food(id: "usda:") == nil)
        #expect(catalog.failures == 0)
    }

    @Test("a burst of parallel reads leaves a few connections open, and releasing memory closes all but one")
    func connections() throws {
        final class Count: Sendable {
            let value = Mutex(0)
            func add() { value.withLock { $0 += 1 } }
            var current: Int { value.withLock { $0 } }
        }
        let pool = try ConnectionPool(url: Catalogs.usdaURL, kept: 2)
        let threads = 8
        let entered = Count()
        let done = DispatchGroup()
        for _ in 0..<threads {
            done.enter()
            Thread {
                pool.read { connection in
                    entered.add()
                    // Each holds its connection until all have one, so eight are open at once.
                    for _ in 0..<10_000 where entered.current < threads { usleep(1000) }
                    try connection.query("SELECT count(*) FROM foods") { _ in }
                }
                done.leave()
            }.start()
        }
        done.wait()
        #expect(entered.current == threads)
        #expect(pool.idleCount == 2)
        #expect(pool.failures.load(ordering: .relaxed) == 0)
        pool.trim()
        #expect(pool.idleCount == 1)
        try pool.with { connection in try connection.query("SELECT count(*) FROM foods") { #expect($0.int(0) == 10231) } }
    }

    @Test("generic foods say how processed they are, and which are fermented")
    func processing() throws {
        func first(_ query: String) throws -> Food { try #require(Catalogs.usda.search(query, limit: 1).first?.food, "\(query)") }
        #expect(try first("banana raw").processing == .whole)
        #expect(try first("chicken breast roasted").processing == .whole)
        #expect(try first("olive oil").processing == .culinary)
        #expect(try first("cheddar cheese").processing == .processed)
        #expect(try first("cola").processing == .ultraProcessed)
        #expect(try first("frankfurter").processing == .ultraProcessed)
        #expect(try first("plain greek yogurt").fermented == true)
        #expect(try first("kefir").fermented == true)
        #expect(try first("cheddar cheese").fermented == false, "fermented, but not what eating fermented foods means")
        #expect(try first("frozen yogurt").fermented == false)
        #expect(try first("banana raw").fermented == false)
        // FNDDS's fast food is ultra-processed like SR Legacy's; a dish from a restaurant, or from
        // either, is processed unless its name says otherwise.
        #expect(try first("chicken nuggets fast food").processing == .ultraProcessed)
        #expect(try first("big mac").processing == .ultraProcessed)
        #expect(try first("broccoli restaurant").processing == .processed)
        #expect(try first("black beans restaurant").processing == .processed)
        #expect(try first("pepperoni pizza restaurant").processing == .ultraProcessed)
    }

    @Test("barcodes are keyed as 14 digits")
    func barcodeKeys() {
        #expect(barcodeKey("6111246721261") == "06111246721261")
        #expect(barcodeKey("42104964") == "00000042104964")
        #expect(barcodeKey("") == nil)
        #expect(barcodeKey(nil) == nil)
    }

    @Test("the bundled USDA catalog opens in place with its provenance")
    func usda() throws {
        let catalog = FoodCatalog.standard(region: "us")
        let info = try #require(catalog.sources.first)
        #expect(info.version.hasPrefix("usda-v3-0fe8ae486a2c-dfb06ae7-"), "SR Legacy and FNDDS, packed rows")
        #expect(info.license == "CC0-1.0")
        #expect(info.foods == 10231, "SR Legacy's 7,793 and FNDDS's 2,438 restaurant foods, drinks and dishes")
        #expect(info.attribution.contains("USDA") && info.attribution.contains("FNDDS"))
        let apples = try #require(catalog.search("apples").first)
        #expect(apples.food.name.hasPrefix("Apples, raw"))
        #expect(apples.food.source == .usda && !apples.personal)
        let found = try #require(catalog.food(id: apples.food.id))
        #expect(found == apples.food)
        #expect(catalog.food(id: "usda:0") == nil)
        #expect(catalog.food(id: "custom:1") == nil)
        // Generic foods have no barcodes, and a missing catalog is simply not there.
        let lonely = FoodCatalog(usda: Catalogs.usdaURL, off: URL(fileURLWithPath: "/nonexistent/off.db"))
        #expect(lonely.sources.count == 1 && !lonely.hasPackagedFoods)
        #expect(lonely.food(barcode: "036000291452") == nil)
        #expect(!lonely.search("chicken breast").isEmpty)
        let none = FoodCatalog(usda: nil, off: nil)
        #expect(none.search("chicken").isEmpty && none.sources.isEmpty)
        // A file that isn't a catalog is left out.
        let bogus = FileManager.default.temporaryDirectory.appending(path: "not-a-catalog-\(UUID().uuidString).db")
        try Data("hello".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }
        #expect(FoodCatalog(usda: bogus, off: nil).sources.isEmpty)
    }

    @Test("a USDA row decodes every nutrient and portion")
    func usdaRow() throws {
        let food = try #require(Catalogs.usda.search("strawberries").first { $0.food.name == "Strawberries, raw" }?.food)
        #expect(food.basis == .g)
        #expect(food.nutrients == Nutrients(kcal: 32, protein: 0.67, carbs: 7.68, fat: 0.3, fiber: 2, sugar: 4.89, saturatedFat: 0.015, sodium: 1))
        #expect(food.extras["vitaminC"] == 58.8 && food.extras["caffeine"] == 0 && food.extras.count == 29)
        #expect(food.portions.count == 10 && food.portions[1] == Portion(label: "1 large (1-3/8\" dia)", amount: 18))
        #expect(food.barcode == nil && food.brand == nil)
    }

    @Test("an FNDDS restaurant food offers the amount people usually eat first")
    func fnddsRow() throws {
        let catalog = Catalogs.usda
        let mac = try #require(catalog.food(id: "usda:2706916"))
        #expect(mac.name == "Big Mac (McDonalds)" && mac.source == .usda && mac.brand == nil && mac.basis == .g)
        #expect(
            mac.nutrients == Nutrients(kcal: 261, protein: 11.9, carbs: 21.5, fat: 14.1, fiber: 1.4, sugar: 3.26, saturatedFat: 5.04, sodium: 485))
        // FNDDS's usual amount is a Big Mac, so it leads the Mac Jr listed before it.
        #expect(mac.portions.map(\.label) == ["1 McDonald's Big Mac", "1 MCDonald's Mac Jr", "1 McDonald's Grand Mac"])
        #expect(mac.portions.first?.amount == 205)
        // Five nuggets is no portion of its own, so FNDDS's order stands and the unnamed amount goes.
        let nuggets = try #require(catalog.food(id: "usda:2706093"))
        #expect(nuggets.name == "Chicken nuggets, from fast food")
        #expect(
            nuggets.portions == [
                Portion(label: "1 nugget", amount: 16), Portion(label: "1 chicken bite", amount: 16), Portion(label: "1 cup", amount: 140),
            ])
        let fries = try #require(catalog.food(id: "usda:2709461"))
        #expect(fries.portions.first == Portion(label: "1 small fast food order", amount: 110))
    }

    @Test("an FNDDS food keeps the names of the chains' items it stands for, and only those")
    func fnddsOtherNames() throws {
        let usda = try #require(Catalogs.usda.catalogs.first)
        let found = usda.match("nuggets", limit: 50)
        // "KFC Bites" and "McDonald's Chicken McNuggets", but not the "Wendy's" or "Burger King" alone
        // FNDDS also lists.
        let fast = try #require(found.first { $0.food.id == "usda:2706093" })
        #expect(fast.entry.also.count == 2)
        #expect(fast.entry.also.last.map { $0.text.titled.contains("mcdonald") && $0.head.hasPrefix("mcnugget") } == true)
        // A name finds its food only when the search asks for what it names: "McDonald's Big Mac
        // sauce" is Thousand Island dressing for "big mac sauce", not for "big mac".
        #expect(Catalogs.usda.top("big mac sauce", 1) == ["Thousand Island dressing"])
        #expect(!Catalogs.usda.top("big mac", 5).contains("Thousand Island dressing"))
        #expect(found.first { $0.food.name == "Chicken nuggets, from restaurant" }?.entry.also.isEmpty == true)
        let shake = try #require(usda.match("shake", limit: 50).first { $0.food.id == "usda:2705508" })
        #expect(
            shake.entry.also.map(\.text.titled) == [["wend", "frost", "shake"], ["chocolate", "milkshake"]],
            "Wendy's Frosty Shakes and what it's ordered as; Dairy Queen, Sonic and the rest alone are left out")
        // The names are the catalog's, not the food's: nothing logged or synced carries them.
        #expect(fast.food == Catalogs.usda.food(id: fast.food.id))
        if let off = Catalogs.both.catalogs.last, off.kind == .branded {
            #expect(off.match("frappuccino", limit: 20).allSatisfy { $0.entry.also.isEmpty })
        }
    }

    @Test("the packaged catalog decodes compact rows, ids and barcodes", .enabled(if: Catalogs.hasOFF))
    func packaged() throws {
        let catalog = Catalogs.both
        #expect(catalog.hasPackagedFoods)
        let info = try #require(catalog.sources.last)
        // Rebuilt from each new export, so only the format and rough size are fixed.
        #expect(info.version.hasPrefix("off-v3-"))
        #expect(info.license == "ODbL-1.0")
        #expect(info.foods > 3_000_000)
        #expect(info.attribution.contains("Open Database License"))
        // The most scanned row, whose id the catalog leaves for the app to derive.
        let food = try #require(catalog.food(barcode: "6111246721261"))
        #expect(food.id == "off:06111246721261")
        #expect(food.barcode == "06111246721261")
        #expect(food.name == "Fromage Blanc Nature" && food.brand == "Milky Food Professional")
        #expect(food.source == .off && food.popularity > 5, "scan counts move with each export")
        #expect(food.nutrients == Nutrients(kcal: 80.6, protein: 7.3, carbs: 6.1, fat: 12, sugar: 4, saturatedFat: 7.15, sodium: 100))
        #expect(food.extras == ["addedSugar": 0])
        // Every id form finds it: the canonical one and the ones earlier builds stored.
        for id in ["off:06111246721261", "off:6111246721261"] { #expect(catalog.food(id: id) == food, "\(id)") }
        // A stored id with its own zeros ("off:06175634") is the same food as its 14 digits.
        let stored = try #require(catalog.food(id: "off:06175634"))
        #expect(stored.id == "off:00000006175634" && stored.name == "Tartines craquantes à la châtaigne")
        #expect(catalog.food(id: "off:abc") == nil)
        // EAN-8 as printed.
        #expect(catalog.food(barcode: "42104964")?.name.hasPrefix("Ciel") == true)
        // Every expression a search can build is valid full-text syntax in both catalogs.
        for query in ["chicken breast", #"" OR - NEAR ( *"#, "crème", "rice", "x", "🍕", "Domino's 14\" pizza"] {
            _ = catalog.search(query)
            _ = catalog.candidates(name: query, brand: "Mc'Test")
        }
        #expect(catalog.failures == 0)
    }
}
