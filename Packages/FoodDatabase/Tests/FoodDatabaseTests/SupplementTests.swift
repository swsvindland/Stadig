import Foundation
import SQLite3
import SystemCore
import Testing

@testable import FoodDatabase

@Suite("Supplements")
struct SupplementTests {
    static let catalogURL = Catalogs.package.appending(path: "../../Apps/MacroTrack/Catalogs/supplements.db").standardizedFileURL
    static var hasCatalog: Bool { FileManager.default.fileExists(atPath: catalogURL.path) }

    /// A supplements.db laid out as `Scripts/build-supplement-catalog.py` writes one, rows in DSLD id
    /// order, each label a magnesium capsule.
    static func catalog(_ labels: [(id: Int, name: String, market: Bool)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "supplements-\(UUID().uuidString).db")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let db = handle else { throw SQLiteError(code: 0, message: "cannot create \(url.path)") }
        defer { sqlite3_close(db) }
        func run(_ sql: String) throws {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SQLiteError(code: 1, message: String(cString: sqlite3_errmsg(db))) }
        }
        try run(
            """
            CREATE TABLE supplements (id INTEGER PRIMARY KEY, name TEXT NOT NULL, brand TEXT NOT NULL, barcode INTEGER, serving TEXT NOT NULL,
                                      market INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO catalog_meta VALUES ('version', 'dsld-test');
            BEGIN;
            """)
        for label in labels.sorted(by: { $0.id < $1.id }) {
            try run(
                "INSERT INTO supplements VALUES (\(label.id), '\(label.name)', 'Brand', NULL, '1 Capsule(s)', \(label.market ? 1 : 0), "
                    + #"'[["Magnesium",200,"mg"]]')"#)
        }
        try run(
            """
            COMMIT;
            CREATE VIRTUAL TABLE supplement_search USING fts5(name, brand, content='supplements', content_rowid='id',
                                                              tokenize='unicode61 remove_diacritics 2', prefix='2 3', columnsize=0);
            INSERT INTO supplement_search(supplement_search) VALUES ('rebuild');
            """)
        return url
    }

    func value(_ name: String, _ amount: Double, _ unit: String) -> (String, Double)? {
        SupplementIngredients.read(name: name, amount: amount, unit: unit).map { ($0.key, $0.value) }
    }

    @Test func ingredientNamesAndUnitsBecomeNutrients() throws {
        #expect(value("Vitamin D3", 1000, "IU")! == ("vitaminD", 25))
        #expect(value("Vitamin D (as cholecalciferol)", 50, "mcg")! == ("vitaminD", 50))
        #expect(value("Folic Acid", 400, "mcg")! == ("folate", 680))
        #expect(value("Folate", 680, "mcg DFE")! == ("folate", 680))
        #expect(value("Vitamin E (as d-alpha tocopherol)", 30, "IU")!.1 == 30 * 0.67)
        #expect(value("Vitamin A", 5000, "IU")! == ("vitaminA", 1500))
        #expect(value("Beta-Carotene", 3000, "mcg")! == ("vitaminA", 1500))
        #expect(value("Eicosapentaenoic Acid", 650, "mg")! == ("epa", 0.65))
        #expect(value("Caffeine Anhydrous", 200, "mg")! == ("caffeine", 200))
        #expect(value("Natural Caffeine (from green coffee bean)", 150, "mg")! == ("caffeine", 150))
        #expect(value("Calories", 25, "Calorie(s)")! == ("kcal", 25))
        #expect(value("Total Carbohydrates", 2, "Gram(s)")! == ("carbs", 2))
        #expect(value("Vitamin B12 (as methylcobalamin)", 500, "mcg")! == ("vitaminB12", 500))
        #expect(value("Vitamin B-6", 2, "mg")! == ("vitaminB6", 2))
        #expect(value("Magnesium (as magnesium glycinate)", 0.2, "g")! == ("magnesium", 200))
        // Named for what it carries, not the salt it's carried in.
        #expect(value("Vitamin C (as calcium ascorbate)", 500, "mg")! == ("vitaminC", 500))
        #expect(value("Calcium (as calcium carbonate)", 600, "mg")! == ("calcium", 600))
        // Not followed, or not convertible.
        #expect(value("Calories from Fat", 20, "Calorie(s)") == nil)
        #expect(value("Ashwagandha", 600, "mg") == nil)
        #expect(value("Melatonin", 3, "mg") == nil)
        #expect(value("Vitamin C", 100, "%") == nil)
        #expect(value("Bromelain", 500, "GDU") == nil)
        #expect(value("Choline Bitartrate", 100, "mg") == nil)
        #expect(value("Caffeine", 90_000, "mg") == nil)
    }

