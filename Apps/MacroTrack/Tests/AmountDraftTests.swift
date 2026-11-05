import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// The amount panel's numbers apart from the panel: what it says is what Save stores, a correction
/// reaches the units it's counted in, and what's typed goes with a food taken elsewhere.
@MainActor
struct AmountDraftTests {
    /// A food logged long enough ago that nothing about today can touch it.
    let eaten = Date(timeIntervalSince1970: 1_790_000_000)

    func model() -> AppModel {
        let model = TestEnvironment().model()
        model.onboard()
        return model
    }

    /// Bananas with `kcal` per 100 g, where USDA has 89.
    @discardableResult
    func correctBanana(_ model: AppModel, kcal: Double) throws -> Food {
        let banana = try #require(model.catalog.food(id: Foods.bananaID))
        let grams = try model.requireUnit(banana, "g")
        return model.saveCorrection(try #require(banana.correcting(kcal: kcal, protein: 1, carbs: 22, fat: 0.3, count: 100, unit: grams)))
    }

    /// A logged food at a count of a unit.
    func logged(_ model: AppModel, count: Double, unitID: String) throws -> FoodEntry {
        let banana = try model.requireFood(Foods.bananaID)
        let unit = try model.requireUnit(banana, unitID)
        let entry = model.entry(for: banana, count: count, unit: unit, source: .search, date: eaten)
        model.log([entry])
        model.toast = nil
        return entry
    }

    func unit(_ draft: AmountDraft, _ id: String) throws -> PortionUnit { try #require(draft.units.first { $0.id == id }) }

    // MARK: What it says is what it saves

    /// Foods already logged keep their numbers, so a correction made from one can't change what
    /// Save says: the yogurt logged at 150 stays 150, however the package reads now.
    @Test func aCorrectionLeavesAnEntrysNumbersAsLogged() throws {
        let model = model()
        let entry = try logged(model, count: 100, unitID: "g")
        var draft = model.draft(for: .edit(entry))

        draft.use(try correctBanana(model, kcal: 200))

        #expect(draft.nutrients == entry.nutrients, "what the button reads")
        #expect(!draft.amountChanged)
        #expect(model.edited(draft, at: eaten)?.nutrients == entry.nutrients, "what Save stores")
    }

    @Test func anEntrysNewAmountIsAtTheCorrectedNumbers() throws {
        let model = model()
        let entry = try logged(model, count: 100, unitID: "g")
        var draft = model.draft(for: .edit(entry))
        draft.use(try correctBanana(model, kcal: 200))

        draft.amount.choose(50)

        #expect(abs(draft.nutrients.kcal - 100) < 0.01)
        #expect(abs((model.edited(draft, at: eaten)?.nutrients.kcal ?? 0) - 100) < 0.01, "the same as the button")
    }

    /// Going back to the amount it opened on is no change at all.
    @Test func anAmountPutBackKeepsTheEntrysNumbers() throws {
        let model = model()
        let entry = try logged(model, count: 100, unitID: "g")
        var draft = model.draft(for: .edit(entry))
        draft.use(try correctBanana(model, kcal: 200))

        draft.amount.choose(50)
        draft.amount.choose(100)

        #expect(draft.nutrients == entry.nutrients)
    }

    /// Calories are the one unit a correction changes the size of. Left as logged, the number stays
    /// beside the numbers it keeps, rather than 150 kcal over a Save of 120.
    @Test func anEntryCountedInCaloriesStaysAsLoggedThroughACorrection() throws {
        let model = model()
        let entry = try logged(model, count: 120, unitID: "kcal")
        var draft = model.draft(for: .edit(entry))

        draft.use(try correctBanana(model, kcal: 200))

        #expect(draft.amount.count == 120)
        #expect(!draft.amountChanged)
        #expect(draft.nutrients == entry.nutrients)
        #expect(model.edited(draft, at: eaten)?.amountLabel == entry.amountLabel)
    }

    @Test func aChangeOfTimeAloneKeepsTheEntrysNumbers() throws {
        let model = model()
        var entry = try logged(model, count: 100, unitID: "g")
        // As a catalog update might leave it: not what the food would give now.
        entry.nutrients.kcal = 1
        let later = eaten.addingTimeInterval(600)

        let edited = try #require(model.edited(model.draft(for: .edit(entry)), at: later))

        #expect(edited.nutrients.kcal == 1)
        #expect(edited.date == later)
    }

    /// With no entry behind it there's nothing to keep, so the correction shows at once.
    @Test func aFoodBeingAddedTakesACorrectionAtOnce() throws {
        let model = model()
        let banana = try model.requireFood(Foods.bananaID)
        var draft = model.draft(for: .add(banana, source: .search))
        let grams = try unit(draft, "g")
        draft.amount.change(to: grams)
        draft.amount.choose(100)

        draft.use(try correctBanana(model, kcal: 200))

        #expect(abs(draft.nutrients.kcal - 200) < 0.01)
    }

    // MARK: The units after a correction

    /// 60 g at 200 kcal per 100 g, corrected to 250: the chip holds the new calories, so the amount,
    /// the total and what's logged all say 150, not 120 over 150.
    @Test func theCalorieChipCountsTheCorrectedFood() throws {
        let model = model()
        try correctBanana(model, kcal: 200)
        var draft = model.draft(for: .add(try model.requireFood(Foods.bananaID), source: .search))
        draft.amount.change(to: try unit(draft, "g"))
        draft.amount.choose(60)

        draft.use(try correctBanana(model, kcal: 250))
        draft.amount.change(to: try unit(draft, "kcal"))

        #expect(draft.amount.count == 150)
        #expect(abs(draft.nutrients.kcal - 150) < 0.01)
    }

    @Test func theChipsKeepTheirPlaceThroughACorrection() throws {
        let model = model()
        var draft = model.draft(for: .add(try model.requireFood(Foods.bananaID), source: .search))
        let before = draft.units.map(\.id)
        draft.amount.change(to: try unit(draft, "kcal"))

        draft.use(try correctBanana(model, kcal: 200))

        #expect(draft.units.map(\.id) == before, "the chip tapped doesn't jump to the front")
    }

    /// A food with no calories can't be counted in them: it goes to its basis at the same amount.
    @Test func aFoodCorrectedToNoCaloriesLeavesTheCalorieUnit() throws {
        let model = model()
        try correctBanana(model, kcal: 200)
        var draft = model.draft(for: .add(try model.requireFood(Foods.bananaID), source: .search))
        draft.amount.change(to: try unit(draft, "kcal"))
        draft.amount.choose(120)

        draft.use(try correctBanana(model, kcal: 0))

        #expect(!draft.units.contains { $0.id == "kcal" })
        #expect(draft.amount.unit?.id == "g")
        #expect(draft.amount.count == 60)
    }

    // MARK: Taken elsewhere

    /// Tap a food at 100 g, type 200, Move, To Tomorrow: it goes at 200 g.
    @Test func moveTakesAnAmountTypedFirst() throws {
        let model = model()
        let entry = try logged(model, count: 100, unitID: "g")
        var draft = model.draft(for: .edit(entry))
        draft.amount.choose(200)

        model.take(draft, at: entry.date, intent: .move)
        model.placeSelection(on: [entry.day.adding(days: 1)])

        let moved = try #require(model.allEntries(on: entry.day.adding(days: 1)).first)
        #expect(moved.id == entry.id)
        #expect(moved.grams == 200)
        #expect(model.allEntries(on: entry.day).isEmpty)
    }

    /// A copy starts from the food as it stands on the panel, so the one it came from says the same.
    @Test func copyTakesAnAmountTypedFirst() throws {
        let model = model()
        let entry = try logged(model, count: 100, unitID: "g")
        var draft = model.draft(for: .edit(entry))
        draft.amount.choose(200)

        model.take(draft, at: entry.date, intent: .copy)
        model.placeSelection(on: [entry.day.adding(days: 1)])

        #expect(model.allEntries(on: entry.day).first?.grams == 200)
        #expect(model.allEntries(on: entry.day.adding(days: 1)).first?.grams == 200)
    }

    @Test func aMoveTakesATimeChangedFirst() throws {
        let model = model()
        let entry = try logged(model, count: 100, unitID: "g")
        let later = eaten.addingTimeInterval(600)

        model.take(model.draft(for: .edit(entry)), at: later, intent: .move)

        #expect(model.allEntries(on: entry.day).first?.date == later)
        #expect(model.selection.ids == [entry.id])
    }

    /// Nothing changed, nothing's written: an entry doesn't read as edited for being picked out.
    @Test func takingAFoodLeftAsItIsSavesNothing() throws {
        let model = model()
        let entry = try logged(model, count: 100, unitID: "g")
        let stored = try #require(model.allEntries(on: entry.day).first)

        model.take(model.draft(for: .edit(stored)), at: stored.date, intent: .move)

        #expect(model.allEntries(on: entry.day).first == stored)
        #expect(model.selection.ids == [entry.id])
    }
}
