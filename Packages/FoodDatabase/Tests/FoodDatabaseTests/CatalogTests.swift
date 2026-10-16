import Foundation
import SystemCore
import Testing
@testable import FoodDatabase

@Suite("Catalog rows and files")
struct CatalogTests {
    static let order = ["calories", "protein", "carbs", "fat", "fiber", "sodium", "sugar", "saturatedFat", "cholesterol", "calcium",
                        "iron", "transFat", "potassium", "addedSugar", "vitaminD", "vitaminC", "vitaminA"]

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
        let data = #"{"basis":"g","nutrients":{"calories":32.0,"protein":0.67,"carbs":7.68,"fat":0.3,"fiber":2.0,"sodium":1.0,"#
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
        #expect(JSONValue.parse("[80.6, -0.5, 1e3, 0.0001, 12345678901234567890, 3.14159265358979]")
            == .array([.number(80.6), .number(-0.5), .number(1000), .number(0.0001), .number(1.2345678901234567e19), .number(3.14159265358979)]))
        #expect(JSONValue.parse("[true,false,null,\"a\\nb\"]") == .array([.bool(true), .bool(false), .null, .string("a\nb")]))
        #expect(JSONValue.parse("[1,]") == nil)
        #expect(JSONValue.parse("-") == nil)
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
        #expect(info.version.hasPrefix("usda-v3-0fe8ae486a2c-"), "SR Legacy, packed rows")
        #expect(info.license == "CC0-1.0")
        #expect(info.foods == 7793)
        #expect(info.attribution.contains("USDA"))
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
        #expect(food.source == .off && food.popularity == 8.13)
        #expect(food.nutrients == Nutrients(kcal: 80.6, protein: 7.3, carbs: 6.1, fat: 12, sugar: 4, saturatedFat: 7.15, sodium: 100))
        #expect(food.extras == ["addedSugar": 0])
        // Every id form finds it: the canonical one and the ones earlier builds stored.
        for id in ["off:06111246721261", "off:6111246721261"] { #expect(catalog.food(id: id) == food, "\(id)") }
        // A stored id with its own zeros ("off:06175634") is the same food as its 14 digits.
        let stored = try #require(catalog.food(id: "off:06175634"))
        #expect(stored.id == "off:00000006175634" && stored.name == "Tartines craquantes à la châtaigne")
        #expect(catalog.food(id: "off:abc") == nil)
        // EAN-8 as printed.
        #expect(catalog.food(barcode: "42104964")?.name == "Ciel 33cl")
        // Every expression a search can build is valid full-text syntax in both catalogs.
        for query in ["chicken breast", #"" OR - NEAR ( *"#, "crème", "rice", "x", "🍕", "Domino's 14\" pizza"] {
            _ = catalog.search(query)
            _ = catalog.candidates(name: query, brand: "Mc'Test")
        }
    }
}
