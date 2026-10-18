import Foundation
import Testing

@testable import SystemCore

/// The label reading SystemCore ships to the apps. FoodDatabase's tests cover it against real
/// catalog rows; these pin the parsing rules themselves.
@Suite("Supplement labels")
struct SupplementParsingTests {
    func serving(_ text: String) -> String? { SupplementServing.parse(text).map { "\($0.count) \($0.unit)" } }

    @Test func spoonsAreNotTablets() {
        #expect(serving("Serving Size: 1 Tablespoon (15 mL)") == "1.0 tbsp")
        #expect(serving("2 Tablespoon(s)") == "2.0 tbsp")
        #expect(serving("1 Tbsp") == "1.0 tbsp")
        #expect(serving("1/2 Teaspoon(s)") == "0.5 tsp")
        #expect(serving("2 Tab(s)") == "2.0 tablet")
        #expect(serving("Serving Size: 1 Tablet") == "1.0 tablet")
        #expect(serving("2 Softgels") == "2.0 softgel")
        #expect(serving("10 Gram(s) [1 scoop]") == "1.0 scoop")
        #expect(SupplementForm(unit: SupplementServing.unit(words: "Tablespoons")) == .powder)
        #expect(SupplementServing.label(2, "tbsp") == "2 tbsp")
    }

    @Test func aMacroLineWithNoUnitIsGrams() throws {
        let protein = try #require(SupplementIngredients.read(name: "Protein", amount: 25, unit: ""))
        #expect(protein.key == "protein" && protein.value == 25)
        let carbs = try #require(SupplementIngredients.read(name: "Total Carbohydrates", amount: 2, unit: ""))
        #expect(carbs.key == "carbs" && carbs.value == 2)
        #expect(SupplementIngredients.read(name: "Calories", amount: 120, unit: "")?.value == 120)
        // Only macros: a bare number for a vitamin could be anything.
        #expect(SupplementIngredients.read(name: "Vitamin C", amount: 100, unit: "") == nil)
        // A misread is still a misread.
        #expect(SupplementIngredients.read(name: "Total Fat", amount: 1250, unit: "") == nil)

        let facts = SupplementFacts(
            id: "dsld:1", name: "Whey", unit: "scoop",
            ingredients: [
                SupplementIngredient(name: "Calories", amount: 120, unit: ""),
                SupplementIngredient(name: "Protein", amount: 25, unit: ""),
                SupplementIngredient(name: "Total Carbohydrates", amount: 2, unit: ""),
            ], source: .dsld)
        let nutrients = try #require(facts.nutrients)
        #expect(nutrients.kcal == 120 && nutrients.protein == 25 && nutrients.carbs == 2)
        #expect(facts.tracked.ingredients.count == 3)
    }
}
