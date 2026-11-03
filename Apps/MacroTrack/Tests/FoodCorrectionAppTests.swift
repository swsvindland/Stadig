import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// A catalog food's numbers corrected to its package's: kept under the catalog's id over a
/// relaunch, found by search, logged at the person's numbers however it's logged (Log Again
/// included) while what was eaten stays as logged, taken away again, and one of the person's own
/// foods changed in place.
@MainActor
struct FoodCorrectionAppTests {
    /// Bananas as a package might have them: 120 kcal and 2 g protein per 100 g, where USDA has 89
    /// and 1.09.
    @discardableResult
    func correctBanana(_ model: AppModel) throws -> Food {
        let banana = try #require(model.catalog.food(id: Foods.bananaID))
        let grams = try model.requireUnit(banana, "g")
        let corrected = try #require(banana.correcting(kcal: 120, protein: 2, carbs: 25, fat: 0.5, count: 100, unit: grams))
        return model.saveCorrection(corrected)
    }

    @Test func aCorrectionStandsInForTheCatalogsFoodAndOutlivesARelaunch() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let saved = try correctBanana(model)
        try correctBanana(model)

        #expect(saved.id == Foods.bananaID, "kept under the catalog's id, so favourites and the log still find it")
        #expect(model.food(id: Foods.bananaID)?.nutrients.kcal == 120)
        #expect(model.isCorrected(Foods.bananaID))
        #expect(model.customFoods.isEmpty, "not a food of its own beside the catalog's")
        #expect(environment.store.all(FoodCorrection.self).count == 1, "correcting it again changes the same record")

        let relaunched = environment.model()
        #expect(relaunched.food(id: Foods.bananaID)?.nutrients.kcal == 120)
    }

    @Test func searchListsTheCorrectionOnceAndCountsItAsTheirOwn() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        try correctBanana(model)

        let found = model.corrected(model.catalog.search("bananas raw", personal: model.personal, limit: 20))
        let bananas = found.filter { $0.food.id == Foods.bananaID }
        #expect(bananas.count == 1)
        #expect(bananas.first?.food.nutrients.kcal == 120)
        // Never logged, it's still among the person's own foods, which a search lists first.
        #expect(await eventually(timeout: .seconds(30)) { model.personalFood(Foods.bananaID)?.food.nutrients.kcal == 120 })
    }

    @Test func whatsLoggedAgainTakesTheCorrectedNumbersAndWhatWasEatenStays() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let yesterday = try model.entry(foodID: Foods.bananaID, grams: 150, date: Date().addingTimeInterval(-86400))
        model.log([yesterday])
        #expect(abs(yesterday.nutrients.kcal - 133.5) < 0.01)
        try correctBanana(model)

        let eaten = try #require(model.entries(on: yesterday.day).first { $0.id == yesterday.id })
        #expect(eaten.nutrients == yesterday.nutrients, "what was eaten stays as logged")
        let item = try #require(model.logAgain.first { $0.template.foodID == Foods.bananaID })
        #expect(abs(item.template.nutrients.kcal - 180) < 0.01, "the chip says what a tap logs")

        model.logAgain(item)
        let again = try #require(model.entries(on: model.today).first { $0.foodID == Foods.bananaID })
        #expect(abs(again.nutrients.kcal - 180) < 0.01)
        #expect(abs(again.nutrients.protein - 3) < 0.01)
        #expect(again.grams == 150, "the same amount")
        #expect(model.toast?.message.contains("180 kcal") == true)
    }

    @Test func aCatalogMatchIsLoggedAtTheCorrectedNumbers() throws {
        let model = TestEnvironment().model()
        model.onboard()
        try correctBanana(model)
        // A description matched the catalog's banana, as the model's candidates can.
        let catalogs = try #require(model.catalog.food(id: Foods.bananaID))
        let entry = model.entry(for: catalogs, count: 100, unit: try model.requireUnit(catalogs, "g"), source: .description, confidence: 0.8)
        model.log([entry])

        let logged = try #require(model.entries(on: model.today).first)
        #expect(logged.id == entry.id)
        #expect(logged.nutrients.kcal == 120)
        #expect(logged.confidence == 0.8 && logged.amountLabel.hasPrefix("≈"), "still an estimate")
    }

    @Test func takingACorrectionAwayGivesTheCatalogsNumbersBack() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        try correctBanana(model)
        // The personal foods are rebuilt with the correction, and must not keep it for the catalog's.
        #expect(await eventually(timeout: .seconds(30)) { model.personalFood(Foods.bananaID)?.food.nutrients.kcal == 120 })

        let original = try #require(model.removeCorrection(of: Foods.bananaID))
        #expect(abs(original.nutrients.kcal - 89) < 0.01)
        #expect(!model.isCorrected(Foods.bananaID))
        #expect(abs((model.food(id: Foods.bananaID)?.nutrients.kcal ?? 0) - 89) < 0.01)
        let entry = try model.entry(foodID: Foods.bananaID, grams: 100)
        model.log([entry])
        #expect(abs((model.entries(on: model.today).first?.nutrients.kcal ?? 0) - 89) < 0.01)
    }

    @Test func correctingTheirOwnFoodChangesItInPlace() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let label = Food(
            id: "label", name: "Granola", barcode: "00012345678905", basis: .g,
            nutrients: Nutrients(kcal: 450, protein: 10, carbs: 60, fat: 18), source: .label)
        let saved = model.save(customFood: label)
        let grams = try model.requireUnit(saved, "g")
        var edited = try #require(saved.correcting(kcal: 200, protein: 5, carbs: 27, fat: 8, count: 50, unit: grams))
        edited.name = "Granola, maple"

        let resaved = model.saveCorrection(edited)
        #expect(resaved.id == saved.id)
        #expect(model.customFoods.count == 1)
        #expect(model.corrections.isEmpty)
        #expect(model.food(barcode: "00012345678905")?.nutrients.kcal == 400)
        #expect(model.food(id: saved.id)?.name == "Granola, maple")
    }
}
