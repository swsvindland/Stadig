import Foundation
import SystemCore
import Testing
@testable import FoodDatabase

@Suite("Implausible packaged foods")
struct PlausibilityTests {
    /// The id is the name and brand, so two brands' foods of one name stay two foods.
    func off(_ name: String, _ basis: FoodBasis = .g, kcal: Double, p: Double, c: Double, f: Double, fiber: Double? = nil,
             brand: String? = nil) -> Food {
        Food(id: "off:\(name)|\(brand ?? "")", name: name, brand: brand, basis: basis,
             nutrients: Nutrients(kcal: kcal, protein: p, carbs: c, fat: f, fiber: fiber), source: .off)
    }

    @Test("numbers that can't be right are caught")
    func caught() {
        // A powder's values on the drink as poured (a real Open Food Facts row).
        #expect(off("Flat White", .ml, kcal: 452, p: 21.8, c: 43.6, f: 19.2, brand: "Nestlé").problem == .drinkTooDense)
        #expect(off("Coca-Cola Classic", .ml, kcal: 176, p: 0, c: 10.6, f: 0).problem == .caloriesDontAddUp)
        // Kilojoules entered as calories: 765 for a cream cheese with 10 g protein and 8 g fat.
        #expect(off("St Moret Ligne & Plaisir 8% Minis", kcal: 765, p: 10, c: 5, f: 8).problem == .caloriesDontAddUp)
        // Per-portion calories beside per-100 g macros.
        #expect(off("Salade Roma", kcal: 62.7, p: 6.9, c: 19.1, f: 6.6, fiber: 2.9).problem == .caloriesDontAddUp)
        // Calories left out, and calories with no macros at all.
        #expect(off("Pain complet", kcal: 0, p: 9, c: 45, f: 3).problem == .caloriesDontAddUp)
        #expect(off("Bottled Spring Water", .ml, kcal: 117.9, p: 0, c: 0, f: 0).problem == .caloriesDontAddUp)
        #expect(off("Mystery", kcal: 300, p: 60, c: 40, f: 20).problem == .macrosOverWeight)
        #expect(off("Mystery", kcal: 950, p: 0, c: 0, f: 100).problem == .tooDense)
    }

    @Test("ordinary foods, oils, syrups, alcohol and sweeteners pass")
    func passes() {
        #expect(off("Extra virgin olive oil", .ml, kcal: 828, p: 0, c: 0, f: 92).isPlausible)
        #expect(off("Sirop d'agave", .ml, kcal: 324, p: 0, c: 77, f: 0.5).isPlausible)
        #expect(off("Coffee mate Hazelnut", .ml, kcal: 233, p: 1, c: 30, f: 12).isPlausible, "a creamer isn't a drink as poured")
        #expect(off("Flat White", .ml, kcal: 55, p: 2, c: 6, f: 2, brand: "Nescafé Dolce Gusto").isPlausible)
        #expect(off("Coca-Cola", .ml, kcal: 42, p: 0, c: 10.6, f: 0).isPlausible)
        #expect(off("Absolut Vodka", .ml, kcal: 221, p: 0, c: 0, f: 0).isPlausible)
        #expect(off("Stevia", kcal: 2, p: 0, c: 99, f: 0).isPlausible)
        // US labels count fibre in the carbs: All-Bran is far below 4 kcal per gram of carbs.
        #expect(off("All-Bran", kcal: 260, p: 14, c: 74, f: 5, fiber: 29).isPlausible)
        #expect(off("Greek yogurt", kcal: 97, p: 9, c: 4, f: 5).isPlausible)
        // Curated and personal foods aren't second-guessed.
        let vodka = Food(id: "usda:174832", name: "Alcoholic beverage, distilled, vodka, 80 proof", basis: .g,
                         nutrients: Nutrients(kcal: 231, protein: 0, carbs: 0, fat: 0), source: .usda)
        #expect(vodka.isPlausible)
        let own = Food(id: "custom:x", name: "Flat white", basis: .ml, nutrients: Nutrients(kcal: 400, protein: 20, carbs: 40, fat: 18),
                       source: .custom)
        #expect(own.isPlausible)
    }

    @Test("an implausible food ranks below a plausible one that matches as well")
    func ranksBelow() {
        let powder = off("Flat White", .ml, kcal: 452, p: 21.8, c: 43.6, f: 19.2, brand: "Nestlé")
        let poured = off("Flat White", .ml, kcal: 55, p: 2, c: 6, f: 2, brand: "Nescafé Dolce Gusto")
        #expect(powder.id != poured.id)
        let ranked = rankSearch("flat white", [powder, poured])
        #expect(ranked.map(\.food.id) == [poured.id, powder.id])
        #expect(ranked.map(\.food.brand) == ["Nescafé Dolce Gusto", "Nestlé"])
    }
}

@Suite("Implausible packaged foods in the catalog", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"))
struct CatalogPlausibilityTests {
    let catalog = Catalogs.both

    @Test("real rows with impossible numbers are caught, and searches lead with plausible foods")
    func catalogRows() throws {
        // Nestlé's flat white: a powder's 452 kcal per 100 ml on the drink as poured.
        let powder = try #require(catalog.food(barcode: "7613036675680"))
        #expect(powder.problem == .drinkTooDense)
        #expect(catalog.search("coca cola", limit: 5).allSatisfy { $0.food.isPlausible })
        // A flat white, not the "Flat White" brand's coffee chocolate.
        let first = try #require(catalog.search("flat white").first)
        #expect(first.food.name.lowercased() == "flat white", "\(first.food.name) [\(first.food.brand ?? "")]")
    }
}