    @Test func servingsAreCountedInWhatPeopleTake() {
        func serving(_ text: String) -> String? { SupplementServing.parse(text).map { "\($0.count) \($0.unit)" } }
        #expect(serving("2 Softgel(s)") == "2.0 softgel")
        #expect(serving("1 Vegetarian Capsule(s)") == "1.0 capsule")
        #expect(serving("10 Gram(s) [1 scoop]") == "1.0 scoop")
        #expect(serving("12.5 Gram(s) [1-2 scoops]") == "12.5 g")
        #expect(serving("1 mL [20-30 drops]") == "1.0 ml")
        #expect(serving("0.25 mL [5 drops]") == "5.0 drop")
        #expect(serving("Serving Size: 2 Gummies") == "2.0 gummy")
        #expect(serving("Serving Size 1 Scoop (6.5 g)") == "1.0 scoop")
        #expect(serving("1/2 Teaspoon(s)") == "0.5 tsp")
        #expect(serving("2 Caplet(s)") == "2.0 caplet")
        #expect(serving("Serving Size: Two Softgels") == "2.0 softgel")
        #expect(SupplementServing.label(2, "softgel") == "2 softgels")
        #expect(SupplementServing.label(1, "gummy") == "1 gummy")
        #expect(SupplementServing.label(3, "gummy") == "3 gummies")
        #expect(SupplementServing.label(10, "g") == "10 g")
    }

    @Test func fishOilCountsItsOmega3sOnce() {
        let total = SupplementFacts(
            id: "t", name: "Fish Oil", servingCount: 2, unit: "softgel",
            ingredients: [
                SupplementIngredient(name: "Calories", amount: 20, unit: "Calorie(s)"),
                SupplementIngredient(name: "Total Fat", amount: 2, unit: "Gram(s)"),
                SupplementIngredient(name: "Fish Oil concentrate", amount: 2400, unit: "mg"),
                SupplementIngredient(name: "Total Omega-3 Fatty Acids", amount: 720, unit: "mg"),
                SupplementIngredient(name: "Eicosapentaenoic Acid", amount: 432, unit: "mg"),
                SupplementIngredient(name: "Docosahexaenoic Acid", amount: 288, unit: "mg"),
            ], source: .dsld)
        #expect(abs(total.amounts["omega3"]! - 0.72) < 1e-9)
        #expect(total.nutrients?.kcal == 20)
        #expect(total.nutrients?.fat == 2)
        #expect(total.others.map(\.name) == ["Fish Oil concentrate", "Eicosapentaenoic Acid", "Docosahexaenoic Acid"])
        let parts = SupplementFacts(
            id: "p", name: "Fish Oil",
            ingredients: [
                SupplementIngredient(name: "EPA (Eicosapentaenoic Acid)", amount: 650, unit: "mg"),
                SupplementIngredient(name: "DHA (Docosahexaenoic Acid)", amount: 450, unit: "mg"),
            ], source: .dsld)
        #expect(abs(parts.amounts["omega3"]! - 1.1) < 1e-9)
        #expect(parts.nutrients == nil)
    }

    @Test func aFolateLineInDFEStandsForItsFolicAcid() {
        let facts = SupplementFacts(
            id: "m", name: "Multi",
            ingredients: [
                SupplementIngredient(name: "Folate", amount: 680, unit: "mcg DFE"),
                SupplementIngredient(name: "Folic Acid", amount: 400, unit: "mcg"),
            ], source: .dsld)
        #expect(facts.amounts["folate"] == 680)
    }

    @Test func aMultivitaminPanelIsReadLineByLine() throws {
        let lines = [
            "Centrum Adults", "Supplement Facts", "Serving Size 1 Tablet", "Amount Per Serving % Daily Value",
            "Vitamin A (as retinyl acetate and 29% as beta-carotene) 750 mcg 83%", "Vitamin C (as ascorbic acid) 90 mg 100%",
            "Vitamin D3 (as cholecalciferol) 25 mcg (1,000 IU) 125%", "Vitamin E (as dl-alpha tocopheryl acetate) 22.5 mg 150%",
            "Vitamin B12", "(as cyanocobalamin) 25 mcg 1,042%", "Folate 400 mcg DFE (240 mcg folic acid) 100%",
            "Calcium (as calcium carbonate) 200 mg 15%", "Iron (as ferrous fumarate) 8 mg 44%", "Zinc (as zinc oxide) 11 mg 100%",
            "Lutein 250 mcg †", "† Daily Value not established.", "Other ingredients: Calcium Carbonate, Gelatin.",
        ]
        let facts = try #require(SupplementLabel.parse(lines: lines))
        #expect(facts.servingLabel == "1 tablet")
        // Lutein isn't a nutrient Stadig Macro tracks, so it isn't kept.
        #expect(facts.ingredients.count == 9)
        let amounts = facts.amounts
        #expect(amounts["vitaminA"] == 750)
        #expect(amounts["vitaminC"] == 90)
        #expect(amounts["vitaminD"] == 25)
        #expect(amounts["vitaminE"] == 22.5)
        #expect(amounts["vitaminB12"] == 25)
        #expect(amounts["folate"] == 400)
        #expect(amounts["calcium"] == 200)
        #expect(amounts["iron"] == 8)
        #expect(amounts["zinc"] == 11)
        #expect(facts.ingredients.last?.name == "Zinc (as zinc oxide)")
        #expect(facts.ingredients.first { $0.key == "vitaminB12" }?.name == "Vitamin B12 (as cyanocobalamin)")
    }

