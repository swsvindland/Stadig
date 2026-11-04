import FoodDatabase
import FoodIntelligence
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// One logger, however it's logging: every way returns to the search, and the AI's review survives
/// a trip to search for one of its foods.
@MainActor
struct LoggerSessionTests {
    func review(_ model: AppModel, mode: LogMode = .describe) throws -> MealReview {
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        let nutrients = Nutrients(kcal: 100, protein: 1, carbs: 25, fat: 0)
        func seen() -> GuessedItem {
            GuessedItem(
                id: UUID(), seenName: "banana", seenBrand: nil, match: nil, alternatives: [], unit: grams, count: 120, nutrients: nutrients,
                sure: true,
                approximate: false)
        }
        var review = MealReview(
            guess: MealGuess(scene: nil, isFood: true, items: [seen(), seen()], engine: .onDevice, seconds: 1), source: .description, mode: mode,
            corrected: { $0 })
        review.items[0].food = banana
        review.items[0].unit = grams
        review.items[0].included = true
        return review
    }

    @Test func everyWayEndsBackAtTheSearch() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.query = "banana"
        session.review = try review(model)

        session.backToSearch()

        #expect(session.mode == .search)
        #expect(session.review == nil)
        #expect(session.query.isEmpty)
    }

    @Test func goingOffToSearchKeepsTheReview() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        let unmatched = try #require(session.review?.items[1])
        #expect(unmatched.food == nil)

        session.find("banana", for: unmatched.id)
        #expect(session.mode == .search)
        #expect(session.query == "banana")
        #expect(session.review != nil)

        let found = try model.requireFood(Foods.coffeeID)
        session.use(found)

        #expect(session.mode == .describe)
        #expect(session.query.isEmpty)
        #expect(session.finding == nil)
        #expect(session.review?.items.count == 2)
        #expect(session.review?.items[1].food?.id == Foods.coffeeID)
        #expect(session.review?.items[1].included == true)
    }

    @Test func comingBackWithoutOneChangesNothing() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .camera)
        session.review = try review(model, mode: .camera)
        let unmatched = try #require(session.review?.items[1])
        session.find("banana", for: unmatched.id)

        session.stopFinding()

        #expect(session.mode == .camera)
        #expect(session.review?.items[1].food == nil)
        #expect(session.finding == nil)
    }

    @Test func aFoodsNewAmountStaysInItsUnit() throws {
        let model = TestEnvironment().model()
        model.onboard()
        var item = try #require(try review(model).items.first)
        let coffee = try model.requireFood(Foods.coffeeID)
        item.count = 150
        item.swap(to: coffee)
        #expect(item.count == 150)
        #expect(item.unit?.id == "g")
    }
}
