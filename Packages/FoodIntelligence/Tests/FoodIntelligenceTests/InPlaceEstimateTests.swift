import FoodDatabase
import Foundation
import SystemCore
import Testing

@testable import FoodIntelligence

/// Words Today's composer matched to no food, read by the model and logged in place: what goes in,
/// what's said instead, and how sure each food is.
@Suite("In-place estimates")
struct InPlaceEstimateTests {
    let rice = food("Rice, white, cooked", kcal: 130, portions: [("1 cup", 158)])
    let beans = food("Beans, black, canned", kcal: 91, portions: [("1 cup", 172)])
    let cup = PortionUnit(id: "portion:0", label: "cup", kind: .portion, amount: 158)

    func guessed(
        _ name: String, _ food: Food?, unit: PortionUnit? = nil, count: Double = 1, sure: Bool = true, approximate: Bool = false
    ) -> GuessedItem {
        GuessedItem(
            seenName: name, seenBrand: nil, match: food.map { match($0, 3) }, alternatives: [], unit: food == nil ? nil : unit ?? cup,
            count: count, nutrients: .zero, sure: sure, approximate: approximate)
    }

    func guess(_ items: [GuessedItem]) -> MealGuess {
        MealGuess(scene: nil, isFood: true, items: items, engine: .onDevice, seconds: 1)
    }

    @Test func everyMatchedFoodIsLoggedAndWhatNothingMatchedIsSaid() throws {
        let read = guess([
            guessed("Rice", rice), guessed("Black beans", beans, sure: false), guessed("Salsa verde", nil), guessed("salsa verde", nil),
        ])
        guard case .foods(let items, let missed) = InPlaceEstimate.outcome(of: read, words: "burrito bowl") else {
            Issue.record("expected foods")
            return
        }
        // A weak match goes in too, as an estimate to confirm: a review is what's being skipped.
        #expect(items.map(\.seenName) == ["Rice", "Black beans"])
        #expect(missed == ["Salsa verde"], "named twice, said once")
        #expect(InPlaceEstimate.missing(from: "burrito bowl") == "Not in the catalog. Part of “burrito bowl”.")
    }

    @Test func nothingMatchedSaysWhatWasNamed() {
        let read = guess([guessed("Salsa verde", nil), guessed("Crema", nil)])
        guard case .nothing(let why) = InPlaceEstimate.outcome(of: read, words: "salsa verde with crema") else {
            Issue.record("expected nothing")
            return
        }
        #expect(why == "Nothing in the catalog for Salsa verde and Crema. Find it in the logger.")
    }

    @Test func noFoodsNamedAsksForEachOne() {
        guard case .nothing(let why) = InPlaceEstimate.outcome(of: guess([]), words: "the usual") else {
            Issue.record("expected nothing")
            return
        }
        #expect(why == "The model couldn't name a food in it. Try naming each one.")
    }

    @Test func aMatchWithNoAmountIsNotLogged() {
        let read = guess([guessed("Rice", rice, count: 0), guessed("Beans", beans, count: .nan)])
        guard case .nothing = InPlaceEstimate.outcome(of: read, words: "rice and beans") else {
            Issue.record("a food at nothing, or at no number, is nothing to log")
            return
        }
    }

    @Test func confidenceMarksHowSureTheEstimateIs() {
        #expect(guessed("Rice", rice).confidence == 0.8)
        #expect(guessed("Rice", rice, sure: false).confidence == 0.5)
        #expect(guessed("Rice", rice, approximate: true).confidence == 0.5)
    }

    @Test func namesAreListedTheWayTheyAreSaid() {
        #expect(InPlaceEstimate.spoken(["rice"]) == "rice")
        #expect(InPlaceEstimate.spoken(["rice", "beans"]) == "rice and beans")
        #expect(InPlaceEstimate.spoken(["rice", "beans", "salsa"]) == "rice, beans and salsa")
    }
}