    @Test func preWorkoutAndSleepPanels() throws {
        let preWorkout = try #require(
            SupplementLabel.parse(lines: [
                "SUPPLEMENT FACTS", "Serving Size 1 Scoop (10.5 g)", "Servings Per Container 30", "Calories 5",
                "Total Carbohydrate <1 g <1%*", "Niacin (as niacinamide) 30 mg 188%", "Vitamin B12 (as methylcobalamin) 250 mcg 10,417%",
                "L-Citrulline 6 g †", "Beta-Alanine 3.2 g †", "Caffeine Anhydrous 300 mg †", "L-Theanine 200 mg †",
                "*Percent Daily Values are based on a 2,000 calorie diet.",
            ]))
        #expect(preWorkout.servingLabel == "1 scoop")
        #expect(preWorkout.amounts["caffeine"] == 300)
        #expect(preWorkout.amounts["niacin"] == 30)
        #expect(preWorkout.nutrients?.kcal == 5)
        #expect(preWorkout.nutrients?.carbs == 0.5)
        // The amino acids aren't tracked, so only the nutrients are kept.
        #expect(
            preWorkout.ingredients.map(\.name) == [
                "Calories", "Total Carbohydrate", "Niacin (as niacinamide)",
                "Vitamin B12 (as methylcobalamin)", "Caffeine Anhydrous",
            ])

        let sleep = try #require(
            SupplementLabel.parse(lines: [
                "Supplement Facts", "Serving Size: 2 Gummies", "Amount Per Serving", "Calories 15", "Total Sugars 3 g",
                "Includes 3g Added Sugars 6%", "Magnesium (as magnesium citrate) 50 mg 12%", "Melatonin 3 mg †", "L-Theanine 100 mg †",
                "Other Ingredients: Glucose Syrup, Sugar, Pectin.",
            ]))
        #expect(sleep.servingLabel == "2 gummies")
        #expect(sleep.amounts["magnesium"] == 50)
        #expect(sleep.nutrients?.kcal == 15)
        #expect(!sleep.ingredients.contains { $0.name == "Melatonin" })
        // Not a panel at all.
        #expect(SupplementLabel.parse(lines: ["Nature Made", "Fish Oil", "Heart health support"]) == nil)
    }

    @Test("search ranks every label that matches, so the newest ones on the market come first")
    func searchRanksEveryMatch() throws {
        // 500 old labels off the market, oldest first as DSLD numbers them, then the newest, still sold.
        let old = (1...500).map { (id: $0, name: "Magnesium Oxide \($0)", market: false) }
        let url = try Self.catalog(old + [(id: 341_521, name: "Magnesium Glycinate", market: true)])
        defer { try? FileManager.default.removeItem(at: url) }
        let catalog = try SupplementCatalog(url: url)
        #expect(catalog.count == 501)
        let found = catalog.search("magnesium")
        #expect(found.count == 30)
        #expect(found.first?.id == "dsld:341521")
        #expect(catalog.search("magnesium gly").map(\.id) == ["dsld:341521"])
        #expect(catalog.failures == 0)
    }

    @Test(.enabled(if: SupplementTests.hasCatalog, "needs Apps/MacroTrack/Catalogs/supplements.db"))
    func theNIHCatalogFindsLabelsByBarcodeAndName() throws {
        let url = Self.catalogURL
        let catalog = try SupplementCatalog(url: url)
        #expect(catalog.count > 100_000)
        // Nature Made Omega-3 Fish Oil 1200 mg, scanned as its UPC-A.
        let fish = try #require(catalog.supplement(barcode: "031604010539"))
        #expect(fish.brand == "Nature Made")
        #expect(fish.unit == "softgel")
        #expect((fish.amounts["omega3"] ?? 0) > 0.5)
        // The catalog keeps only tracked lines: no "Fish Oil concentrate" or cholesterol.
        #expect(fish.ingredients.allSatisfy(\.isTracked) && !fish.ingredients.contains { $0.name.contains("concentrate") })
        #expect(catalog.supplement(id: fish.id)?.name == fish.name)
        let found = catalog.search("nature made fish oil")
        #expect(found.contains { $0.brand == "Nature Made" && $0.name.localizedCaseInsensitiveContains("fish oil") })
        #expect(catalog.search("melatonin").count >= 10)
        #expect(catalog.search("x").isEmpty)
        // Labels are in DSLD id order, so ranking only the first matches would leave out the newer ones.
        var cutoff: Int64 = 0
        try SQLiteConnection(url: url).query(#"SELECT rowid FROM supplement_search WHERE supplement_search MATCH '"magnesium"*' LIMIT 1 OFFSET 399"#)
        {
            cutoff = $0.int(0)
        }
        #expect(catalog.search("magnesium").contains { (Int64($0.id.dropFirst(5)) ?? 0) > cutoff })
        #expect(catalog.failures == 0)
    }
}
